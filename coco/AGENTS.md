# Incident Debugger - Agent Configuration

## Skill Overview

The Incident Debugger skill provides automated root cause analysis for failed queries, tasks, and pipelines in Snowflake. It gathers evidence from system views, reconstructs timelines, and synthesizes actionable remediation recommendations.

## Prerequisites

Before using this skill, run the setup script to create required objects:

```sql
-- Execute as ACCOUNTADMIN
@incident_debugger_setup.sql
```

This creates:
- `OBSERVABILITY_DB.OBSERVABILITY.INCIDENT_LOG` - Investigation audit trail
- `OBSERVABILITY_DB.OBSERVABILITY.INCIDENT_CATEGORIES` - Category reference
- `OBSERVABILITY_DB.OBSERVABILITY.NOTIFICATION_ROUTING` - Alert routing rules
- Helper views and UDFs

## Required Privileges

Grant IMPORTED PRIVILEGES on SNOWFLAKE database to query ACCOUNT_USAGE views:

```sql
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE <your_role>;
GRANT USAGE ON DATABASE OBSERVABILITY_DB TO ROLE <your_role>;
GRANT USAGE ON SCHEMA OBSERVABILITY_DB.OBSERVABILITY TO ROLE <your_role>;
GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA OBSERVABILITY_DB.OBSERVABILITY TO ROLE <your_role>;
```

---

## Custom Incident Categories

Add custom categories beyond the 6 defaults:

```sql
INSERT INTO OBSERVABILITY_DB.OBSERVABILITY.INCIDENT_CATEGORIES 
    (CATEGORY_ID, CATEGORY_NAME, DESCRIPTION, SEVERITY_DEFAULT, AUTO_REMEDIATE, NOTIFICATION_TIER, RUNBOOK_URL)
VALUES
    ('DBT_MODEL', 'dbt Model Failure', 'Failures in dbt run, test, or snapshot', 'MEDIUM', FALSE, 'STANDARD', 'https://wiki.company.com/dbt-runbook'),
    ('STREAMLIT', 'Streamlit App Error', 'Streamlit in Snowflake app errors', 'LOW', FALSE, 'STANDARD', NULL),
    ('ML_PIPELINE', 'ML Pipeline Failure', 'ML training or inference failures', 'HIGH', FALSE, 'URGENT', NULL),
    ('CORTEX', 'Cortex AI Failure', 'Cortex LLM or ML function errors', 'MEDIUM', FALSE, 'STANDARD', NULL);
```

---

## Notification Routing Configuration

### Route by Category and Severity

```sql
-- Critical auth failures → Security team
INSERT INTO OBSERVABILITY_DB.OBSERVABILITY.NOTIFICATION_ROUTING 
    (CATEGORY_ID, SEVERITY, NOTIFICATION_TYPE, RECIPIENTS)
VALUES
    ('AUTH_NETWORK', 'CRITICAL', 'EMAIL', PARSE_JSON('["security-team@company.com"]'));

-- Warehouse issues → Platform team
INSERT INTO OBSERVABILITY_DB.OBSERVABILITY.NOTIFICATION_ROUTING 
    (CATEGORY_ID, SEVERITY, NOTIFICATION_TYPE, RECIPIENTS)
VALUES
    ('WAREHOUSE', 'HIGH', 'EMAIL', PARSE_JSON('["platform-team@company.com"]'));

-- Permission issues in PROD → Data governance
INSERT INTO OBSERVABILITY_DB.OBSERVABILITY.NOTIFICATION_ROUTING 
    (CATEGORY_ID, DATABASE_PATTERN, NOTIFICATION_TYPE, RECIPIENTS)
VALUES
    ('PERMISSION', 'PROD_%', 'EMAIL', PARSE_JSON('["data-governance@company.com"]'));
```

### Route by Schema Pattern

```sql
-- All ANALYTICS schema failures → Analytics team
INSERT INTO OBSERVABILITY_DB.OBSERVABILITY.NOTIFICATION_ROUTING 
    (CATEGORY_ID, SCHEMA_PATTERN, NOTIFICATION_TYPE, RECIPIENTS)
VALUES
    (NULL, 'ANALYTICS', 'EMAIL', PARSE_JSON('["analytics-team@company.com"]'));

-- ETL task failures → Data engineering
INSERT INTO OBSERVABILITY_DB.OBSERVABILITY.NOTIFICATION_ROUTING 
    (CATEGORY_ID, TASK_PATTERN, NOTIFICATION_TYPE, RECIPIENTS)
VALUES
    ('TASK_DEPENDENCY', 'ETL_%', 'EMAIL', PARSE_JSON('["data-engineering@company.com"]'));
```

---

## Skill Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `lookback_hours` | integer | 24 | Hours to search for incident evidence |
| `include_concurrent_queries` | boolean | true | Include warehouse contention analysis |
| `auto_log_incident` | boolean | true | Log investigation to INCIDENT_LOG |
| `confidence_threshold` | string | MEDIUM | Min confidence for remediation (LOW/MEDIUM/HIGH) |

---

## Invocation Examples

### Basic Task Investigation
```
Debug why task LOAD_ORDERS_TASK failed this morning
```

### Query by ID
```
Investigate query 01b4d5e6-0000-1234-0000-00000000abcd
```

### Error Message Search
```
Diagnose "Object does not exist" errors in ANALYTICS schema
```

### Data Load Failures
```
RCA for COPY INTO failures on STAGING.RAW_EVENTS
```

### Authentication Issues
```
Why is service account ETL_USER failing to login?
```

### Broad Investigation
```
Investigate all pipeline failures last night between 2am and 6am
```

---

## Follow-Up Questions

After initial investigation, ask:

| Question | What It Does |
|----------|--------------|
| "Was this failing before?" | Checks recurrence pattern over 30 days |
| "Show me the full query" | Retrieves complete QUERY_TEXT |
| "What depends on this task?" | Shows downstream task dependencies |
| "Who else uses this warehouse?" | Lists users with concurrent activity |
| "What changed recently?" | Finds ALTER/DROP/CREATE on related objects |
| "Apply the fix" | Executes suggested remediation (with approval) |
| "Log this incident" | Persists investigation to INCIDENT_LOG |
| "Compare to last success" | Diffs conditions vs last successful run |

---

## Escalation Rules

Configure automatic escalation thresholds:

```sql
-- Add custom metadata to categories for escalation logic
UPDATE OBSERVABILITY_DB.OBSERVABILITY.INCIDENT_CATEGORIES
SET NOTIFICATION_TIER = 'CRITICAL'
WHERE CATEGORY_ID IN ('AUTH_NETWORK', 'PERMISSION');

-- Track escalation in notification routing
INSERT INTO OBSERVABILITY_DB.OBSERVABILITY.NOTIFICATION_ROUTING 
    (CATEGORY_ID, SEVERITY, NOTIFICATION_TYPE, RECIPIENTS)
VALUES
    (NULL, 'CRITICAL', 'EMAIL', PARSE_JSON('["oncall@company.com", "manager@company.com"]'));
```

---

## Remediation Approval Rules

The skill follows these safety rules:

**Always require approval:**
- DROP, DELETE, TRUNCATE commands
- REVOKE statements
- ALTER...OWNER statements

**Can suggest without approval (display only):**
- SHOW GRANTS, DESCRIBE, SELECT queries
- Diagnostic queries

**Executable with confirmation:**
- GRANT SELECT/INSERT/UPDATE
- ALTER WAREHOUSE RESUME
- EXECUTE TASK

---

## Audit & Compliance

View investigation history:

```sql
-- Recent investigations
SELECT 
    INCIDENT_ID,
    CREATED_AT,
    INVESTIGATED_BY,
    INCIDENT_TYPE,
    OBJECT_NAME,
    ROOT_CAUSE_CATEGORY,
    CONFIDENCE_SCORE,
    REMEDIATION_STATUS
FROM OBSERVABILITY_DB.OBSERVABILITY.INCIDENT_LOG
ORDER BY CREATED_AT DESC
LIMIT 20;

-- Incidents by category (last 30 days)
SELECT 
    ROOT_CAUSE_CATEGORY,
    COUNT(*) AS incident_count,
    AVG(CONFIDENCE_PERCENTAGE) AS avg_confidence,
    AVG(TIME_TO_DIAGNOSE_SEC) AS avg_diagnose_time_sec
FROM OBSERVABILITY_DB.OBSERVABILITY.INCIDENT_LOG
WHERE CREATED_AT >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY ROOT_CAUSE_CATEGORY
ORDER BY incident_count DESC;

-- Recurring incidents
SELECT 
    OBJECT_NAME,
    ROOT_CAUSE_CATEGORY,
    RECURRENCE_COUNT,
    FIRST_OCCURRENCE,
    MAX(CREATED_AT) AS latest_occurrence
FROM OBSERVABILITY_DB.OBSERVABILITY.INCIDENT_LOG
WHERE IS_RECURRING = TRUE
GROUP BY OBJECT_NAME, ROOT_CAUSE_CATEGORY, RECURRENCE_COUNT, FIRST_OCCURRENCE
ORDER BY RECURRENCE_COUNT DESC;
```

---

## Troubleshooting

### "Insufficient privileges to query ACCOUNT_USAGE"

```sql
-- Grant required access (run as ACCOUNTADMIN)
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE <your_role>;
```

### "INCIDENT_LOG table not found"

Run the setup script:
```sql
@incident_debugger_setup.sql
```

### "Data latency - recent events not available"

ACCOUNT_USAGE views have ~45 minute latency. For very recent failures, the skill will note this and suggest waiting or using INFORMATION_SCHEMA views where applicable.

### "No evidence found"

- Verify the task/query name is spelled correctly
- Check if the failure occurred within the lookback window (default 24h)
- Ensure your role has access to the database/schema containing the object

---

## Data Retention

Configure retention for INCIDENT_LOG:

```sql
-- Set 365-day retention
ALTER TABLE OBSERVABILITY_DB.OBSERVABILITY.INCIDENT_LOG 
SET DATA_RETENTION_TIME_IN_DAYS = 365;

-- Or create a cleanup task
CREATE OR REPLACE TASK OBSERVABILITY_DB.OBSERVABILITY.CLEANUP_OLD_INCIDENTS
  WAREHOUSE = COMPUTE_WH
  SCHEDULE = 'USING CRON 0 2 * * 0 UTC'  -- Weekly Sunday 2am
AS
DELETE FROM OBSERVABILITY_DB.OBSERVABILITY.INCIDENT_LOG
WHERE CREATED_AT < DATEADD('day', -365, CURRENT_TIMESTAMP());
```
