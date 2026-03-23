--------------------------------------------------------------------------------
-- INCIDENT DEBUGGER - Supporting Objects Setup
-- Run this script with ACCOUNTADMIN or a role with CREATE privileges
-- 
-- This creates:
--   1. OBSERVABILITY schema
--   2. INCIDENT_LOG table (stores all investigations)
--   3. INCIDENT_CATEGORIES reference table (6 default categories)
--   4. NOTIFICATION_ROUTING configuration table
--   5. V_INCIDENT_EVIDENCE helper view (pre-joined diagnostics)
--   6. V_TASK_FAILURE_SUMMARY view (task failure aggregation)
--   7. CLASSIFY_ERROR_CATEGORY UDF
--   8. CALCULATE_CONFIDENCE UDF
--   9. LOG_INCIDENT stored procedure
--   10. UPDATE_REMEDIATION_STATUS stored procedure
--------------------------------------------------------------------------------

USE ROLE ACCOUNTADMIN;

--------------------------------------------------------------------------------
-- 1. Create dedicated schema for incident debugger objects
--------------------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS OBSERVABILITY_DB;
CREATE SCHEMA IF NOT EXISTS OBSERVABILITY_DB.OBSERVABILITY;

USE SCHEMA OBSERVABILITY_DB.OBSERVABILITY;

--------------------------------------------------------------------------------
-- 2. INCIDENT_LOG Table - Stores all incident investigations
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS INCIDENT_LOG (
    INCIDENT_ID             VARCHAR(36) DEFAULT UUID_STRING() PRIMARY KEY,
    CREATED_AT              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    INVESTIGATED_BY         VARCHAR(256) DEFAULT CURRENT_USER(),
    INVESTIGATING_ROLE      VARCHAR(256) DEFAULT CURRENT_ROLE(),
    
    INCIDENT_TYPE           VARCHAR(50) NOT NULL,
    OBJECT_NAME             VARCHAR(512),
    QUERY_ID                VARCHAR(256),
    TASK_NAME               VARCHAR(256),
    DATABASE_NAME           VARCHAR(256),
    SCHEMA_NAME             VARCHAR(256),
    WAREHOUSE_NAME          VARCHAR(256),
    
    INCIDENT_START_TIME     TIMESTAMP_NTZ,
    INCIDENT_END_TIME       TIMESTAMP_NTZ,
    DETECTION_LATENCY_SEC   NUMBER(10,2),
    
    ERROR_CODE              VARCHAR(50),
    ERROR_MESSAGE           TEXT,
    ERROR_CATEGORY          VARCHAR(100),
    
    ROOT_CAUSE_CATEGORY     VARCHAR(100) NOT NULL,
    ROOT_CAUSE_SUMMARY      TEXT NOT NULL,
    CONFIDENCE_SCORE        VARCHAR(10) NOT NULL,
    CONFIDENCE_PERCENTAGE   NUMBER(5,2),
    ALTERNATIVE_HYPOTHESES  VARIANT,
    EVIDENCE_REFERENCES     VARIANT,
    
    EVENT_TIMELINE          VARIANT,
    CONCURRENT_EVENTS       VARIANT,
    
    IS_RECURRING            BOOLEAN DEFAULT FALSE,
    RECURRENCE_COUNT        NUMBER(10) DEFAULT 0,
    FIRST_OCCURRENCE        TIMESTAMP_NTZ,
    PATTERN_DESCRIPTION     TEXT,
    
    REMEDIATION_SUGGESTED   VARIANT,
    REMEDIATION_APPLIED     VARIANT,
    REMEDIATION_STATUS      VARCHAR(50) DEFAULT 'PENDING',
    REMEDIATION_APPLIED_AT  TIMESTAMP_NTZ,
    REMEDIATION_APPLIED_BY  VARCHAR(256),
    
    TIME_TO_DIAGNOSE_SEC    NUMBER(10,2),
    TIME_TO_RESOLVE_SEC     NUMBER(10,2),
    
    NOTIFICATION_SENT       BOOLEAN DEFAULT FALSE,
    NOTIFICATION_RECIPIENTS VARIANT,
    NOTIFICATION_SENT_AT    TIMESTAMP_NTZ,
    
    RAW_EVIDENCE            VARIANT
);

COMMENT ON TABLE INCIDENT_LOG IS 'Stores all incident investigations performed by Incident Debugger skill';

--------------------------------------------------------------------------------
-- 3. INCIDENT_CATEGORIES Reference Table
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS INCIDENT_CATEGORIES (
    CATEGORY_ID         VARCHAR(50) PRIMARY KEY,
    CATEGORY_NAME       VARCHAR(100) NOT NULL,
    DESCRIPTION         TEXT,
    SEVERITY_DEFAULT    VARCHAR(20) DEFAULT 'MEDIUM',
    AUTO_REMEDIATE      BOOLEAN DEFAULT FALSE,
    NOTIFICATION_TIER   VARCHAR(20) DEFAULT 'STANDARD',
    RUNBOOK_URL         VARCHAR(1000),
    CREATED_AT          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

MERGE INTO INCIDENT_CATEGORIES tgt
USING (
    SELECT column1 AS CATEGORY_ID, column2 AS CATEGORY_NAME, column3 AS DESCRIPTION, 
           column4 AS SEVERITY_DEFAULT, column5 AS AUTO_REMEDIATE, column6 AS NOTIFICATION_TIER
    FROM VALUES
        ('QUERY_LOGIC', 'Query Logic Error', 'SQL syntax errors, invalid references, type mismatches', 'MEDIUM', FALSE, 'STANDARD'),
        ('PERMISSION', 'Permission/Privilege Gap', 'Missing GRANT, role issues, object access denied', 'HIGH', FALSE, 'URGENT'),
        ('WAREHOUSE', 'Warehouse Resource Issue', 'Suspension, timeout, capacity, scaling failures', 'HIGH', TRUE, 'URGENT'),
        ('DATA_QUALITY', 'Data Quality/Schema Mismatch', 'Schema drift, malformed data, constraint violations', 'MEDIUM', FALSE, 'STANDARD'),
        ('AUTH_NETWORK', 'Authentication/Network Failure', 'Login failures, MFA issues, network policy blocks', 'CRITICAL', FALSE, 'CRITICAL'),
        ('TASK_DEPENDENCY', 'Task Dependency Failure', 'Upstream task failures, DAG issues, scheduling conflicts', 'MEDIUM', FALSE, 'STANDARD')
) src
ON tgt.CATEGORY_ID = src.CATEGORY_ID
WHEN NOT MATCHED THEN INSERT (CATEGORY_ID, CATEGORY_NAME, DESCRIPTION, SEVERITY_DEFAULT, AUTO_REMEDIATE, NOTIFICATION_TIER)
VALUES (src.CATEGORY_ID, src.CATEGORY_NAME, src.DESCRIPTION, src.SEVERITY_DEFAULT, src.AUTO_REMEDIATE, src.NOTIFICATION_TIER);

--------------------------------------------------------------------------------
-- 4. NOTIFICATION_ROUTING Configuration Table
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS NOTIFICATION_ROUTING (
    ROUTING_ID          VARCHAR(36) DEFAULT UUID_STRING() PRIMARY KEY,
    CATEGORY_ID         VARCHAR(50),
    SEVERITY            VARCHAR(20),
    DATABASE_PATTERN    VARCHAR(256) DEFAULT '*',
    SCHEMA_PATTERN      VARCHAR(256) DEFAULT '*',
    TASK_PATTERN        VARCHAR(256) DEFAULT '*',
    NOTIFICATION_TYPE   VARCHAR(50) NOT NULL,
    RECIPIENTS          VARIANT NOT NULL,
    ENABLED             BOOLEAN DEFAULT TRUE,
    CREATED_AT          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CREATED_BY          VARCHAR(256) DEFAULT CURRENT_USER()
);

COMMENT ON TABLE NOTIFICATION_ROUTING IS 'Configures notification routing rules by category, severity, and object patterns';

--------------------------------------------------------------------------------
-- 5. V_INCIDENT_EVIDENCE - Pre-joined diagnostic view
--------------------------------------------------------------------------------
CREATE OR REPLACE VIEW V_INCIDENT_EVIDENCE AS
WITH task_failures AS (
    SELECT 
        th.NAME AS task_name,
        th.DATABASE_NAME,
        th.SCHEMA_NAME,
        th.QUERY_ID,
        th.STATE,
        th.ERROR_CODE,
        th.ERROR_MESSAGE,
        th.SCHEDULED_TIME,
        th.COMPLETED_TIME,
        th.QUERY_START_TIME,
        th.ROOT_TASK_ID,
        th.GRAPH_RUN_GROUP_ID,
        DATEDIFF('second', th.SCHEDULED_TIME, th.COMPLETED_TIME) AS duration_sec
    FROM SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY th
    WHERE th.STATE = 'FAILED'
      AND th.COMPLETED_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
),
query_details AS (
    SELECT 
        qh.QUERY_ID,
        qh.QUERY_TEXT,
        qh.ERROR_CODE AS query_error_code,
        qh.ERROR_MESSAGE AS query_error_message,
        qh.EXECUTION_STATUS,
        qh.WAREHOUSE_NAME,
        qh.WAREHOUSE_SIZE,
        qh.BYTES_SCANNED,
        qh.ROWS_PRODUCED,
        qh.COMPILATION_TIME,
        qh.EXECUTION_TIME,
        qh.QUEUED_PROVISIONING_TIME,
        qh.QUEUED_OVERLOAD_TIME,
        qh.START_TIME AS query_start_time,
        qh.END_TIME AS query_end_time,
        qh.USER_NAME,
        qh.ROLE_NAME
    FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY qh
    WHERE qh.START_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
)
SELECT 
    tf.task_name,
    tf.DATABASE_NAME,
    tf.SCHEMA_NAME,
    tf.QUERY_ID,
    tf.STATE AS task_state,
    tf.ERROR_CODE AS task_error_code,
    tf.ERROR_MESSAGE AS task_error_message,
    tf.SCHEDULED_TIME,
    tf.COMPLETED_TIME,
    tf.QUERY_START_TIME,
    tf.ROOT_TASK_ID,
    tf.GRAPH_RUN_GROUP_ID,
    tf.duration_sec,
    qd.QUERY_TEXT,
    qd.query_error_code,
    qd.query_error_message,
    qd.EXECUTION_STATUS,
    qd.WAREHOUSE_NAME,
    qd.WAREHOUSE_SIZE,
    qd.BYTES_SCANNED,
    qd.COMPILATION_TIME / 1000 AS compile_sec,
    qd.EXECUTION_TIME / 1000 AS exec_sec,
    qd.QUEUED_PROVISIONING_TIME / 1000 AS queue_provision_sec,
    qd.QUEUED_OVERLOAD_TIME / 1000 AS queue_overload_sec,
    qd.USER_NAME,
    qd.ROLE_NAME
FROM task_failures tf
LEFT JOIN query_details qd ON tf.QUERY_ID = qd.QUERY_ID;

--------------------------------------------------------------------------------
-- 6. V_TASK_FAILURE_SUMMARY - Aggregated task failure view
--------------------------------------------------------------------------------
CREATE OR REPLACE VIEW V_TASK_FAILURE_SUMMARY AS
SELECT 
    DATABASE_NAME,
    SCHEMA_NAME,
    NAME AS task_name,
    COUNT(*) AS total_failures,
    COUNT(DISTINCT DATE_TRUNC('day', COMPLETED_TIME)) AS days_with_failures,
    MIN(COMPLETED_TIME) AS first_failure,
    MAX(COMPLETED_TIME) AS last_failure,
    LISTAGG(DISTINCT ERROR_CODE, ', ') WITHIN GROUP (ORDER BY ERROR_CODE) AS error_codes,
    MODE(ERROR_MESSAGE) AS most_common_error,
    AVG(DATEDIFF('second', SCHEDULED_TIME, COMPLETED_TIME)) AS avg_duration_sec
FROM SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY
WHERE STATE = 'FAILED'
  AND COMPLETED_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY DATABASE_NAME, SCHEMA_NAME, NAME
ORDER BY total_failures DESC;

--------------------------------------------------------------------------------
-- 7. UDF: Classify Error Category
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION CLASSIFY_ERROR_CATEGORY(
    error_code VARCHAR,
    error_message VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
    CASE
        WHEN error_code IN ('002003', '003001', '090106') 
          OR LOWER(error_message) LIKE '%permission denied%'
          OR LOWER(error_message) LIKE '%insufficient privileges%'
          OR LOWER(error_message) LIKE '%access denied%'
          OR LOWER(error_message) LIKE '%not authorized%'
          OR LOWER(error_message) LIKE '%does not exist or not authorized%'
        THEN 'PERMISSION'
        
        WHEN error_code IN ('090001', '090002', '390114')
          OR LOWER(error_message) LIKE '%warehouse%suspended%'
          OR LOWER(error_message) LIKE '%warehouse%timeout%'
          OR LOWER(error_message) LIKE '%statement timeout%'
          OR LOWER(error_message) LIKE '%resource%unavailable%'
          OR LOWER(error_message) LIKE '%queue%timeout%'
        THEN 'WAREHOUSE'
        
        WHEN error_code IN ('100038', '100069', '100071', '100072')
          OR LOWER(error_message) LIKE '%schema%mismatch%'
          OR LOWER(error_message) LIKE '%column%not found%'
          OR LOWER(error_message) LIKE '%invalid identifier%'
          OR LOWER(error_message) LIKE '%type%mismatch%'
          OR LOWER(error_message) LIKE '%constraint%violation%'
          OR LOWER(error_message) LIKE '%invalid%format%'
          OR LOWER(error_message) LIKE '%null value%'
        THEN 'DATA_QUALITY'
        
        WHEN error_code IN ('390100', '390101', '390144', '390318')
          OR LOWER(error_message) LIKE '%authentication%'
          OR LOWER(error_message) LIKE '%login%failed%'
          OR LOWER(error_message) LIKE '%network%policy%'
          OR LOWER(error_message) LIKE '%session%expired%'
          OR LOWER(error_message) LIKE '%mfa%'
        THEN 'AUTH_NETWORK'
        
        WHEN LOWER(error_message) LIKE '%predecessor%'
          OR LOWER(error_message) LIKE '%upstream%task%'
          OR LOWER(error_message) LIKE '%dependency%'
          OR LOWER(error_message) LIKE '%graph%failed%'
          OR LOWER(error_message) LIKE '%dag%'
        THEN 'TASK_DEPENDENCY'
        
        ELSE 'QUERY_LOGIC'
    END
$$;

COMMENT ON FUNCTION CLASSIFY_ERROR_CATEGORY(VARCHAR, VARCHAR) IS 'Classifies Snowflake errors into one of 6 incident categories';

--------------------------------------------------------------------------------
-- 8. UDF: Calculate Confidence Score
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION CALCULATE_CONFIDENCE(
    evidence_count NUMBER,
    category_match_strength NUMBER,
    pattern_confirmed BOOLEAN
)
RETURNS OBJECT
LANGUAGE SQL
AS
$$
    SELECT OBJECT_CONSTRUCT(
        'level', CASE 
            WHEN evidence_count >= 3 AND category_match_strength >= 8 THEN 'HIGH'
            WHEN evidence_count >= 2 AND category_match_strength >= 5 THEN 'MEDIUM'
            ELSE 'LOW'
        END,
        'percentage', LEAST(100, GREATEST(0,
            (evidence_count * 15) + 
            (category_match_strength * 5) + 
            (IFF(pattern_confirmed, 20, 0))
        ))
    )
$$;

COMMENT ON FUNCTION CALCULATE_CONFIDENCE(NUMBER, NUMBER, BOOLEAN) IS 'Calculates confidence level and percentage for RCA based on evidence strength';

--------------------------------------------------------------------------------
-- 9. Stored Procedure: Log Incident
--------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE LOG_INCIDENT(
    p_incident_type VARCHAR,
    p_object_name VARCHAR,
    p_query_id VARCHAR,
    p_task_name VARCHAR,
    p_database_name VARCHAR,
    p_schema_name VARCHAR,
    p_warehouse_name VARCHAR,
    p_incident_start_time TIMESTAMP_NTZ,
    p_error_code VARCHAR,
    p_error_message VARCHAR,
    p_root_cause_category VARCHAR,
    p_root_cause_summary VARCHAR,
    p_confidence_score VARCHAR,
    p_confidence_percentage NUMBER,
    p_is_recurring BOOLEAN,
    p_recurrence_count NUMBER,
    p_evidence_references VARIANT,
    p_event_timeline VARIANT,
    p_remediation_suggested VARIANT,
    p_raw_evidence VARIANT
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    v_incident_id VARCHAR;
    v_detection_latency NUMBER;
BEGIN
    v_detection_latency := DATEDIFF('second', p_incident_start_time, CURRENT_TIMESTAMP());
    
    INSERT INTO OBSERVABILITY_DB.OBSERVABILITY.INCIDENT_LOG (
        INCIDENT_TYPE, OBJECT_NAME, QUERY_ID, TASK_NAME,
        DATABASE_NAME, SCHEMA_NAME, WAREHOUSE_NAME,
        INCIDENT_START_TIME, INCIDENT_END_TIME, DETECTION_LATENCY_SEC,
        ERROR_CODE, ERROR_MESSAGE, ERROR_CATEGORY,
        ROOT_CAUSE_CATEGORY, ROOT_CAUSE_SUMMARY,
        CONFIDENCE_SCORE, CONFIDENCE_PERCENTAGE,
        IS_RECURRING, RECURRENCE_COUNT,
        EVIDENCE_REFERENCES, EVENT_TIMELINE,
        REMEDIATION_SUGGESTED, REMEDIATION_STATUS,
        RAW_EVIDENCE
    )
    VALUES (
        :p_incident_type,
        :p_object_name,
        :p_query_id,
        :p_task_name,
        :p_database_name,
        :p_schema_name,
        :p_warehouse_name,
        :p_incident_start_time,
        CURRENT_TIMESTAMP(),
        :v_detection_latency,
        :p_error_code,
        :p_error_message,
        OBSERVABILITY_DB.OBSERVABILITY.CLASSIFY_ERROR_CATEGORY(:p_error_code, :p_error_message),
        :p_root_cause_category,
        :p_root_cause_summary,
        :p_confidence_score,
        :p_confidence_percentage,
        :p_is_recurring,
        :p_recurrence_count,
        :p_evidence_references,
        :p_event_timeline,
        :p_remediation_suggested,
        'PENDING',
        :p_raw_evidence
    );
    
    SELECT INCIDENT_ID INTO :v_incident_id 
    FROM OBSERVABILITY_DB.OBSERVABILITY.INCIDENT_LOG 
    WHERE INVESTIGATED_BY = CURRENT_USER()
    ORDER BY CREATED_AT DESC 
    LIMIT 1;
    
    RETURN v_incident_id;
END;
$$;

COMMENT ON PROCEDURE LOG_INCIDENT(VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, TIMESTAMP_NTZ, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, NUMBER, BOOLEAN, NUMBER, VARIANT, VARIANT, VARIANT, VARIANT) 
IS 'Logs an incident investigation to the INCIDENT_LOG table and returns the incident ID';

--------------------------------------------------------------------------------
-- 10. Stored Procedure: Update Remediation Status
--------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE UPDATE_REMEDIATION_STATUS(
    p_incident_id VARCHAR,
    p_status VARCHAR,
    p_remediation_applied VARIANT
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    UPDATE OBSERVABILITY_DB.OBSERVABILITY.INCIDENT_LOG
    SET REMEDIATION_STATUS = :p_status,
        REMEDIATION_APPLIED = :p_remediation_applied,
        REMEDIATION_APPLIED_AT = CURRENT_TIMESTAMP(),
        REMEDIATION_APPLIED_BY = CURRENT_USER(),
        TIME_TO_RESOLVE_SEC = DATEDIFF('second', INCIDENT_START_TIME, CURRENT_TIMESTAMP())
    WHERE INCIDENT_ID = :p_incident_id;
    
    RETURN 'Remediation status updated to ' || :p_status;
END;
$$;

COMMENT ON PROCEDURE UPDATE_REMEDIATION_STATUS(VARCHAR, VARCHAR, VARIANT)
IS 'Updates the remediation status for an incident after fix is applied';

--------------------------------------------------------------------------------
-- Grant permissions (customize role names as needed)
--------------------------------------------------------------------------------
-- Example grants for a DATA_ENGINEER role:
-- GRANT USAGE ON DATABASE OBSERVABILITY_DB TO ROLE DATA_ENGINEER;
-- GRANT USAGE ON SCHEMA OBSERVABILITY_DB.OBSERVABILITY TO ROLE DATA_ENGINEER;
-- GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA OBSERVABILITY_DB.OBSERVABILITY TO ROLE DATA_ENGINEER;
-- GRANT SELECT ON ALL VIEWS IN SCHEMA OBSERVABILITY_DB.OBSERVABILITY TO ROLE DATA_ENGINEER;
-- GRANT USAGE ON ALL FUNCTIONS IN SCHEMA OBSERVABILITY_DB.OBSERVABILITY TO ROLE DATA_ENGINEER;
-- GRANT USAGE ON ALL PROCEDURES IN SCHEMA OBSERVABILITY_DB.OBSERVABILITY TO ROLE DATA_ENGINEER;

--------------------------------------------------------------------------------
-- Verify installation
--------------------------------------------------------------------------------
SELECT 'INCIDENT_LOG' AS object_name, COUNT(*) AS exists_check FROM OBSERVABILITY_DB.OBSERVABILITY.INCIDENT_LOG
UNION ALL
SELECT 'INCIDENT_CATEGORIES', COUNT(*) FROM OBSERVABILITY_DB.OBSERVABILITY.INCIDENT_CATEGORIES
UNION ALL
SELECT 'NOTIFICATION_ROUTING', COUNT(*) FROM OBSERVABILITY_DB.OBSERVABILITY.NOTIFICATION_ROUTING;

SELECT 'Setup complete! Objects created in OBSERVABILITY_DB.OBSERVABILITY schema.' AS status;
