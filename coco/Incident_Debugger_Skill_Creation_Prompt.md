================================================================================
PROMPT: CREATE THE "INCIDENT DEBUGGER" SKILL FOR SNOWFLAKE CORTEX CODE (COCO)
================================================================================

Use the following prompt with Cortex Code (COCO) in a Snowflake Workspace to
have it build the complete Incident Debugger skill from scratch.

Copy everything between the START and END markers below and paste it as a
message to COCO.

================================================================================
--- START OF PROMPT ---
================================================================================

I want you to build a complete Cortex Code skill called "Incident_Debugger".
This skill automates the investigation of failed queries, tasks, pipelines,
COPY operations, and login failures in Snowflake by gathering diagnostic
evidence from system views, reconstructing timelines, performing root cause
analysis, and suggesting remediation.

Below are the EXACT requirements. Create all three files in the directory
`.snowflake/cortex/skills/Incident_Debugger/`.

------------------------------------------------------------------------
FILE 1: SKILL.md
------------------------------------------------------------------------

Create the SKILL.md file with this frontmatter:

```
---
name: Incident_Debugger
description: AI-powered incident investigation that automatically diagnoses
  failed queries, tasks, and pipelines by gathering logs from Snowflake system
  views, correlating diagnostic signals, and synthesizing actionable root cause
  analysis.
---
```

The body must define a 7-phase investigation workflow. Each phase is described
below with its exact purpose and the SQL templates or output formats it must
contain.

### PHASE 1 - INCIDENT IDENTIFICATION
Parse the user's request to extract:
- Incident Type: one of TASK, QUERY, PIPELINE, COPY, LOGIN
- Object Identifier: task name, query ID, table name, or error snippet
- Time Window: explicit or default to last 24 hours
- Context: database, schema, warehouse if mentioned

Include resolution rules:
- Error message only -> search QUERY_HISTORY for matching errors
- Task name -> resolve to DATABASE.SCHEMA.TASK_NAME
- "this morning" -> DATEADD('hour', -12, CURRENT_TIMESTAMP())
- "last night" -> 18:00-06:00 previous day
- "yesterday" -> full previous calendar day

### PHASE 2 - EVIDENCE COLLECTION
Include 11 diagnostic SQL query templates that should be executed IN PARALLEL
where possible. Each query must have placeholders ({{variable}}) for dynamic
values. The 11 queries are:

1. Task History - from SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY, filtering by
   task name and last 24 hours. Include NAME, STATE, ERROR_CODE,
   ERROR_MESSAGE, SCHEDULED_TIME, QUERY_START_TIME, COMPLETED_TIME, QUERY_ID,
   ROOT_TASK_ID, GRAPH_RUN_GROUP_ID, and duration calculation.

2. Query History - from SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY, filtering by
   query_id OR search_term OR error_snippet with EXECUTION_STATUS = 'FAIL'.
   Include all timing breakdowns (compilation, execution, queue provisioning,
   queue overload), BYTES_SCANNED, ROWS_PRODUCED, PARTITIONS_SCANNED/TOTAL.

3. Complete Task Graphs - from SNOWFLAKE.ACCOUNT_USAGE.COMPLETE_TASK_GRAPHS
   for DAG analysis. Filter by ROOT_TASK_ID, GRAPH_RUN_GROUP_ID, or task
   name. Include RUN_ID, ATTEMPT_NUMBER, duration.

4. Access History - from SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY for
   permission analysis. Include DIRECT_OBJECTS_ACCESSED,
   BASE_OBJECTS_ACCESSED, OBJECTS_MODIFIED, POLICIES_REFERENCED. Filter by
   query_id or +/- 5 minutes around incident time.

5. Warehouse Events History - from
   SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_EVENTS_HISTORY. Include EVENT_NAME,
   EVENT_REASON, EVENT_STATE, CLUSTER_NUMBER. Filter +/- 1 hour around
   incident.

6. Warehouse Metering History - from
   SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY for capacity analysis.
   Include CREDITS_USED, CREDITS_USED_COMPUTE, CREDITS_USED_CLOUD_SERVICES.

7. Copy History - from SNOWFLAKE.ACCOUNT_USAGE.COPY_HISTORY for data load
   failures. Filter where STATUS != 'Loaded'. Include FILE_NAME,
   STAGE_LOCATION, ERROR_COUNT, FIRST_ERROR_MESSAGE,
   FIRST_ERROR_LINE_NUMBER, FIRST_ERROR_COLUMN_NAME.

8. Login History - from SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY for auth
   failures. Include EVENT_TYPE, CLIENT_IP, REPORTED_CLIENT_TYPE,
   FIRST/SECOND_AUTHENTICATION_FACTOR, IS_SUCCESS, ERROR_CODE.

9. Stages - from SNOWFLAKE.ACCOUNT_USAGE.STAGES for file verification.
   Include STAGE_URL, STAGE_TYPE.

10. Concurrent Activity - COUNT, SUM(BYTES_SCANNED), AVG elapsed,
    MAX queue overload, LISTAGG of users from QUERY_HISTORY for the same
    warehouse +/- 10 minutes around incident, excluding the incident query.

11. Recent Schema Changes - from QUERY_HISTORY where QUERY_TYPE IN
    ('ALTER_TABLE', 'DROP_TABLE', 'CREATE_TABLE', 'ALTER', 'DROP') and
    QUERY_TEXT matches the object name, last 7 days.

### PHASE 3 - TIMELINE RECONSTRUCTION
After evidence collection, build a chronological timeline using this format:

```
INCIDENT TIMELINE: {{task_name or query_id}}
===================================================================
[TIMESTAMP]  EVENT_TYPE  Description
-------------------------------------------------------------------
[T-10m]  > SCHEDULED    Task scheduled
[T-5m]   > EXECUTE      Query execution started
[T-2m]   X FAILURE      {{error_message}}
===================================================================
```

Include sections for:
- CONCURRENT EVENTS (other queries, warehouse scaling, DDL on related objects)
- PATTERN CHECK (previous run status, recurrence count, first occurrence)

### PHASE 4 - ROOT CAUSE ANALYSIS
Classify into exactly ONE of 6 categories:
| Category             | Code             | Indicators                               |
|----------------------|------------------|------------------------------------------|
| Query Logic Error    | QUERY_LOGIC      | Syntax error, invalid ref, division by 0 |
| Permission Gap       | PERMISSION       | Access denied, missing GRANT             |
| Warehouse Resource   | WAREHOUSE        | Suspended, timeout, queue timeout        |
| Data Quality         | DATA_QUALITY     | Schema drift, type mismatch, constraint  |
| Auth/Network Failure | AUTH_NETWORK     | Login failed, MFA, network policy        |
| Task Dependency      | TASK_DEPENDENCY  | Predecessor failed, DAG issues           |

Output a formatted RCA box with: Incident, Time, Query ID, Category,
Confidence (HIGH/MEDIUM/LOW with percentage), Summary (2-3 sentences),
Evidence (numbered list with source), Alternative Hypotheses (with
probability percentages).

Confidence scoring rules:
- HIGH (80-100%): 3+ evidence pieces, error directly indicates cause
- MEDIUM (50-79%): 2 evidence pieces
- LOW (0-49%): Circumstantial only

### PHASE 5 - REMEDIATION RECOMMENDATIONS
Provide category-specific remediation SQL templates:
- PERMISSION: SHOW GRANTS, GRANT statements
- WAREHOUSE: ALTER WAREHOUSE RESUME/RESIZE, EXECUTE TASK
- QUERY_LOGIC: SHOW TABLES, DESCRIBE TABLE
- DATA_QUALITY: DESCRIBE TABLE, ALTER COLUMN
- TASK_DEPENDENCY: TASK_DEPENDENTS, EXECUTE predecessor then failed task
- AUTH_NETWORK: SHOW USERS, DESCRIBE USER, SHOW NETWORK POLICIES

Present each remediation with: Action description, Impact warning,
Reversibility statement, SQL block, and a confirmation prompt before
executing any DDL/DML.

CRITICAL RULES:
- NEVER execute DROP, DELETE, TRUNCATE, REVOKE without explicit user request
- Always explain what each command does
- Always warn about potential impact
- Provide rollback instructions

### PHASE 6 - INCIDENT LOGGING
First check if the INCIDENT_LOG table exists in OBSERVABILITY schema.
If yes, INSERT the investigation results with all fields including:
INCIDENT_TYPE, OBJECT_NAME, QUERY_ID, TASK_NAME, DATABASE/SCHEMA/WAREHOUSE,
timestamps, error details, ROOT_CAUSE_CATEGORY, ROOT_CAUSE_SUMMARY,
CONFIDENCE_SCORE/PERCENTAGE, IS_RECURRING, RECURRENCE_COUNT,
EVIDENCE_REFERENCES (VARIANT), EVENT_TIMELINE (VARIANT),
REMEDIATION_SUGGESTED (VARIANT), RAW_EVIDENCE (VARIANT).

### PHASE 7 - NOTIFICATION & FOLLOW-UP
Check NOTIFICATION_ROUTING table for matching routing rules by category,
database pattern, and enabled status.

Include a follow-up questions table mapping user questions to actions:
- "Was this failing before?" -> TASK_HISTORY 30-day recurrence analysis
- "Show me the full query" -> QUERY_TEXT from QUERY_HISTORY
- "What other tasks depend on this?" -> TASK_DEPENDENTS
- "Who else uses this warehouse?" -> QUERY_HISTORY by user
- "What changed recently?" -> ALTER/DROP/CREATE queries
- "Apply the fix" -> Execute remediation with confirmation
- "Log this incident" -> Trigger Phase 6
- "Send notification" -> Trigger Phase 7

Include a recurrence analysis query grouping failures by day over 30 days.

### SECURITY REQUIREMENTS
Add these rules at the end of SKILL.md:
1. RBAC Compliance: execute under CURRENT_ROLE(), never escalate
2. No Data Exposure: only metadata and error messages, not table contents
3. Query Text Masking: mask secrets (password, key, token) in output
4. Audit Trail: log evidence collection
5. Approval Gates: DDL/DML requires explicit user confirmation

### ERROR HANDLING
If evidence queries fail, show a warning with possible causes:
1. Insufficient privileges (need IMPORTED PRIVILEGES on SNOWFLAKE db)
2. Account usage data latency (< 45 min)
3. Object may not exist or is in a different schema
Then proceed with available evidence (partial analysis).

------------------------------------------------------------------------
FILE 2: AGENTS.md
------------------------------------------------------------------------

Create an AGENTS.md file with:
- A header "# Incident Debugger - Agent Configuration"
- Description of the skill as an AI-powered Snowflake incident investigator
- Supported incident types: TASK, QUERY, PIPELINE, COPY, LOGIN
- List of Snowflake system views used (11 views):
  TASK_HISTORY, QUERY_HISTORY, COMPLETE_TASK_GRAPHS, ACCESS_HISTORY,
  WAREHOUSE_EVENTS_HISTORY, WAREHOUSE_METERING_HISTORY, COPY_HISTORY,
  LOGIN_HISTORY, STAGES, NOTIFICATION_ROUTING, INCIDENT_LOG
- Prerequisites: ACCOUNTADMIN or role with IMPORTED PRIVILEGES on SNOWFLAKE
  database, and a warehouse
- Example invocations:
  "why did my task fail?"
  "show fail pipeline"
  "debug failed COPY into my_table"
  "why can't user X login?"
  "what failed last night?"
- Section on supporting database objects (reference incident_debugger_setup.sql)

------------------------------------------------------------------------
FILE 3: incident_debugger_setup.sql
------------------------------------------------------------------------

Create a SQL setup script that creates these Snowflake objects inside an
OBSERVABILITY_DB.OBSERVABILITY schema:

1. DATABASE OBSERVABILITY_DB and SCHEMA OBSERVABILITY (IF NOT EXISTS)

2. INCIDENT_LOG table with columns:
   - INCIDENT_ID (UUID default), CREATED_AT, INVESTIGATED_BY, INVESTIGATING_ROLE
   - INCIDENT_TYPE, OBJECT_NAME, QUERY_ID, TASK_NAME, DATABASE_NAME,
     SCHEMA_NAME, WAREHOUSE_NAME
   - INCIDENT_START_TIME, INCIDENT_END_TIME, DETECTION_LATENCY_SEC
   - ERROR_CODE, ERROR_MESSAGE, ERROR_CATEGORY
   - ROOT_CAUSE_CATEGORY, ROOT_CAUSE_SUMMARY, CONFIDENCE_SCORE,
     CONFIDENCE_PERCENTAGE, ALTERNATIVE_HYPOTHESES (VARIANT),
     EVIDENCE_REFERENCES (VARIANT)
   - EVENT_TIMELINE (VARIANT), CONCURRENT_EVENTS (VARIANT)
   - IS_RECURRING, RECURRENCE_COUNT, FIRST_OCCURRENCE, PATTERN_DESCRIPTION
   - REMEDIATION_SUGGESTED (VARIANT), REMEDIATION_APPLIED (VARIANT),
     REMEDIATION_STATUS, REMEDIATION_APPLIED_AT, REMEDIATION_APPLIED_BY
   - TIME_TO_DIAGNOSE_SEC, TIME_TO_RESOLVE_SEC
   - NOTIFICATION_SENT, NOTIFICATION_RECIPIENTS (VARIANT),
     NOTIFICATION_SENT_AT
   - RAW_EVIDENCE (VARIANT)

3. INCIDENT_CATEGORIES reference table with 6 default categories:
   QUERY_LOGIC, PERMISSION, WAREHOUSE, DATA_QUALITY, AUTH_NETWORK,
   TASK_DEPENDENCY. Each with name, description, severity default,
   auto_remediate flag, and notification tier. Use MERGE for idempotency.

4. NOTIFICATION_ROUTING configuration table with columns for category
   matching, database/schema/task patterns, notification type, recipients
   (VARIANT), and enabled flag.

5. V_INCIDENT_EVIDENCE view - joins TASK_HISTORY with QUERY_HISTORY on
   QUERY_ID for pre-joined diagnostics (last 7 days of failed tasks with
   their query details including timing breakdowns).

6. V_TASK_FAILURE_SUMMARY view - aggregates task failures over last 30 days
   grouped by database, schema, task name. Include total failures,
   days_with_failures, first/last failure, distinct error codes, most common
   error, avg duration.

7. CLASSIFY_ERROR_CATEGORY UDF (SQL) - takes error_code and error_message,
   returns one of the 6 categories using CASE logic with pattern matching on
   known error codes and LIKE patterns on error messages.

8. CALCULATE_CONFIDENCE UDF (SQL) - takes evidence_count (NUMBER),
   category_match_strength (NUMBER), pattern_confirmed (BOOLEAN). Returns an
   OBJECT with 'level' (HIGH/MEDIUM/LOW) and 'percentage' (0-100).

9. LOG_INCIDENT stored procedure - takes all incident fields as parameters,
   calculates DETECTION_LATENCY_SEC, inserts into INCIDENT_LOG, uses
   CLASSIFY_ERROR_CATEGORY for the ERROR_CATEGORY column, and returns the
   generated INCIDENT_ID.

10. UPDATE_REMEDIATION_STATUS stored procedure - takes incident_id, status,
    and remediation_applied (VARIANT). Updates the incident record with
    status, applied details, timestamp, user, and calculates
    TIME_TO_RESOLVE_SEC.

Include commented-out GRANT examples for a DATA_ENGINEER role and a
verification query at the end.

------------------------------------------------------------------------
IMPORTANT NOTES FOR THE BUILDER
------------------------------------------------------------------------

- The SKILL.md file is the core intelligence. It must be comprehensive
  enough that COCO can follow it autonomously during an investigation.
- All SQL templates in SKILL.md use {{placeholder}} syntax for dynamic values.
- The setup SQL must be idempotent (IF NOT EXISTS, MERGE, CREATE OR REPLACE).
- The skill directory structure must be:
  .snowflake/cortex/skills/Incident_Debugger/
    SKILL.md
    AGENTS.md
    incident_debugger_setup.sql
- All output formatting in SKILL.md uses box-drawing characters for
  professional presentation.
- The skill must handle partial evidence gracefully (some queries may fail
  due to permissions or latency).

================================================================================
--- END OF PROMPT ---
================================================================================


WHAT THIS PROMPT PRODUCES:
--------------------------
When you paste the prompt above into Cortex Code, it will create:

1. SKILL.md        - The AI instruction set (7-phase investigation workflow
                      with 11 diagnostic SQL templates, timeline formatting,
                      6-category RCA framework, remediation playbooks,
                      incident logging, and notification routing)

2. AGENTS.md       - Agent metadata (supported types, prerequisites, example
                      invocations, system views used)

3. Setup SQL       - 10 Snowflake objects (2 tables, 1 ref table, 1 config
                      table, 2 views, 2 UDFs, 2 stored procedures) in an
                      OBSERVABILITY_DB.OBSERVABILITY schema

HOW TO USE AFTER CREATION:
--------------------------
1. Run the setup SQL in a Snowflake worksheet with ACCOUNTADMIN to create
   supporting objects.
2. In any Snowflake Workspace, invoke the skill with:
   @Incident_Debugger why did my task fail?
   @Incident_Debugger show fail pipeline
   @Incident_Debugger debug failed queries last night
3. The skill will automatically gather evidence, build a timeline, perform
   root cause analysis, and suggest remediation.

CUSTOMIZATION TIPS:
-------------------
- Add more error code patterns to CLASSIFY_ERROR_CATEGORY for your environment
- Configure NOTIFICATION_ROUTING rows for your team's alert preferences
- Adjust the 24-hour default time window in Phase 1 if needed
- Add custom remediation templates in Phase 5 for your common failure modes
- Extend INCIDENT_CATEGORIES with organization-specific categories
