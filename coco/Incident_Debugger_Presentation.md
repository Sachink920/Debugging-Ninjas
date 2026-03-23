# Incident Debugger Skill — Presentation Outline

---

## Slide 1: Title Slide

**Incident Debugger**
AI-Powered Incident Investigation for Snowflake

- Automatically diagnoses failed queries, tasks, and pipelines
- Gathers logs from Snowflake system views
- Correlates diagnostic signals into actionable root cause analysis

---

## Slide 2: Problem Statement

**Why do we need an Incident Debugger?**

- Failed tasks, queries, and pipelines require manual log digging
- Root cause analysis is time-consuming and error-prone
- Multiple system views must be cross-referenced (TASK_HISTORY, QUERY_HISTORY, ACCESS_HISTORY, etc.)
- No single pane of glass for incident investigation in Snowflake

---

## Slide 3: Solution Overview

**A 7-Phase Automated Investigation Framework**

| Phase | Name | Purpose |
|-------|------|---------|
| 1 | Incident Identification | Parse and classify the incident |
| 2 | Evidence Collection | Gather data from 11 system views |
| 3 | Timeline Reconstruction | Build chronological event sequence |
| 4 | Root Cause Analysis | Classify and score the root cause |
| 5 | Remediation Recommendations | Generate fix SQL with safety gates |
| 6 | Incident Logging | Persist findings for audit |
| 7 | Notification & Follow-Up | Alert teams and support follow-up questions |

---

## Slide 4: Supported Incident Types

**What can it investigate?**

- **TASK** — Failed scheduled tasks and DAG executions
- **QUERY** — Failed ad-hoc or programmatic queries
- **PIPELINE** — Data pipeline and task graph failures
- **COPY** — Data load errors (COPY INTO failures)
- **LOGIN** — Authentication and access failures

---

## Slide 5: Phase 1 — Incident Identification

**Parsing the user's report to classify the incident**

Extracts:
- Incident Type (TASK, QUERY, PIPELINE, COPY, LOGIN)
- Object Identifier (task name, query ID, table, error snippet)
- Time Window (explicit or inferred — e.g., "this morning" → last 12 hours)
- Context (database, schema, warehouse)

Smart resolution rules:
- Error message only → searches QUERY_HISTORY for matching errors
- Task name → resolves to fully qualified DATABASE.SCHEMA.TASK_NAME

---

## Slide 6: Phase 2 — Evidence Collection

**11 Parallel Diagnostic Queries Across System Views**

| # | Data Source | What It Captures |
|---|-----------|-----------------|
| 1 | TASK_HISTORY | Task states, errors, durations |
| 2 | QUERY_HISTORY | Query details, execution metrics |
| 3 | COMPLETE_TASK_GRAPHS | DAG analysis, graph runs |
| 4 | ACCESS_HISTORY | Permissions, objects accessed |
| 5 | WAREHOUSE_EVENTS_HISTORY | Warehouse provisioning events |
| 6 | WAREHOUSE_METERING_HISTORY | Credit consumption, capacity |
| 7 | COPY_HISTORY | Data load errors, file details |
| 8 | LOGIN_HISTORY | Auth failures, client info |
| 9 | STAGES | Stage metadata verification |
| 10 | QUERY_HISTORY (concurrent) | Contention analysis |
| 11 | QUERY_HISTORY (DDL) | Recent schema changes (drift) |

---

## Slide 7: Phase 3 — Timeline Reconstruction

**Building a chronological event sequence**

```
INCIDENT TIMELINE: ETL_DAILY_LOAD
═══════════════════════════════════════════
[T-10m]  ▶ SCHEDULED   Task scheduled
[T-9m]   ▶ WAREHOUSE   Provisioning started
[T-7m]   ⚠ QUEUE       High queue time (45s)
[T-5m]   ▶ EXECUTE     Query execution started
[T-2m]   ✗ FAILURE     Column 'AMOUNT' not found
[T-0m]   ▶ LOGGED      Task marked FAILED
═══════════════════════════════════════════
```

Includes: concurrent events, comparison to prior successful runs, recurrence patterns

---

## Slide 8: Phase 4 — Root Cause Analysis

**6 Root Cause Categories**

| Category | Code | Common Indicators |
|----------|------|-------------------|
| Query Logic Error | QUERY_LOGIC | Syntax error, invalid reference, type mismatch |
| Permission Gap | PERMISSION | Access denied, missing GRANT |
| Warehouse Resource | WAREHOUSE | Suspended, timeout, queue overflow |
| Data Quality / Schema | DATA_QUALITY | Column not found, type conversion error |
| Auth / Network | AUTH_NETWORK | Login failed, MFA required, network policy |
| Task Dependency | TASK_DEPENDENCY | Predecessor failed, DAG aborted |

**Confidence Scoring:**
- HIGH (80–100%) — 3+ corroborating evidence pieces
- MEDIUM (50–79%) — 2 evidence pieces
- LOW (0–49%) — Circumstantial only

---

## Slide 9: Phase 4 — RCA Report Format

**Structured, actionable output**

```
╔═══════════════════════════════════════════╗
║  ROOT CAUSE ANALYSIS                      ║
╠═══════════════════════════════════════════╣
║  Incident:   ETL_DAILY_LOAD               ║
║  Category:   DATA_QUALITY                  ║
║  Confidence: HIGH (92%)                    ║
╠═══════════════════════════════════════════╣
║  SUMMARY                                   ║
║  Column 'AMOUNT' was dropped by ALTER      ║
║  TABLE executed 2 hours before task run.   ║
╠═══════════════════════════════════════════╣
║  EVIDENCE                                  ║
║  1. QUERY_HISTORY: Column not found error  ║
║  2. DDL HISTORY: ALTER TABLE at T-2h       ║
║  3. ACCESS_HISTORY: Same column referenced ║
╠═══════════════════════════════════════════╣
║  ALTERNATIVES                              ║
║  • [5%] Permission change                  ║
║  • [3%] Transient warehouse issue          ║
╚═══════════════════════════════════════════╝
```

---

## Slide 10: Phase 5 — Remediation Recommendations

**Category-specific, executable SQL fixes**

Each recommendation includes:
- **Action** — What the fix does
- **Impact** — Potential effects and risks
- **Reversible** — Whether it can be undone and how
- **SQL** — Ready-to-run remediation statements

**Safety Rules:**
- All DDL/DML requires explicit user confirmation
- No DROP, DELETE, TRUNCATE, or REVOKE without user request
- Rollback instructions provided where applicable

---

## Slide 11: Phase 6 & 7 — Logging, Notification & Follow-Up

**Phase 6: Incident Logging**
- Persists full investigation to OBSERVABILITY.INCIDENT_LOG
- Captures: root cause, evidence, timeline, remediation, confidence scores
- Enables historical trend analysis

**Phase 7: Notification & Follow-Up**
- Routes alerts based on OBSERVABILITY.NOTIFICATION_ROUTING
- Supports natural follow-up questions:

| User Asks | System Does |
|-----------|-------------|
| "Was this failing before?" | Queries 30-day TASK_HISTORY |
| "Show the full query" | Retrieves QUERY_TEXT |
| "What depends on this?" | Queries TASK_DEPENDENTS |
| "Apply the fix" | Executes remediation with confirmation |

---

## Slide 12: Security & Compliance

**Built-in safety guardrails**

- **RBAC Compliance** — Executes under CURRENT_ROLE(), never escalates privileges
- **No Data Exposure** — Only metadata and error messages displayed, not table contents
- **Secret Masking** — Masks passwords, keys, tokens in query text output
- **Audit Trail** — All evidence collection is logged
- **Approval Gates** — DDL/DML requires explicit user confirmation

---

## Slide 13: Error Handling & Resilience

**Graceful degradation when evidence sources fail**

Common issues handled:
- Insufficient privileges on SNOWFLAKE database
- Account usage data latency (< 45 min delay)
- Objects in unexpected database/schema

Behavior: Always provides partial analysis with available evidence, clearly communicates which sources were unavailable

---

## Slide 14: Architecture Summary

```
User Report
    │
    ▼
┌──────────────────────┐
│ Phase 1: Identify    │ ← Parse incident type, object, time window
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│ Phase 2: Collect     │ ← 11 parallel queries across system views
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│ Phase 3: Timeline    │ ← Chronological event reconstruction
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│ Phase 4: RCA         │ ← Classify root cause + confidence score
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│ Phase 5: Remediate   │ ← Generate fix SQL with safety gates
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│ Phase 6: Log         │ ← Persist to INCIDENT_LOG table
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│ Phase 7: Notify      │ ← Alert teams + support follow-ups
└──────────────────────┘
```

---

## Slide 15: Key Benefits

- **Speed** — Automates hours of manual log investigation into seconds
- **Consistency** — Structured 7-phase methodology for every incident
- **Comprehensiveness** — 11 data sources queried in parallel
- **Actionability** — Executable remediation SQL, not just diagnosis
- **Safety** — RBAC-compliant with approval gates for all changes
- **Auditability** — Full incident logging and notification routing
- **Resilience** — Graceful degradation when data sources are unavailable
