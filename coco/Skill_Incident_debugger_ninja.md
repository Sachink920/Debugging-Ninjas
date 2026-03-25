I want you to build a complete, production-ready Cortex Code skill called "Incident_Debugger".

This skill will act as an AI-powered Snowflake incident investigator that automatically diagnoses failed queries, tasks, pipelines, COPY INTO operations, and login failures.

Please create the skill in this exact directory structure:
.snowflake/cortex/skills/Incident_Debugger/

You must generate exactly these three files:

1. SKILL.md
2. AGENTS.md
3. incident_debugger_setup.sql

------------------------------------------------------------------------
FILE 1: SKILL.md
------------------------------------------------------------------------

Create SKILL.md with the following frontmatter exactly:

---
name: Incident_Debugger
description: AI-powered incident investigation that automatically diagnoses failed queries, tasks, pipelines, COPY operations, and login failures in Snowflake by gathering logs from system views, correlating signals, and synthesizing actionable root cause analysis.
---

Then define a clear 7-phase investigation workflow:

### PHASE 1: INCIDENT IDENTIFICATION
Parse the user's request to identify:
- Incident Type: TASK, QUERY, PIPELINE, COPY, or LOGIN
- Object Identifier: task name, query ID, table name, or error message snippet
- Time Window: default to last 24 hours if not specified
- Context: database, schema, warehouse (if mentioned)

Include smart resolution rules for phrases like "this morning", "last night", "yesterday", or when only an error message is provided.

### PHASE 2: EVIDENCE COLLECTION
Run the following 11 diagnostic queries in parallel. Use {{placeholder}} syntax for dynamic values:

1. Task History from SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY
2. Query History from SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY (failed queries only)
3. Complete Task Graphs from SNOWFLAKE.ACCOUNT_USAGE.COMPLETE_TASK_GRAPHS
4. Access History from SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY
5. Warehouse Events History from SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_EVENTS_HISTORY
6. Warehouse Metering History from SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
7. Copy History from SNOWFLAKE.ACCOUNT_USAGE.COPY_HISTORY (failed loads)
8. Login History from SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY
9. Stages from SNOWFLAKE.ACCOUNT_USAGE.STAGES
10. Concurrent Activity on the same warehouse
11. Recent Schema Changes (last 7 days)

Provide full SQL templates with proper placeholders for each query.

### PHASE 3: TIMELINE RECONSTRUCTION
After collecting evidence, create a clean chronological timeline using ASCII art format. Include sections for concurrent events, anomalous durations, and recurrence patterns.

### PHASE 4: ROOT CAUSE ANALYSIS
Classify the root cause into exactly ONE of these 6 categories:
- QUERY_LOGIC
- PERMISSION
- WAREHOUSE
- DATA_QUALITY
- AUTH_NETWORK
- TASK_DEPENDENCY

Output the RCA in a professional boxed format including:
- Incident details
- Category
- Confidence level (HIGH / MEDIUM / LOW) with percentage
- 2-3 sentence plain-language summary
- Numbered evidence list with sources
- Alternative hypotheses with probability percentages

### PHASE 5: REMEDIATION RECOMMENDATIONS
Provide specific remediation SQL for each category. For every recommendation include:
- Clear action description
- Impact and risk warning
- Whether it is reversible (with rollback steps if applicable)
- Formatted SQL code block
- Ask for explicit user confirmation before executing any DDL or DML

Important Rules:
- Never execute DROP, DELETE, TRUNCATE, or REVOKE without explicit user approval
- Always explain what each command does
- Always warn about potential impact

### PHASE 6: INCIDENT LOGGING
Check if the INCIDENT_LOG table exists in OBSERVABILITY_DB.OBSERVABILITY schema. If it exists, log the full investigation details (use the LOG_INCIDENT stored procedure if available).

### PHASE 7: NOTIFICATION & FOLLOW-UP
Support common follow-up questions and recurrence analysis. Check the NOTIFICATION_ROUTING table for alert configuration.

### SECURITY REQUIREMENTS & ERROR HANDLING
- Always respect RBAC – run under CURRENT_ROLE()
- Never expose sensitive data or full table contents
- Handle partial failures gracefully (show warning and continue with available evidence)

------------------------------------------------------------------------
FILE 2: AGENTS.md
------------------------------------------------------------------------

Create AGENTS.md with the following content:
- Title: Incident Debugger - Agent Configuration
- Short description of the skill
- List of supported incident types
- List of Snowflake system views used
- Prerequisites (IMPORTED PRIVILEGES on SNOWFLAKE database, warehouse access)
- Example natural language invocations
- Reference to incident_debugger_setup.sql for supporting objects

------------------------------------------------------------------------
FILE 3: incident_debugger_setup.sql
------------------------------------------------------------------------

Generate a complete, idempotent SQL script that does the following:

- Creates database OBSERVABILITY_DB and schema OBSERVABILITY (if not exists)
- Creates INCIDENT_LOG table with all necessary columns (including VARIANT columns for timeline, evidence, remediation)
- Creates INCIDENT_CATEGORIES reference table with 6 default categories using MERGE
- Creates NOTIFICATION_ROUTING configuration table
- Creates V_INCIDENT_EVIDENCE and V_TASK_FAILURE_SUMMARY views
- Creates CLASSIFY_ERROR_CATEGORY and CALCULATE_CONFIDENCE UDFs
- Creates LOG_INCIDENT and UPDATE_REMEDIATION_STATUS stored procedures
- Includes commented GRANT statements for a DATA_ENGINEER role
- Ends with a verification query

Make the script fully idempotent using CREATE OR REPLACE and IF NOT EXISTS.

------------------------------------------------------------------------
FINAL INSTRUCTIONS
------------------------------------------------------------------------

- Make SKILL.md detailed and well-structured so the skill can run autonomously.
- Use professional formatting with box-drawing characters for timelines and RCA output.
- Ensure all SQL templates use {{placeholder}} syntax.
- Keep everything clean, readable, and suitable for production use in 2026 Snowflake environment.

After generating the files, please display the full content of each file clearly separated with headings.