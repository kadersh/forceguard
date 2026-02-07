# ForceGuard Architecture Plan

**Date:** 2026-02-07
**Version:** 1.0
**Purpose:** Complete technical blueprint for building ForceGuard - a Salesforce-native regression testing framework. First target: the Audit (SOX/IPE) product.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Phase & Task Structure](#2-phase--task-structure)
3. [Audit Product Test Scenarios](#3-audit-product-test-scenarios)
4. [Data Model](#4-data-model)
5. [LWC Component Specifications](#5-lwc-component-specifications)

---

## Key Policies

### No Flows in ForceGuard (CRITICAL)

**ForceGuard is a managed package product - ALL automation is built in Apex, NOT Flows.**

**Why:**
- **IP Protection:** Flows expose business logic to customers in Flow Builder - revealing algorithms, rules, and competitive advantages
- **Obfuscation:** Apex in managed packages is obfuscated; customers see method signatures only, not implementation
- **Licensing:** Flow logic can be copied/exported; Apex cannot
- **Professional Image:** Enterprise buyers expect code-based managed packages

**Implementation:**
- Record automation → Apex Triggers with handler classes
- Scheduled automation → Schedulable Apex
- User interactions → LWC with Apex controllers
- Platform events → Apex EventBus handlers

**About @InvocableMethod:**
- Apex methods can be marked `@InvocableMethod` for customer extensibility via Flow Builder
- Core logic remains protected via obfuscation
- Customers see signature/description, not implementation

**Important Distinction:**
- **ForceGuard itself:** ZERO Flows (this document, Phase 6 tasks)
- **Products being tested:** MAY contain Flows (e.g., Audit product has 8 Flows)
- ForceGuard tests other products' Flows but contains none itself

See Phase 6 for full details.

---

## 1. Architecture Overview

### 1.1 The 4-Layer Testing Model

ForceGuard tests Salesforce products through 4 sequential layers, each progressively deeper. Blocking layers halt the pipeline if they fail - there is no point running expensive data scenario tests if the code does not even compile.

```
Layer 1: Deployment Validation  [BLOCKING]  ~30-60s
  Input:  Regression_Test_Case__c records where Test_Layer__c = 'Deployment'
  Action: sf project deploy validate --source-dir <product-source-path>
  Output: Regression_Test_Result__c with deploy status, error messages
  Stops:  If any class/trigger/LWC/Flow fails compilation or has broken references
  Note:   ForceGuard tests products that MAY contain Flows (like Audit). ForceGuard itself has no Flows.

Layer 2: Apex Test Execution    [BLOCKING]  ~2-5m
  Input:  Regression_Test_Case__c records where Test_Layer__c = 'Apex Test'
  Action: sf apex run test --test-level RunLocalTests (or specific test classes)
  Output: Regression_Test_Result__c with pass/fail per method, code coverage %
  Stops:  If coverage < threshold (default 85%) or any critical assertion fails

Layer 3: Data Scenario Testing  [VERIFICATION]  ~5-15m
  Input:  Regression_Test_Case__c records where Test_Layer__c = 'Data Scenario'
  Action: Execute anonymous Apex scripts that create real data, trigger automations,
          and assert expected outcomes using SOQL queries
  Output: Regression_Test_Result__c with scenario results, actual vs expected
  Note:   Does NOT block pipeline but flags regressions

Layer 4: Static Analysis        [QUALITY GATE]  ~1-2m
  Input:  Source code paths from Regression_Config__mdt
  Action: sf code-analyzer run --target <source-path> --format json
  Output: Regression_Test_Result__c with violation counts, severity breakdown
  Note:   Advisory quality gate, configurable severity threshold
```

### 1.2 Apex Class Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                      ORCHESTRATION LAYER                            │
│                                                                      │
│  RegressionTestRunner                                                │
│  - Accepts Suite ID or Run configuration                            │
│  - Creates Regression_Test_Run__c record (Status = 'Running')       │
│  - Queries active Regression_Test_Case__c records                    │
│  - Iterates layers 1-4 in sequence                                  │
│  - Respects blocking logic (stops if L1 or L2 fails)               │
│  - Calls RegressionTestExecutor for each layer                      │
│  - Calls RegressionTestReporter after completion                    │
│  - Updates Run record with final counts and status                  │
│  - Implements Batchable<SObject> for async execution                │
│                                                                      │
│  RegressionTestScheduler (Schedulable)                               │
│  - Reads Regression_Config__mdt for schedule config                 │
│  - Instantiates and executes RegressionTestRunner                   │
│  - Supports daily, weekly, monthly, and custom cron                 │
│  - Handles multi-suite scheduling                                   │
└────────────────────────────┬─────────────────────────────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────────────────┐
│                       EXECUTION LAYER                                │
│                                                                      │
│  RegressionTestExecutor                                              │
│  - Receives List<Regression_Test_Case__c> + layer number            │
│  - Dispatches to layer-specific execution logic:                    │
│    - Layer 1: Calls Tooling API / sf deploy validate                │
│    - Layer 2: Calls sf apex run test with specified classes          │
│    - Layer 3: Runs anonymous Apex scripts from test case Steps__c   │
│    - Layer 4: Parses code analyzer output                           │
│  - Creates Regression_Test_Result__c per test case                  │
│  - Detects regressions (previously passing, now failing)            │
│  - Returns LayerResult with pass/fail counts and blocking status    │
│                                                                      │
│  RegressionTestAssertion (Static Utility)                            │
│  - assertEquals(expected, actual, message)                          │
│  - assertNotNull(value, message)                                    │
│  - assertRecordExists(sObjectType, whereClause)                     │
│  - assertRecordCount(sObjectType, whereClause, expectedCount)       │
│  - assertFieldValue(recordId, fieldName, expectedValue)             │
│  - assertCoverage(className, minPercent)                            │
│  - assertNoGovernorViolation(testClassName)                         │
│  - Each returns AssertionResult { passed, message, expected, actual }│
└────────────────────────────┬─────────────────────────────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────────────────┐
│                       REPORTING LAYER                                │
│                                                                      │
│  RegressionTestReporter                                              │
│  - Generates run summary (pass/fail/skip per layer)                 │
│  - Compares with previous run to identify regressions               │
│  - Calculates trend data (pass rate delta)                          │
│  - Creates Regression_Finding__c for new regressions                │
│  - Generates PDF report (via Visualforce)                           │
│  - Generates CSV export                                             │
│  - Sends email notifications to configured recipients               │
│  - Updates Test_Coverage_Snapshot__c                                │
│                                                                      │
│  RegressionTestNotifier (Async - Queueable)                         │
│  - Sends email digest with run results                              │
│  - Creates external tickets for regressions (REST callout)          │
│  - Fires platform events for real-time LWC updates                  │
│  - Handles Slack/Teams webhook notifications                        │
└──────────────────────────────────────────────────────────────────────┘
```

### 1.3 Data Flow: End-to-End

```
1. TRIGGER
   User clicks "Run Suite" in LWC Dashboard
   OR Schedule fires via RegressionTestScheduler
        │
        ▼
2. INITIALIZATION (RegressionTestRunner)
   a. Query Regression_Test_Suite__c by ID
   b. Validate suite is active
   c. Create Regression_Test_Run__c (Status = 'Running', Run_Date = NOW())
   d. Query all active Regression_Test_Case__c for this suite
   e. Group test cases by Test_Layer__c
        │
        ▼
3. LAYER 1: DEPLOYMENT VALIDATION (RegressionTestExecutor)
   a. Execute sf project deploy validate for the target source
   b. Parse deployment result (success/failure, component errors)
   c. Create Regression_Test_Result__c per test case
   d. If ANY deployment test fails → mark layer as FAILED
   e. If layer FAILED → skip layers 2, 3 (mark as SKIPPED)
        │
        ▼ (only if Layer 1 PASSED)
4. LAYER 2: APEX TEST EXECUTION (RegressionTestExecutor)
   a. Execute sf apex run test for configured test classes
   b. Parse test results (per-method pass/fail, coverage)
   c. Create Regression_Test_Result__c per test case
   d. If coverage < threshold OR critical tests fail → FAILED
   e. If layer FAILED → skip layer 3 (mark as SKIPPED)
        │
        ▼ (only if Layer 2 PASSED)
5. LAYER 3: DATA SCENARIO TESTING (RegressionTestExecutor)
   a. For each test case:
      - Execute setup anonymous Apex (create test data)
      - Execute trigger action (DML to fire automations)
      - Execute verification SOQL queries
      - Run assertions via RegressionTestAssertion
   b. Create Regression_Test_Result__c per test case
   c. Layer 3 failures do NOT block Layer 4
        │
        ▼ (always runs)
6. LAYER 4: STATIC ANALYSIS (RegressionTestExecutor)
   a. Execute sf code-analyzer run on source path
   b. Parse analyzer output (violations by severity)
   c. Create Regression_Test_Result__c per test case
   d. Advisory only - does not block
        │
        ▼
7. FINALIZATION (RegressionTestRunner)
   a. Aggregate all results: total, passed, failed, skipped
   b. Calculate code coverage percentage
   c. Calculate duration
   d. Update Regression_Test_Run__c (Status, counts, coverage, duration)
   e. Update Regression_Test_Suite__c (Last_Run_Date, Last_Run_Status)
        │
        ▼
8. REPORTING (RegressionTestReporter)
   a. Compare results with previous run → detect regressions
   b. Set Is_Regression__c = true on newly failing tests
   c. Generate summary report
   d. Create/update Test_Coverage_Snapshot__c
        │
        ▼
9. NOTIFICATION (RegressionTestNotifier - Queueable)
   a. Send email to configured recipients
   b. Create tickets for regressions (if auto-ticket enabled)
   c. Fire ForceGuard_Test_Complete__e platform event
   d. LWC dashboard refreshes via empApi subscription
```

### 1.4 Salesforce CLI Integration Strategy

ForceGuard does NOT shell out to the Salesforce CLI directly. Instead, it uses the following native APIs:

| Operation | Salesforce API | Method |
|-----------|---------------|--------|
| Deploy validation | Metadata API (SOAP) or Tooling API | `MetadataContainer` + `ContainerAsyncRequest` |
| Apex test execution | Tooling API REST | `POST /services/data/vXX.0/tooling/runTestsAsynchronous` |
| Code coverage | Tooling API REST | `GET /services/data/vXX.0/tooling/query/?q=SELECT...FROM ApexCodeCoverage` |
| Anonymous Apex | Tooling API REST | `POST /services/data/vXX.0/tooling/executeAnonymous` |
| Static analysis | Metadata queries + custom rules | Internal pattern matching on source metadata |

For Layer 4 (static analysis), since `sf code-analyzer` is a CLI tool and cannot run inside Salesforce, ForceGuard implements a subset of static analysis rules in Apex:
- Query SOQL-in-loops patterns via Tooling API (ApexClass.Body)
- Check for hardcoded IDs via regex patterns
- Verify CRUD/FLS enforcement via SymbolTable queries
- Count complexity metrics via ApexClass metadata

---

## 2. Phase & Task Structure

### Phase 1: Foundation & Project Setup

**Description:** Set up the SFDX project structure, GitHub repository, and documentation foundation. This phase creates the scaffolding that all subsequent development depends on. It also establishes the development workflow (branching, deployment, validation) that the team will use throughout the build.

**Duration:** 3-5 days

---

#### Task 1.1: Create SFDX Project Structure

**Title:** Create SFDX project with namespace and scratch org definition

**Description:** Initialize the ForceGuard SFDX project with the correct directory structure. Configure `sfdx-project.json` with the `forceguard` namespace prefix, API version 62.0, and scratch org definition that includes required features (LightningExperience, API, Chatter). Create the `force-app/main/default/` directory structure for classes, lwc, objects, customMetadata, flows, permissionsets, and tabs. Add `.gitignore` for standard Salesforce ignores. Create `project-scratch-def.json` with the org shape needed for testing (edition: Developer, features: []).

**Acceptance Criteria:**
- [ ] `sfdx-project.json` exists with correct namespace and API version
- [ ] `project-scratch-def.json` creates a working scratch org
- [ ] Directory structure matches the planned layout (classes/, lwc/, objects/, etc.)
- [ ] `.gitignore` excludes `.sfdx/`, `.sf/`, `node_modules/`, etc.
- [ ] `sf project deploy validate` runs without errors on empty project

**Priority:** P0
**Effort:** S
**Dependencies:** None

---

#### Task 1.2: Create Package Manifest

**Title:** Create package.xml manifest with all metadata components

**Description:** Build the `manifest/package.xml` file listing all planned custom objects, Apex classes, LWC components, custom metadata types, permission sets, tabs, and page layouts. This manifest will be used for deployment validation. Include placeholders for components that will be built in later phases so the manifest grows with the project. Start with the data model components since those are built first. **IMPORTANT:** ForceGuard contains NO Flows (IP protection policy - see Phase 6).

**Acceptance Criteria:**
- [ ] `manifest/package.xml` exists with correct API version
- [ ] All 6 custom objects listed under `CustomObject`
- [ ] Custom metadata types listed under `CustomMetadata`
- [ ] Placeholder entries for Apex classes and LWC (NO Flows - see Phase 6 policy)
- [ ] Manifest validates with `sf project retrieve start` (no syntax errors)

**Priority:** P0
**Effort:** S
**Dependencies:** Task 1.1

---

#### Task 1.3: Initialize GitHub Repository

**Title:** Set up GitHub repository with branch protection and initial commit

**Description:** Create the `kadersh/forceguard` GitHub repository. Push the initial SFDX project structure. Set up branch protection on `main` (require PR reviews, require status checks to pass). Create `develop` branch for active development. Add README.md with product overview, installation instructions placeholder, and badge links. Add DEPLOYMENT.md with deployment steps for sandbox and production.

**Acceptance Criteria:**
- [ ] GitHub repo exists at `github.com/kadersh/forceguard`
- [ ] `main` branch has branch protection enabled
- [ ] `develop` branch exists for active development
- [ ] README.md has product overview section
- [ ] DEPLOYMENT.md has deployment workflow documented
- [ ] Initial commit contains full SFDX project structure

**Priority:** P0
**Effort:** S
**Dependencies:** Task 1.1, Task 1.2

---

#### Task 1.4: Create Project Documentation

**Title:** Write CLAUDE.md, coding standards, and test writing guide

**Description:** Create the developer-facing documentation that guides how code should be written for ForceGuard. CLAUDE.md should contain project context, agent routing, directory structure, build commands, and OpenProject reference. Create TESTING_GUIDE.md explaining how to write test scenarios for new products. Create a CODING_STANDARDS.md section covering: bulkification patterns, error handling conventions, naming conventions (ForceGuard prefix for all classes), and SOQL/DML best practices.

**Acceptance Criteria:**
- [ ] CLAUDE.md exists with accurate project context and agent routing
- [ ] TESTING_GUIDE.md explains how to create test suites and cases
- [ ] Coding standards documented (naming, patterns, conventions)
- [ ] All documentation reflects the 4-layer model accurately

**Priority:** P1
**Effort:** S
**Dependencies:** Task 1.1

---

### Phase 2: Custom Objects & Data Model

**Description:** Build all 6 custom objects, 1 custom metadata type, validation rules, and relationships that form the data foundation of ForceGuard. Every subsequent phase depends on this data model. The objects must be deployed and validated in a scratch org before Phase 3 begins.

**Duration:** 4-6 days

---

#### Task 2.1: Build Regression_Test_Suite__c

**Title:** Create Test Suite custom object with 9 fields and tab

**Description:** Build the `Regression_Test_Suite__c` custom object that groups test cases per product. This is the top-level organizational unit. Fields: Name (standard), Product_Name__c (Text 80), Version__c (Text 10), Target_Org__c (Text 100, stores org alias or username), Description__c (Long Text Area 32000), Is_Active__c (Checkbox, default true), Total_Test_Cases__c (Rollup Summary counting child Regression_Test_Case__c), Last_Run_Date__c (DateTime), Last_Run_Status__c (Picklist: Not Run/Passed/Failed/Running). Create tab with custom icon. Create compact layout and page layout.

**Acceptance Criteria:**
- [ ] Object deploys successfully to scratch org
- [ ] All 9 fields exist with correct types and lengths
- [ ] Total_Test_Cases__c rollup counts child test cases correctly
- [ ] Tab visible in app launcher
- [ ] Page layout shows all fields in logical sections
- [ ] Compact layout shows Name, Product_Name__c, Last_Run_Status__c

**Priority:** P0
**Effort:** S
**Dependencies:** Task 1.1

---

#### Task 2.2: Build Regression_Test_Case__c

**Title:** Create Test Case custom object with 13 fields and Master-Detail to Suite

**Description:** Build `Regression_Test_Case__c` - the individual test definition. This object holds everything needed to execute and evaluate a single test. Fields: Name (Auto-Number, TC-{0000}), Test_Suite__c (Master-Detail to Regression_Test_Suite__c), Title__c (Text 255), Description__c (Long Text Area 32000), Test_Layer__c (Picklist: Deployment/Apex Test/Data Scenario/Static Analysis), Category__c (Picklist: Functional/Edge Case/Bulk Performance/Security Permission/Integration/Regression/UAT/Deployment), Perspective__c (Picklist: Developer/Admin/Product Manager/Designer/Client), Priority__c (Picklist: P0/P1/P2), Steps__c (Long Text Area 131072, stores Apex script or CLI command), Expected_Result__c (Long Text Area 32000), Assertion_Type__c (Picklist: Record Exists/Field Value/Record Count/Coverage Threshold/No Error/Custom Script), Is_Active__c (Checkbox, default true), Execution_Order__c (Number, for ordering within a layer).

**Acceptance Criteria:**
- [ ] Object deploys with Master-Detail to Regression_Test_Suite__c
- [ ] Auto-Number generates TC-0001, TC-0002, etc.
- [ ] All picklist values defined and correct
- [ ] Steps__c field large enough for Apex scripts (131072 chars)
- [ ] Page layout organized: General, Test Definition, Execution, Metadata sections
- [ ] Validation rule: Test_Layer__c is required

**Priority:** P0
**Effort:** S
**Dependencies:** Task 2.1

---

#### Task 2.3: Build Regression_Test_Run__c

**Title:** Create Test Run custom object with 13 fields

**Description:** Build `Regression_Test_Run__c` - the execution instance. One Run record is created each time a test suite is executed. Fields: Name (Auto-Number, RUN-{0000}), Test_Suite__c (Lookup to Regression_Test_Suite__c), Run_Date__c (DateTime), Completed_Date__c (DateTime), Triggered_By__c (Picklist: Manual/Scheduled/CI CD/Pre-Deployment), Status__c (Picklist: Queued/Running/Completed/Failed/Cancelled), Total_Tests__c (Number), Passed__c (Number), Failed__c (Number), Skipped__c (Number), Duration_Seconds__c (Number, 2 decimal), Code_Coverage__c (Percent, 2 decimal), Run_By__c (Lookup to User). Create a formula field Pass_Rate__c = IF(Total_Tests__c > 0, Passed__c / Total_Tests__c, 0).

**Acceptance Criteria:**
- [ ] Object deploys successfully
- [ ] Auto-Number generates RUN-0001, RUN-0002, etc.
- [ ] Pass_Rate__c formula calculates correctly
- [ ] Status__c picklist has all 5 values
- [ ] Triggered_By__c distinguishes manual, scheduled, CI/CD, and pre-deployment
- [ ] Page layout has sections: Run Info, Results, Timing

**Priority:** P0
**Effort:** S
**Dependencies:** Task 2.1

---

#### Task 2.4: Build Regression_Test_Result__c

**Title:** Create Test Result custom object with 11 fields and Master-Detail to Run

**Description:** Build `Regression_Test_Result__c` - the granular pass/fail record for each test case in each run. Fields: Name (Auto-Number, RES-{0000}), Test_Run__c (Master-Detail to Regression_Test_Run__c), Test_Case__c (Lookup to Regression_Test_Case__c), Status__c (Picklist: Passed/Failed/Skipped/Error), Actual_Result__c (Long Text Area 32000), Error_Message__c (Long Text Area 32000), Stack_Trace__c (Long Text Area 32000), Duration_Ms__c (Number, execution time in milliseconds), Layer__c (Picklist: Deployment/Apex Test/Data Scenario/Static Analysis, copied from test case for denormalization), Is_Regression__c (Checkbox, true if test previously passed and now fails), Previous_Status__c (Text 20, status from previous run for comparison).

**Acceptance Criteria:**
- [ ] Object deploys with Master-Detail to Regression_Test_Run__c
- [ ] Lookup to Regression_Test_Case__c works correctly
- [ ] Auto-Number generates RES-0001, etc.
- [ ] Error_Message__c and Stack_Trace__c can hold full Apex exception details
- [ ] Is_Regression__c defaults to false
- [ ] Cascade delete: deleting a Run deletes all Results

**Priority:** P0
**Effort:** S
**Dependencies:** Task 2.3, Task 2.2

---

#### Task 2.5: Build Regression_Config__mdt

**Title:** Create Configuration custom metadata type with 9 fields and default record

**Description:** Build `Regression_Config__mdt` - the configuration store for ForceGuard. This replaces hardcoded values and allows per-org customization. Fields: Label (standard), DeveloperName (standard), Coverage_Threshold__c (Number, default 85), Org_Alias__c (Text 100, target org alias), Auto_Ticket_Enabled__c (Checkbox, default false), Flaky_Threshold__c (Number, default 3, number of intermittent failures before flagging), Notification_Email__c (Email), Schedule_Frequency__c (Picklist: Daily/Weekly/Monthly/Custom), Enabled_Layers__c (Text 100, semicolon-delimited: "1;2;3;4"), Source_Path__c (Text 255, path to source directory for the product being tested). Create a default record named "Default" with sensible defaults.

**Acceptance Criteria:**
- [ ] Custom metadata type deploys successfully
- [ ] Default record exists with Coverage_Threshold = 85, Flaky_Threshold = 3
- [ ] Enabled_Layers__c defaults to "1;2;3;4"
- [ ] All fields are accessible via Apex (Regression_Config__mdt.getAll())
- [ ] No governor limit impact (CMT queries do not count against SOQL limit)

**Priority:** P0
**Effort:** S
**Dependencies:** Task 1.1

---

#### Task 2.6: Build Test_Coverage_Snapshot__c and Cross-Object Validation

**Title:** Create Coverage Snapshot object and all validation rules

**Description:** Build `Test_Coverage_Snapshot__c` for tracking coverage metrics over time. Fields: Name (Auto-Number, COV-{0000}), Snapshot_Date__c (Date), Test_Suite__c (Lookup to Regression_Test_Suite__c), Apex_Coverage__c (Percent), Flow_Coverage__c (Percent), VR_Coverage__c (Percent), Total_Metadata_Items__c (Number), Tested_Metadata_Items__c (Number), Overall_Score__c (Formula: (Tested_Metadata_Items__c / Total_Metadata_Items__c) * 100). Also create cross-object validation rules: on Regression_Test_Case__c, require Steps__c when Test_Layer__c = 'Data Scenario'. On Regression_Test_Result__c, require Error_Message__c when Status__c = 'Failed'. Set up FLS (Field-Level Security) for all objects across the permission sets to be created in Phase 3.

**Acceptance Criteria:**
- [ ] Test_Coverage_Snapshot__c deploys with all 9 fields
- [ ] Overall_Score__c formula calculates correctly
- [ ] Validation rule on Test_Case: Steps required for Data Scenario layer
- [ ] Validation rule on Test_Result: Error_Message required for Failed status
- [ ] All objects have appropriate FLS configured
- [ ] All objects deploy together without dependency errors

**Priority:** P1
**Effort:** M
**Dependencies:** Task 2.1, Task 2.2, Task 2.3, Task 2.4

---

### Phase 3: Core Framework Engine (Apex)

**Description:** Build the 5 core Apex classes that power ForceGuard's test execution pipeline. This is the heart of the product - the orchestrator, executor, assertion framework, reporter, and scheduler. All classes must follow bulkification patterns, use the custom objects from Phase 2, and achieve 90%+ code coverage with their corresponding test classes.

**Duration:** 7-10 days

---

#### Task 3.1: Build RegressionTestRunner (Orchestrator)

**Title:** Create the main orchestration class that drives the test pipeline

**Description:** Build `RegressionTestRunner` as the central entry point for ForceGuard test execution. This class implements `Database.Batchable<SObject>` and `Database.AllowsCallouts` for async execution. It accepts a Suite ID (or list of Suite IDs), queries all active test cases grouped by layer, and executes them in sequence through `RegressionTestExecutor`. The `start()` method queries active test cases, the `execute()` method processes one layer at a time, and the `finish()` method finalizes the run. Key logic: if Layer 1 or Layer 2 fails (blocking layers), skip subsequent layers and mark skipped test cases as 'Skipped'. Create the `Regression_Test_Run__c` record at start, update it progressively, and finalize with total counts and duration. Include an `@AuraEnabled` static method `runSuite(Id suiteId)` for LWC invocation that enqueues the batch and returns the batch job ID.

**Acceptance Criteria:**
- [ ] Implements Batchable<SObject> with AllowsCallouts
- [ ] Creates Regression_Test_Run__c at start with Status = 'Running'
- [ ] Executes layers 1-4 in sequence
- [ ] Skips layers 3 and 4 if Layer 1 fails, skips Layer 3 if Layer 2 fails
- [ ] Updates Run record with pass/fail/skip counts and duration
- [ ] Sets final Status to 'Completed' or 'Failed'
- [ ] Updates parent Suite's Last_Run_Date__c and Last_Run_Status__c
- [ ] @AuraEnabled runSuite() returns batch job ID
- [ ] Handles empty test suites gracefully (no test cases)
- [ ] Handles governor limits (processes in batches of 200)

**Priority:** P0
**Effort:** L
**Dependencies:** Task 2.1, Task 2.2, Task 2.3, Task 2.4, Task 2.5

---

#### Task 3.2: Build RegressionTestExecutor (Per-Layer Executor)

**Title:** Create the layer-specific test execution engine

**Description:** Build `RegressionTestExecutor` that handles the actual execution logic for each of the 4 layers. This class receives a list of test cases and a layer number, then dispatches to the correct execution method. Layer 1 (Deployment): Uses Tooling API to create a MetadataContainer and ContainerAsyncRequest, polls for completion, parses results. Layer 2 (Apex Tests): Uses Tooling API `runTestsAsynchronous` to execute test classes named in the test case Steps__c field, polls `ApexTestQueueItem` for completion, retrieves results from `ApexTestResult`. Layer 3 (Data Scenarios): Executes the anonymous Apex script stored in Steps__c using Tooling API `executeAnonymous`, then runs assertion logic defined in the test case. Layer 4 (Static Analysis): Queries `ApexClass` bodies via Tooling API and applies pattern-matching rules for common issues (SOQL in loops, hardcoded IDs, missing null checks). Each method creates `Regression_Test_Result__c` records. Returns a `LayerResult` inner class containing pass/fail counts and whether the layer blocks further execution.

**Acceptance Criteria:**
- [ ] Layer 1 validates deployment via Tooling API or Metadata API
- [ ] Layer 2 executes Apex tests via Tooling API and retrieves results
- [ ] Layer 3 executes anonymous Apex from Steps__c field
- [ ] Layer 4 runs static analysis pattern matching
- [ ] Creates Regression_Test_Result__c for every test case
- [ ] Returns LayerResult with blocking status
- [ ] Handles API callout errors gracefully (try/catch with meaningful messages)
- [ ] Supports polling for async operations (deploy, test execution)
- [ ] Respects callout limits (max 100 callouts per transaction)

**Priority:** P0
**Effort:** L
**Dependencies:** Task 3.1

---

#### Task 3.3: Build RegressionTestAssertion (Assertion Framework)

**Title:** Create reusable assertion methods for test scenario validation

**Description:** Build `RegressionTestAssertion` as a static utility class providing standardized assertion methods for Layer 3 data scenario testing. Methods: `assertEquals(Object expected, Object actual, String message)` - type-safe comparison for String, Integer, Decimal, Boolean, Date, DateTime; `assertNotNull(Object value, String message)`; `assertRecordExists(String sObjectType, String whereClause)` - executes SOQL and asserts at least 1 record; `assertRecordCount(String sObjectType, String whereClause, Integer expected)` - asserts exact count; `assertFieldValue(Id recordId, String objectType, String fieldName, Object expectedValue)` - queries record and compares field value; `assertCoverage(String className, Decimal minPercent)` - queries ApexCodeCoverageAggregate; `assertNoGovernorViolation(String testClassName)` - checks ApexTestResult for limit violations. Each method returns an `AssertionResult` inner class: `{ Boolean passed, String message, String expected, String actual }`. All SOQL uses dynamic queries with bind variables for safety.

**Acceptance Criteria:**
- [ ] All 7 assertion methods implemented and working
- [ ] AssertionResult inner class returned from every method
- [ ] Dynamic SOQL uses bind variables (no injection risk)
- [ ] assertEquals handles null values gracefully
- [ ] assertRecordExists does not throw on 0 results (returns failed assertion)
- [ ] assertCoverage queries Tooling API correctly
- [ ] All methods include descriptive failure messages with context
- [ ] Thread-safe (no instance state, all static methods)

**Priority:** P0
**Effort:** M
**Dependencies:** None (utility class)

---

#### Task 3.4: Build RegressionTestReporter (Report Generator)

**Title:** Create the reporting engine for test run results

**Description:** Build `RegressionTestReporter` that generates reports after test execution completes. Key methods: `generateRunSummary(Id testRunId)` - returns a structured summary with per-layer pass/fail/skip counts, duration, coverage, and failure details; `detectRegressions(Id testRunId)` - compares current results against the previous run for the same suite, marks Is_Regression__c = true on newly failing tests, returns list of regressions; `generateCsvExport(Id testRunId)` - creates CSV string with all results for download; `createCoverageSnapshot(Id testRunId)` - queries coverage data and creates Test_Coverage_Snapshot__c record; `getTrendData(Id suiteId, Integer runCount)` - returns last N runs' pass rates for sparkline chart. The reporter also updates the Run record with the regression count. Uses AggregateResult queries for efficiency.

**Acceptance Criteria:**
- [ ] generateRunSummary returns complete per-layer breakdown
- [ ] detectRegressions correctly identifies newly failing tests
- [ ] Is_Regression__c set to true only for previously-passing tests
- [ ] generateCsvExport produces valid CSV with headers
- [ ] createCoverageSnapshot creates accurate Test_Coverage_Snapshot__c
- [ ] getTrendData returns ordered list of historical pass rates
- [ ] Handles first-ever run (no previous run to compare)
- [ ] Uses AggregateResult queries, not row-level iteration

**Priority:** P1
**Effort:** M
**Dependencies:** Task 3.1, Task 3.2

---

#### Task 3.5: Build RegressionTestScheduler (Schedulable Batch)

**Title:** Create the scheduler for automated test execution

**Description:** Build `RegressionTestScheduler` implementing `Schedulable`. The `execute()` method reads all `Regression_Config__mdt` records, finds active suites matching each config's product, and enqueues `RegressionTestRunner` batch jobs for each. Key methods: `scheduleDaily()` - schedules at 2 AM daily; `scheduleWeekly()` - schedules Monday at 2 AM; `scheduleMonthly()` - schedules 1st of month at 2 AM; `scheduleCustom(String cronExpression)` - custom schedule; `unschedule()` - aborts the scheduled job by finding its CronTrigger ID; `isScheduled()` - returns whether the job is currently scheduled. The scheduler must handle the scenario where multiple suites exist - it enqueues them sequentially (not in parallel) to avoid governor limit conflicts. Include error handling that logs failures to a custom log record or sends email notification.

**Acceptance Criteria:**
- [ ] Implements Schedulable interface correctly
- [ ] Reads Regression_Config__mdt for schedule configuration
- [ ] Supports daily, weekly, monthly, and custom cron schedules
- [ ] Enqueues RegressionTestRunner for each active suite
- [ ] Handles multiple suites sequentially (no parallel batch conflicts)
- [ ] unschedule() correctly aborts the CronTrigger
- [ ] isScheduled() returns accurate boolean
- [ ] Error handling for failed batch enqueue (flex queue full, etc.)

**Priority:** P1
**Effort:** M
**Dependencies:** Task 3.1, Task 2.5

---

#### Task 3.6: Write Test Classes (90%+ Coverage)

**Title:** Create comprehensive test classes for all 5 Apex components

**Description:** Write test classes for RegressionTestRunner, RegressionTestExecutor, RegressionTestAssertion, RegressionTestReporter, and RegressionTestScheduler. Each test class must cover: positive scenarios (happy path), negative scenarios (invalid inputs, missing data), bulk scenarios (200+ records), error handling (exceptions, null values), and edge cases (empty suites, no previous runs, first run ever). Use a shared `ForceGuardTestDataFactory` for consistent test data creation. Mock HTTP callouts for Tooling API calls using `HttpCalloutMock`. Test the full pipeline end-to-end: create suite, create test cases, execute runner, verify results, verify reporter output. Target 90%+ coverage on every class.

**Acceptance Criteria:**
- [ ] Test class exists for each of the 5 Apex classes
- [ ] ForceGuardTestDataFactory utility class created
- [ ] Each test class has positive, negative, bulk, and edge case methods
- [ ] HttpCalloutMock implemented for Tooling API calls
- [ ] End-to-end test: suite creation through report generation
- [ ] All test classes pass with 0 failures
- [ ] Each class achieves 90%+ code coverage
- [ ] Bulk test uses 200+ records without governor limit errors
- [ ] All assertions use meaningful messages (not just System.assert(true))

**Priority:** P0
**Effort:** L
**Dependencies:** Task 3.1, Task 3.2, Task 3.3, Task 3.4, Task 3.5

---

### Phase 4: Audit Product Test Scenarios

**Description:** Define and create the specific test scenarios for the Audit (SOX/IPE) product. This phase translates the audit product catalog into concrete, executable test cases stored as `Regression_Test_Case__c` records. This is where ForceGuard proves its value by catching real regressions in a real, complex product with 35+ Apex classes, 8 Flows, and intricate automation chains.

**Duration:** 6-8 days

---

#### Task 4.1: Create Audit Test Suite and Seed Data Script

**Title:** Create the Audit test suite record and Apex seed data script

**Description:** Create the `Regression_Test_Suite__c` record for the Audit product (Product_Name = "User Access Audit", Version = "1.0", Target_Org = configured via CMT). Build an Apex script (or anonymous Apex block) that seeds all test case records for the Audit product. The seed script must create 40+ `Regression_Test_Case__c` records spanning all 4 layers, all 8 categories, and all 5 perspectives. Each test case must have: a clear Title, a Description explaining what it tests and why, the correct Test_Layer__c, Steps__c with executable Apex or validation commands, Expected_Result__c with precise pass criteria, and Assertion_Type__c. The seed data should be idempotent (can run multiple times without creating duplicates).

**Acceptance Criteria:**
- [ ] Regression_Test_Suite__c "User Access Audit" record exists
- [ ] 40+ Regression_Test_Case__c records seeded
- [ ] All 4 layers represented (Layer 1: ~5 tests, Layer 2: ~10, Layer 3: ~20, Layer 4: ~5)
- [ ] All 8 categories represented
- [ ] All 5 perspectives represented
- [ ] Seed script is idempotent (safe to re-run)
- [ ] Every test case has Steps__c and Expected_Result__c populated
- [ ] Test cases ordered via Execution_Order__c within each layer

**Priority:** P0
**Effort:** M
**Dependencies:** Task 2.2, Task 2.1

---

#### Task 4.2: Define Layer 1 Deployment Validation Tests

**Title:** Create deployment validation test cases for all Audit metadata

**Description:** Create `Regression_Test_Case__c` records for Layer 1 that verify all Audit metadata deploys without errors. Test cases should validate: (1) All 35 non-test Apex classes compile and deploy, (2) All 35 test Apex classes compile and deploy, (3) UserAuditTestDataFactory deploys, (4) All 7 custom objects deploy with all fields and relationships intact, (5) All 8 Flows deploy and activate without errors *[Note: These are the AUDIT product's Flows being tested - ForceGuard itself has no Flows]*, (6) All 7 LWC components deploy without JavaScript errors, (7) All 4 custom metadata types deploy with default records, (8) All 3 permission sets deploy with correct object and field permissions, (9) All 2 Visualforce pages deploy, (10) All cross-object references (lookups, master-detail) resolve. Steps__c for each test case should contain the metadata component list to validate.

**Acceptance Criteria:**
- [ ] 5-6 test cases created for Layer 1
- [ ] Covers all metadata types: Apex, objects, Audit product Flows, LWC, CMT, perm sets, VF
- [ ] Each test case lists specific components in Steps__c
- [ ] Expected_Result__c states "All components deploy without errors"
- [ ] Tests cover cross-reference resolution (lookups, formula fields)
- [ ] Test for Flow activation on Audit product Flows (not applicable to ForceGuard - it has no Flows)

**Priority:** P0
**Effort:** M
**Dependencies:** Task 4.1

---

#### Task 4.3: Define Layer 2 Apex Test Execution Scenarios

**Title:** Create Apex test execution test cases targeting Audit test classes

**Description:** Create `Regression_Test_Case__c` records for Layer 2 that execute the Audit product's existing 35 test classes. Organize tests into logical groups: (1) Core batch and service tests - UserAuditSnapshotBatchTest, AuditControllerTest, AuditControlCenterControllerTest, (2) Detection service tests - ProfileChangeDetectorTest, TerminationCrossCheckServiceTest, LoginHistoryServiceTest, SegregationOfDutiesServiceTest, (3) Queueable chain tests - TerminationCrossCheckQueueableTest, ProfileChangeDetectorQueueableTest, UserDeactivationQueueableTest, (4) Reporting tests - AuditReportServiceTest, AuditSummaryPdfGeneratorTest, AuditSummaryEmailServiceTest, (5) Controller tests - QuarterlyReviewControllerTest, BaselineComparisonControllerTest, (6) Feature and config tests - AuditFeatureServiceTest, FindingAssignmentServiceTest. Steps__c should list the specific test class names. Expected_Result__c should state the minimum coverage threshold (85%) and zero failures.

**Acceptance Criteria:**
- [ ] 8-10 test cases created for Layer 2
- [ ] All 35 test classes covered across the test cases
- [ ] Test cases grouped logically (core, detection, reporting, etc.)
- [ ] Each test case specifies classes in Steps__c
- [ ] Expected_Result__c includes coverage threshold (85%)
- [ ] Specific test case for UserAuditTestDataFactory (test data factory should compile)
- [ ] Test case for the full batch chain (batch -> queueable -> queueable)

**Priority:** P0
**Effort:** M
**Dependencies:** Task 4.1

---

#### Task 4.4: Define Layer 3 Data Scenario Tests

**Title:** Create end-to-end data scenario tests for Audit business logic

**Description:** Create `Regression_Test_Case__c` records for Layer 3 that execute real business scenarios against the Audit product. These are the highest-value tests because they verify actual business logic works end-to-end. Scenarios: (1) Full audit run lifecycle - create run, snapshot 200+ users, detect changes, generate findings, finalize run, (2) Terminated user detection - import CSV, cross-check against snapshots, verify Critical findings created, (3) Profile change detection - run 2 consecutive audits with profile changes between them, verify findings, (4) Segregation of duties - create users with toxic permission combinations, run audit, verify SoD violation findings, (5) Login anomaly detection - create login history records with anomalies, run audit, verify anomaly records, (6) SLA management - create findings, advance time, verify SLA status transitions (On Track -> At Risk -> Breached), (7) Quarterly sign-off enforcement - verify new runs blocked without sign-off, (8) Baseline comparison - set baseline, modify users, compare, verify drift detection, (9) Feature toggle behavior - disable features, verify corresponding checks are skipped, (10) PDF report generation - generate PDF, verify ContentVersion created. Steps__c should contain the anonymous Apex that sets up data, triggers the action, and runs assertions.

**Acceptance Criteria:**
- [ ] 15-20 test cases created for Layer 3
- [ ] Full audit run lifecycle tested end-to-end
- [ ] All 14 finding types tested (each type has at least 1 scenario)
- [ ] Batch->Queueable chain tested (UserAuditSnapshotBatch -> TerminationCrossCheckQueueable -> ProfileChangeDetectorQueueable)
- [ ] Feature toggle permutations tested (at least 5 toggle combinations)
- [ ] Each test case has complete anonymous Apex in Steps__c
- [ ] Assertions verify record creation, field values, and counts
- [ ] MIXED_DML scenario tested (UserDeactivationHandler pattern)
- [ ] Bulk scenario: 200+ user snapshots in single batch

**Priority:** P0
**Effort:** L
**Dependencies:** Task 4.1, Task 3.3

---

#### Task 4.5: Define Layer 4 Static Analysis Tests

**Title:** Create static analysis test cases for Audit Apex code quality

**Description:** Create `Regression_Test_Case__c` records for Layer 4 that analyze the Audit product's Apex code for quality and security issues. Test cases: (1) No SOQL queries inside loops - scan all 35 service classes, (2) No hardcoded Salesforce IDs - scan for 15/18-character ID patterns, (3) CRUD/FLS enforcement - verify all controller classes use WITH USER_MODE or Security.stripInaccessible(), (4) No DML inside loops - scan for insert/update/delete inside for/while loops, (5) Bulkification - verify trigger handlers accept List<SObject> not single records, (6) Governor limit awareness - verify batch size configurations, (7) Error handling - verify all @AuraEnabled methods have try/catch with AuraHandledException. Steps__c should contain the class names to analyze and the pattern to check for.

**Acceptance Criteria:**
- [ ] 5-7 test cases created for Layer 4
- [ ] Covers SOQL-in-loops, hardcoded IDs, CRUD/FLS, DML-in-loops
- [ ] Each test case specifies which classes to analyze
- [ ] Expected_Result__c defines acceptable violation count (e.g., 0 critical)
- [ ] Pattern definitions are precise enough for automated checking

**Priority:** P1
**Effort:** M
**Dependencies:** Task 4.1

---

#### Task 4.6: Define Edge Case and Bulk Test Scenarios

**Title:** Create edge case and bulk/performance test cases for Audit product

**Description:** Create `Regression_Test_Case__c` records that test boundary conditions and high-volume scenarios. Edge cases: (1) User with no Profile assignment, (2) User with no Role, (3) Empty org (0 users to snapshot), (4) Duplicate termination records with same email, (5) Concurrent batch execution (2 batches at once), (6) Audit run with all features disabled, (7) CSV import with malformed data (missing columns, special characters), (8) Finding resolution when finding is already resolved, (9) Baseline comparison when no baseline is set, (10) Sign-off on a run that has 0 findings. Bulk scenarios: (11) Snapshot 2000+ users without hitting governor limits, (12) Import 1000+ termination records, (13) 500+ findings in a single run, (14) Bulk resolve 200 findings at once, (15) CSV export with 5000+ findings.

**Acceptance Criteria:**
- [ ] 10-15 test cases created (mix of edge case and bulk)
- [ ] Each edge case has specific setup conditions in Steps__c
- [ ] Bulk tests specify record volumes (2000+, 1000+, 500+)
- [ ] Expected_Result__c defines expected behavior for each edge case
- [ ] Tests verify graceful handling (no unhandled exceptions)
- [ ] Governor limit tests verify no LimitException thrown
- [ ] Null handling tests cover all critical code paths

**Priority:** P1
**Effort:** M
**Dependencies:** Task 4.1

---

#### Task 4.7: Define Security and Permission Tests

**Title:** Create security and permission test cases for the 3 Audit permission sets

**Description:** Create `Regression_Test_Case__c` records that verify the 3 permission sets (Audit_Administrator, Audit_Full_Access, Audit_Viewer) grant correct access levels. Tests: (1) Audit_Administrator can CRUD all 7 objects - create, read, update, delete records for each object, (2) Audit_Administrator has Bypass_All_Flows custom permission *[Note: This is the AUDIT product's custom permission for their Flows - ForceGuard has no Flows to bypass]*, (3) Audit_Full_Access can CRUD all objects but does NOT have Bypass_All_Flows, (4) Audit_Viewer can READ all objects but cannot Create, Update, or Delete, (5) User without any permission set cannot access any audit objects, (6) Audit_Viewer cannot run audit batch (runAuditNow should fail), (7) Audit_Viewer cannot resolve findings (resolveFindings should fail), (8) FLS enforcement - verify WITH USER_MODE blocks field access appropriately, (9) Sharing rules - verify record visibility based on ownership, (10) All @AuraEnabled methods handle insufficient access gracefully (AuraHandledException, not raw DML exception). Steps__c should use `System.runAs()` with test users assigned specific permission sets.

**Acceptance Criteria:**
- [ ] 8-10 test cases created for security testing
- [ ] All 3 permission sets tested (Admin, Full Access, Viewer)
- [ ] CRUD tested for all 7 custom objects per permission set
- [ ] Bypass_All_Flows custom permission verified on Admin only (Audit product's permission)
- [ ] Negative tests: Viewer cannot write, no-perm-set user blocked
- [ ] FLS enforcement verified via WITH USER_MODE queries
- [ ] All tests use System.runAs() with appropriate test users
- [ ] Error messages are user-friendly (not raw exception details)

**Priority:** P0
**Effort:** M
**Dependencies:** Task 4.1

---

### Phase 5: Lightning UI (LWC Dashboard)

**Description:** Build the 4 Lightning Web Components that provide the user interface for ForceGuard. The dashboard is the primary interaction point for admins - they use it to run test suites, view results, track trends, and manage test cases. All components must use SLDS, be responsive, and feel native to Salesforce. Platform events enable real-time updates during test execution.

**Duration:** 7-10 days

---

#### Task 5.1: Build regressionTestDashboard LWC

**Title:** Create the main ForceGuard dashboard with health score, trends, and actions

**Description:** Build `regressionTestDashboard` as the primary landing page for ForceGuard. Layout: Top row - 4 summary cards (Overall Pass Rate as percentage with trend arrow, Total Test Cases count, Active Failures count in red, Flow Coverage percentage). Second row - Trend sparkline showing pass rate over last 10 runs (use SLDS chart pattern or custom SVG). Third row - Recent Runs table showing last 10 runs with columns: Run Name, Suite, Date, Status (badge), Passed, Failed, Duration, and a "View" action button. Action bar: "Run All Suites" button (calls RegressionTestRunner.runSuite), "Run Selected" dropdown per suite, "Schedule" button opening config modal. Real-time updates: subscribe to `ForceGuard_Test_Complete__e` platform event via `lightning/empApi` to refresh data when a run completes. Apex controller: `RegressionDashboardController` with @AuraEnabled methods: `getDashboardSummary()`, `getRecentRuns(Integer limit)`, `getTrendData(Id suiteId)`, `runSuite(Id suiteId)`, `getBatchJobStatus(Id jobId)`.

**Acceptance Criteria:**
- [ ] 4 summary cards display correct data from Apex
- [ ] Trend chart renders pass rate over last 10 runs
- [ ] Recent runs table with sorting, badges, and view action
- [ ] "Run All Suites" button triggers batch and shows progress spinner
- [ ] Platform event subscription refreshes data on run completion
- [ ] SLDS-compliant: uses lightning-card, lightning-datatable, lightning-badge
- [ ] Responsive layout works on desktop and tablet
- [ ] Loading spinner shown during data fetch
- [ ] Error handling with user-friendly toast messages
- [ ] Empty state handled (no suites, no runs)

**Priority:** P0
**Effort:** L
**Dependencies:** Task 3.1, Task 3.4

---

#### Task 5.2: Build testSuiteManager LWC

**Title:** Create the test suite and case management UI

**Description:** Build `testSuiteManager` for CRUD operations on test suites and cases. Two-panel layout: left panel shows list of suites (filterable by product, status), right panel shows test cases for the selected suite. Suite list: Name, Product, Version, Status badge, Test Count, Last Run Status. Clicking a suite loads its test cases. Test case table: Title, Layer (color-coded badge), Category, Perspective, Priority, Is_Active toggle. Actions: "New Suite" button opens creation modal, "New Test Case" opens wizard (4-step: General info, Test Definition with layer/category/perspective, Steps/Script editor, Assertions). Inline editing for test case fields. Bulk actions: activate/deactivate selected, delete selected. Filter bar: filter by layer, category, perspective, priority, active status. Apex controller: `TestSuiteManagerController` with methods for suite CRUD, case CRUD, bulk operations.

**Acceptance Criteria:**
- [ ] Two-panel layout: suite list + case detail
- [ ] Suite CRUD (create, edit, delete) via modals
- [ ] Test case CRUD with 4-step creation wizard
- [ ] Inline editing on test case table
- [ ] Filter bar with layer, category, perspective, priority filters
- [ ] Bulk activate/deactivate and bulk delete
- [ ] Steps__c field uses textarea with monospace font (code editor feel)
- [ ] Layer badges color-coded (L1=blue, L2=purple, L3=amber, L4=green)
- [ ] Confirmation modal before delete operations
- [ ] SLDS-compliant throughout

**Priority:** P0
**Effort:** L
**Dependencies:** Task 2.1, Task 2.2

---

#### Task 5.3: Build testRunViewer LWC

**Title:** Create the test run history and results viewer

**Description:** Build `testRunViewer` that displays all test runs with expandable detail views. Main view: paginated table of all runs with columns: Run Number, Suite Name, Run Date, Triggered By, Status (badge: green=Completed, red=Failed, yellow=Running, gray=Cancelled), Pass/Fail/Skip counts, Duration, Coverage %. Click a row to expand and show per-layer results: Layer name, tests in layer, passed/failed, duration, and a "View Details" link. "View Details" navigates to testResultDetail (or opens a modal) showing individual test results. Action buttons: "Re-run Failed" (creates new run with only failed test cases), "Run All" (re-runs entire suite), "Export CSV" (downloads results). Filter: by suite, by status, by date range. Sort: by date (default newest first), by status, by pass rate. Apex controller: `TestRunViewerController` with methods: `getTestRuns(filters)`, `getRunDetail(Id runId)`, `rerunFailed(Id runId)`, `exportCsv(Id runId)`.

**Acceptance Criteria:**
- [ ] Paginated table of test runs (20 per page)
- [ ] Expandable row showing per-layer breakdown
- [ ] Status badges with correct colors
- [ ] "Re-run Failed" creates new run with only failed tests
- [ ] "Export CSV" downloads results file
- [ ] Filter by suite, status, date range
- [ ] Sort by date, status, pass rate
- [ ] Real-time update when a running test completes (platform event)
- [ ] Duration formatted as human-readable (e.g., "3m 12s")
- [ ] Empty state when no runs exist

**Priority:** P0
**Effort:** M
**Dependencies:** Task 3.1, Task 3.4

---

#### Task 5.4: Build testResultDetail LWC

**Title:** Create the failure drill-down and result detail view

**Description:** Build `testResultDetail` that shows granular detail for a single test run or individual test result. When viewing a run: summary bar (total/passed/failed/skipped/duration/coverage), then 4 collapsible sections for each layer. Each layer section shows individual test results with: Test Case title, Status badge, Duration, and expandable detail. For failed tests, the expanded detail shows: Expected Result (from test case), Actual Result (from result record), Error Message (highlighted in red), Stack Trace (collapsible code block with monospace font), Related Metadata (which Apex class, Flow, or object was involved), "Is Regression" indicator (if this test previously passed). Actions per failed test: "Mark as Known Issue" toggle (adds to known issues list), "Re-run This Test" button, "View Test Case" link. At the bottom: "Mark All Reviewed" button, "Create Ticket" button (manual ticket creation for non-regression failures).

**Acceptance Criteria:**
- [ ] Summary bar with total/passed/failed/skipped/duration
- [ ] 4 collapsible layer sections
- [ ] Individual test result cards with expandable details
- [ ] Expected vs Actual comparison for failed tests
- [ ] Error message displayed in red with full text
- [ ] Stack trace in collapsible monospace code block
- [ ] "Is Regression" highlighted with warning badge
- [ ] "Mark as Known Issue" toggle updates record
- [ ] "Re-run This Test" triggers single test execution
- [ ] Copy-to-clipboard on error message and stack trace

**Priority:** P1
**Effort:** M
**Dependencies:** Task 5.3

---

### Phase 6: Automation & Reporting

**Description:** Build the automated behaviors that make ForceGuard a "set it and forget it" product. This includes: automatic ticket creation on regression failures, email notifications, PDF reports, scheduled execution, and external integrations. These features transform ForceGuard from a manual testing tool into an automated regression monitoring system.

**Duration:** 6-8 days

#### No Flows Policy (CRITICAL)

**ForceGuard is a managed package product - ALL automation MUST be built in Apex, NOT Flows.**

**Why:**
- **IP Protection:** Flows expose business logic to clients. In Flow Builder, customers can see every decision, formula, query, and field assignment. This reveals your product's algorithms, business rules, and competitive advantages.
- **Obfuscation:** Apex code in managed packages is obfuscated - clients cannot see method implementations, logic, or algorithms. They only see method signatures.
- **Licensing Enforcement:** Flow logic can be copied, reverse-engineered, or exported. Apex cannot.
- **Professional Image:** Enterprise buyers expect managed packages to be code-based, not declarative automation that looks like "admin configuration."

**Implementation Pattern:**
- Record automation → Apex Trigger with handler class
- Scheduled automation → Schedulable Apex
- User interactions → LWC with Apex controllers
- Platform events → Apex Trigger or EventBus.subscribe()

**What about @InvocableMethod?**
- Apex methods marked `@InvocableMethod` can still be called from Flow Builder if an admin wants to extend functionality
- But the core product logic is protected in obfuscated Apex
- Customers see method signature and description, not implementation

---

#### Task 6.1: Build Auto-Regression-Finding Trigger

**Title:** Create Apex Trigger that creates findings for regression failures

**Description:** Build an Apex Trigger on `Regression_Test_Result__c` (After Insert) that fires when Status__c = 'Failed' AND Is_Regression__c = true. Implementation: (1) Trigger `RegressionTestResultTrigger` with handler pattern calling `RegressionFindingHandler.handleAfterInsert(List<Regression_Test_Result__c>)`. (2) Handler filters records where Status = 'Failed' AND Is_Regression = true, then queries related Regression_Test_Case__c and Regression_Test_Run__c for context. (3) Creates `Regression_Finding__c` records with: test case title, suite name, error message, expected result, actual result, layer, category, perspective, priority, and timestamp. (4) If Auto_Ticket_Enabled__c is true in Regression_Config__mdt, calls `RegressionTicketCreator.createTickets(List<RegressionFindingRequest>)` (@InvocableMethod) that creates work packages in the configured project management tool. (5) Trigger must respect the Bypass_All_Automation__c custom permission (check via `FeatureManagement.checkPermission('Bypass_All_Automation')`). (6) Fully bulkified - handles 200+ results in a single transaction. (7) Deduplicates findings by test case + run ID to prevent duplicates.

**Acceptance Criteria:**
- [ ] Apex Trigger `RegressionTestResultTrigger` created with `after insert` context
- [ ] Handler class `RegressionFindingHandler` with `handleAfterInsert` method
- [ ] Entry condition: Status = Failed AND Is_Regression = true
- [ ] Queries parent test case and run for context (bulkified)
- [ ] Creates regression finding records with full context
- [ ] Calls invocable action for auto-ticketing (when enabled)
- [ ] Respects Bypass_All_Automation custom permission
- [ ] Fully bulkified - no SOQL/DML in loops
- [ ] Does not create duplicates for the same failure (dedup by test case + run)
- [ ] Test class achieves 90%+ coverage with bulk test (200+ records)
- [ ] `with sharing` keyword declared
- [ ] All SOQL queries use `WITH USER_MODE` or `WITH SYSTEM_MODE`

**Priority:** P0
**Effort:** M
**Dependencies:** Task 2.4, Task 2.5

---

#### Task 6.2: Build Email Notification System

**Title:** Create configurable email notifications for test run results

**Description:** Build `RegressionTestNotifier` (Queueable, implements Database.AllowsCallouts) that sends email notifications after test runs complete. The email should contain: subject line with suite name and pass/fail status, body with summary (total/passed/failed), per-layer breakdown, list of failures with error messages, regression count highlighted, link to the ForceGuard dashboard in Salesforce. Recipients are configured via Regression_Config__mdt.Notification_Email__c (supports semicolon-delimited list). Email is sent only for: (a) failed runs, (b) runs with regressions, or (c) all runs (configurable via CMT setting). Use Messaging.SingleEmailMessage with HTML body for professional formatting. Include an "unsubscribe" note directing users to the config.

**Acceptance Criteria:**
- [ ] Email sent after test run completion
- [ ] Subject includes suite name and PASSED/FAILED status
- [ ] Body includes per-layer breakdown and failure list
- [ ] Regressions highlighted with bold/red formatting
- [ ] Recipients from Regression_Config__mdt
- [ ] Supports multiple recipients (semicolon-delimited)
- [ ] Configurable: send on failure only, regressions only, or always
- [ ] HTML email body with professional formatting
- [ ] Handles missing/invalid email addresses gracefully
- [ ] Dashboard link included in email body

**Priority:** P1
**Effort:** M
**Dependencies:** Task 3.4, Task 2.5

---

#### Task 6.3: Build PDF and CSV Report Generation

**Title:** Create professional PDF reports and CSV exports for test results

**Description:** Extend `RegressionTestReporter` with PDF generation capabilities. Build a Visualforce page `ForceGuardTestReport` that renders a professional PDF report with: header (ForceGuard logo/title, suite name, run date), executive summary (pass rate, regression count, coverage), per-layer results table, failure details with error messages, trend chart (last 5 runs), and footer with generation timestamp. The Apex controller `ForceGuardReportController` queries all data. Method `generatePdf(Id testRunId)` uses PageReference.getContentAsPDF() to create a ContentVersion linked to the run record. CSV export method `generateCsv(Id testRunId)` creates a downloadable CSV with columns: Test Case, Layer, Category, Status, Duration, Error Message, Is Regression.

**Acceptance Criteria:**
- [ ] Visualforce page renders correctly in PDF mode
- [ ] PDF includes executive summary, per-layer results, failure details
- [ ] PDF stored as ContentVersion linked to Regression_Test_Run__c
- [ ] CSV export includes all result fields with proper headers
- [ ] PDF accessible via download button in LWC
- [ ] Report handles large result sets (500+ results) without timeout
- [ ] Professional formatting with SLDS-like styling
- [ ] Trend data included for last 5 runs

**Priority:** P1
**Effort:** M
**Dependencies:** Task 3.4

---

#### Task 6.4: Build Scheduled Test Run Automation

**Title:** Create the platform event and scheduled execution pipeline

**Description:** Build the complete scheduled execution pipeline: (1) `ForceGuard_Test_Complete__e` platform event with fields: Suite_Id__c (Text), Run_Id__c (Text), Status__c (Text), Pass_Rate__c (Number), Failed_Count__c (Number), Regression_Count__c (Number). (2) Update `RegressionTestRunner.finish()` to publish this event after run completion. (3) Update `regressionTestDashboard` LWC to subscribe to this event via `lightning/empApi` and auto-refresh. (4) Build `RegressionTestSchedulerController` (Apex LWC controller) with @AuraEnabled methods: `scheduleRuns(String frequency)`, `unscheduleRuns()`, `getScheduleStatus()`, `getNextScheduledRun()`. (5) Build schedule configuration modal in the dashboard LWC. The scheduler should handle retry logic: if a run fails due to a transient error (lock contention, governor limit), retry once after 5 minutes.

**Acceptance Criteria:**
- [ ] Platform event ForceGuard_Test_Complete__e created with all fields
- [ ] RegressionTestRunner publishes event on completion
- [ ] LWC dashboard subscribes and auto-refreshes on event
- [ ] Schedule configuration via LWC modal
- [ ] Supports daily, weekly, monthly frequency
- [ ] Shows next scheduled run date/time
- [ ] Unschedule removes the CronTrigger
- [ ] Retry logic on transient failures (1 retry after 5 min)
- [ ] Schedule status indicator in dashboard header

**Priority:** P1
**Effort:** M
**Dependencies:** Task 3.5, Task 5.1

---

#### Task 6.5: Build External Integration Callout

**Title:** Create REST callout for auto-ticket creation on regression failures

**Description:** Build `RegressionTicketCreator` (invocable action, called from the Apex handler in Task 6.1) that creates tickets in external project management tools when regressions are detected. Implementation: (1) `@InvocableMethod` that accepts regression details (test case title, error message, suite name, run ID), (2) Uses Named Credential for authentication (supports OpenProject API), (3) Creates a work package with: subject = "[ForceGuard Regression] {test case title}", description = formatted failure details with links, type = Bug, priority based on test case priority. (4) Stores the external ticket ID back on the Regression_Test_Result__c record. (5) If a ticket already exists for this test case (check by external ID), add a comment instead of creating a duplicate. Use HttpRequest/HttpResponse with proper error handling for network failures, rate limiting (429), and authentication errors (401). Named Credential: `ForceGuard_Ticket_System`. **Note:** While this is an `@InvocableMethod` (callable from Flow Builder), it is primarily called from Apex code. The @InvocableMethod annotation allows customers to extend functionality if needed, but the core logic is protected via obfuscation.

**Acceptance Criteria:**
- [ ] @InvocableMethod callable from Apex or Flow (if customer extends)
- [ ] Uses Named Credential for authentication
- [ ] Creates work package with formatted description
- [ ] Avoids duplicate tickets (checks existing external ID)
- [ ] Updates existing ticket with comment if already exists
- [ ] Stores external ticket ID on result record
- [ ] Error handling for network failures, 401, 429
- [ ] HttpCalloutMock test class for 90%+ coverage
- [ ] Configurable via Regression_Config__mdt (enable/disable)
- [ ] `with sharing` and `WITH USER_MODE`/`WITH SYSTEM_MODE` on all SOQL

**Priority:** P2
**Effort:** M
**Dependencies:** Task 6.1

---

### Phase 7: Documentation & Packaging

**Description:** Write all user-facing documentation, create the deployable package, and prepare for distribution. This phase transforms ForceGuard from a development project into a shippable product. Documentation must be thorough enough for a new user to install, configure, and use ForceGuard without any support from the development team.

**Duration:** 5-7 days

---

#### Task 7.1: Write Installation Guide

**Title:** Create step-by-step installation guide for ForceGuard

**Description:** Write `docs/INSTALLATION-GUIDE.md` covering the complete installation process. Sections: (1) Prerequisites - Salesforce edition requirements (Enterprise+), required features (Platform Events, Custom Metadata Types), API access enabled. (2) Installation options - unmanaged package URL, SFDX deployment from GitHub, zip file deployment. (3) Step-by-step installation - download package, deploy to sandbox first, verify deployment, assign permission sets. (4) Post-install configuration - create your first test suite, configure notification emails, set coverage thresholds, enable/disable layers. (5) Verification - run the built-in health check, execute the sample test suite, verify dashboard loads. (6) Troubleshooting - common errors (missing permissions, API version mismatch, feature not enabled), how to uninstall cleanly. Include screenshots of key steps (or placeholder descriptions for screenshots).

**Acceptance Criteria:**
- [ ] Covers all 3 installation methods (package, SFDX, zip)
- [ ] Prerequisites clearly listed
- [ ] Step-by-step with numbered instructions
- [ ] Post-install configuration guide
- [ ] Verification steps to confirm successful install
- [ ] Troubleshooting section with 5+ common issues
- [ ] Permission set assignment documented
- [ ] Written for admin audience (no developer jargon)

**Priority:** P0
**Effort:** M
**Dependencies:** All Phase 1-6 tasks

---

#### Task 7.2: Write Configuration Guide

**Title:** Create guide for configuring ForceGuard settings and thresholds

**Description:** Write `docs/CONFIGURATION-GUIDE.md` covering all configurable aspects of ForceGuard. Sections: (1) Custom Metadata Configuration - how to edit Regression_Config__mdt records, what each field controls, recommended defaults. (2) Coverage Thresholds - what the coverage threshold means, how to set it per suite. (3) Layer Configuration - how to enable/disable specific layers, when you would skip a layer. (4) Notification Configuration - setting up email recipients, configuring notification triggers (all runs, failures only, regressions only). (5) Schedule Configuration - how to set up daily/weekly/monthly scheduled runs, how to view/cancel schedules. (6) Permission Set Assignment - which permission set to assign to which role (Admin vs Viewer). (7) External Integration Setup - configuring Named Credentials for auto-ticketing, supported ticket systems. (8) Advanced Configuration - custom cron expressions, Apex test class filtering, source path configuration.

**Acceptance Criteria:**
- [ ] All Regression_Config__mdt fields documented with descriptions
- [ ] Coverage threshold configuration explained
- [ ] Layer enable/disable documented
- [ ] Notification setup with step-by-step
- [ ] Schedule configuration with examples
- [ ] Permission set guidance by role
- [ ] Named Credential setup for integrations
- [ ] Each section has a "Recommended Settings" callout

**Priority:** P0
**Effort:** M
**Dependencies:** All Phase 1-6 tasks

---

#### Task 7.3: Write User and Admin Guide

**Title:** Create comprehensive user guide for the ForceGuard UI

**Description:** Write `docs/USER-GUIDE.md` covering how to use ForceGuard day-to-day. Two sections: Admin Guide and User Guide. Admin Guide: (1) Dashboard overview - what each card/chart means, how to read trends, (2) Running test suites - manual execution, interpreting progress, (3) Viewing results - navigating run history, understanding per-layer results, (4) Managing failures - drill-down, regression identification, marking known issues, (5) Reports - generating PDFs, exporting CSVs, sharing with stakeholders. User Guide: (1) Viewing your dashboard - pass rates, active failures, coverage, (2) Understanding test results - what passed/failed/skipped means, (3) Responding to failures - reading error messages, identifying regressions, (4) Coverage tracking - what coverage percentage means, how to improve it.

**Acceptance Criteria:**
- [ ] Dashboard walkthrough with all elements explained
- [ ] Manual test execution guide with expected flow
- [ ] Results interpretation guide
- [ ] Failure drill-down walkthrough
- [ ] Report generation instructions
- [ ] Written for non-technical admin audience
- [ ] Separate sections for admin vs regular user
- [ ] Glossary of ForceGuard-specific terms

**Priority:** P1
**Effort:** M
**Dependencies:** Phase 5 LWC tasks

---

#### Task 7.4: Write Test Writing Guide

**Title:** Create guide for writing new test cases and test suites

**Description:** Write `docs/WRITING-TESTS.md` covering how to create new test scenarios for any Salesforce product. Sections: (1) Test Case anatomy - explanation of every field on Regression_Test_Case__c, (2) Choosing the right layer - decision tree for L1/L2/L3/L4, (3) Writing Layer 1 tests - what to include in deployment validation, (4) Writing Layer 2 tests - specifying Apex test classes, coverage requirements, (5) Writing Layer 3 tests - step-by-step guide for anonymous Apex data scenarios with templates for: record creation, trigger verification, Flow path testing, permission testing, (6) Writing Layer 4 tests - defining static analysis rules, (7) Choosing perspectives - when to tag as Developer/Admin/PM/Designer/Client with examples, (8) Writing good assertions - using RegressionTestAssertion methods, common patterns, (9) Templates - copy-paste templates for the 8 most common test patterns.

**Acceptance Criteria:**
- [ ] Every Regression_Test_Case__c field explained
- [ ] Layer selection decision tree
- [ ] Per-layer writing guides with examples
- [ ] Perspective selection guidance with examples
- [ ] Assertion method reference with code samples
- [ ] 8+ copy-paste templates for common patterns
- [ ] Real-world examples from the Audit test suite
- [ ] "Do's and Don'ts" section

**Priority:** P1
**Effort:** M
**Dependencies:** Phase 3 and Phase 4 tasks

---

#### Task 7.5: Create Gumroad/AppExchange Listing

**Title:** Create product listing copy, screenshots, and marketing materials

**Description:** Create `GUMROAD-LISTING.md` with the complete product listing for Gumroad (initial distribution channel) and future AppExchange listing. Sections: (1) Product headline and tagline, (2) Product description (500-word marketing copy), (3) Key features with bullet points (8 features), (4) Competitive comparison table (ForceGuard vs Copado vs Provar vs ACCELQ vs testRigor), (5) Pricing table (4 tiers), (6) FAQ (10 questions), (7) Technical requirements, (8) What's included in the download, (9) Testimonials placeholder, (10) Support contact info. Also create a `SCREENSHOTS.md` describing exactly what screenshots need to be captured (dashboard, results, suite manager, failure detail) with composition notes.

**Acceptance Criteria:**
- [ ] Marketing copy written in professional, benefit-focused tone
- [ ] 8 key features with compelling descriptions
- [ ] Competitive comparison table accurate
- [ ] Pricing table with all 4 tiers
- [ ] 10 FAQ questions answered
- [ ] Technical requirements listed
- [ ] Screenshot descriptions for 6+ screens
- [ ] Ready to publish on Gumroad without editing

**Priority:** P2
**Effort:** M
**Dependencies:** All Phase 1-6 tasks

---

#### Task 7.6: Package as Deployable Product

**Title:** Create unlocked package with version 1.0 and post-install script

**Description:** Create the deployable package for ForceGuard. Steps: (1) Create unlocked package: `sf package create --name ForceGuard --package-type Unlocked --path force-app`, (2) Create package version 1.0.0: `sf package version create --package ForceGuard --installation-key <key> --wait 20`, (3) Build `ForceGuardPostInstallScript` (implements InstallHandler) that: creates default Regression_Config__mdt record, creates sample test suite with 3 demo test cases, assigns ForceGuard_Admin permission set to the installing user, sends welcome email, (4) Build `ForceGuardUninstallScript` (implements UninstallHandler) that: aborts scheduled jobs, sends farewell email, (5) Verify package installs cleanly on a fresh scratch org, (6) Verify all components are included, (7) Create zip file alternative for non-package deployment, (8) Create deployment script (`scripts/deploy.sh`) for SFDX deployment.

**Acceptance Criteria:**
- [ ] Unlocked package created successfully
- [ ] Version 1.0.0 created with installation key
- [ ] PostInstallScript creates default config and sample suite
- [ ] UninstallScript cleans up scheduled jobs
- [ ] Package installs on fresh scratch org without errors
- [ ] All 6 objects, all Apex classes, all LWC included
- [ ] CRITICAL: Zero Flows in package (verify with `sf project retrieve start -m Flow`)
- [ ] Zip file alternative created for manual deployment
- [ ] Deployment script works for SFDX-based deployment
- [ ] Installation verified on both Developer and Enterprise edition

**Priority:** P0
**Effort:** L
**Dependencies:** All Phase 1-6 tasks

---

## 3. Audit Product Test Scenarios

### 3.1 Audit Product Automation Test Mapping

**Context:** The Audit product (the first product ForceGuard will test) has 8 record-triggered automations (Flows or Apex Triggers). ForceGuard must verify these automations work correctly. This section maps each Audit automation to specific ForceGuard test cases.

**CRITICAL CLARIFICATION:** These Flow references (Flow 1-8 below) are the **AUDIT product's Flows being TESTED** by ForceGuard. **ForceGuard itself contains ZERO Flows** (see "No Flows Policy" in Phase 6). ForceGuard is pure Apex + LWC to protect IP. The Audit product being tested may contain Flows, but the ForceGuard test framework does not.

Each of the 8 Audit automations maps to specific ForceGuard test cases:

#### Flow 1: Set_Latest_Flag_On_New_Audit_Run (Before Insert on Audit_Run__c)

| Test ID | Scenario | Category | Priority | Steps |
|---------|----------|----------|----------|-------|
| AUD-FLOW-001 | New audit run has Is_Latest__c = true after insert | Functional | P0 | Insert Audit_Run__c. Assert Is_Latest__c = true. |
| AUD-FLOW-002 | Multiple inserts in same transaction all get Is_Latest = true (before second Flow clears) | Edge Case | P1 | Insert 2 Audit_Run__c in same transaction. Assert both get Is_Latest = true before after-insert fires. |
| AUD-FLOW-003 | Bypass_All_Flows custom permission bypasses this Flow | Security | P1 | Run as user with Bypass_All_Flows. Insert Audit_Run__c. Assert Is_Latest__c respects bypass behavior. |

#### Flow 2: Set_Latest_Audit_Run (After Insert on Audit_Run__c)

| Test ID | Scenario | Category | Priority | Steps |
|---------|----------|----------|----------|-------|
| AUD-FLOW-004 | Previous runs have Is_Latest__c cleared after new insert | Functional | P0 | Insert Run A, verify Is_Latest = true. Insert Run B, verify Run A Is_Latest = false, Run B Is_Latest = true. |
| AUD-FLOW-005 | Works correctly with 50+ existing runs | Bulk | P1 | Insert 50 runs sequentially. Verify only the last has Is_Latest = true. |
| AUD-FLOW-006 | Bypass_All_Flows prevents clearing of old Is_Latest flags | Security | P1 | Run as admin with bypass. Insert new run. Verify previous run's Is_Latest is NOT cleared (bypass active). |

#### Flow 3: Audit_Run_Status_Update (After Save on Audit_Run__c, Status = 'Completed')

| Test ID | Scenario | Category | Priority | Steps |
|---------|----------|----------|----------|-------|
| AUD-FLOW-007 | Finding counts updated when status changes to Completed | Functional | P0 | Create run with 5 Critical, 3 Warning, 2 Info findings. Update Status to 'Completed'. Assert Finding_Count_Critical__c = 5, Warning = 3, Info = 2, Total = 10. |
| AUD-FLOW-008 | Finding counts are 0 when no findings exist | Edge Case | P1 | Create run with 0 findings. Update Status to 'Completed'. Assert all counts = 0. |
| AUD-FLOW-009 | Flow does not fire when status changes to 'Running' (only 'Completed') | Regression | P0 | Update Status to 'Running'. Assert finding counts are NOT recalculated. |

#### Flow 4: Notify_Audit_Team (After Save on Audit_Run__c, Status = 'Completed')

| Test ID | Scenario | Category | Priority | Steps |
|---------|----------|----------|----------|-------|
| AUD-FLOW-010 | Email sent when completed run has Critical findings > 0 | Functional | P0 | Create run with Critical findings. Update Status to 'Completed'. Assert email sent (check Messaging.sendEmail invocation count). |
| AUD-FLOW-011 | No email sent when completed run has 0 Critical findings | Functional | P1 | Create run with only Info findings. Update Status to 'Completed'. Assert no email sent. |

#### Flow 5: Set_Assignment_Date (Before Save on Audit_Finding__c)

| Test ID | Scenario | Category | Priority | Steps |
|---------|----------|----------|----------|-------|
| AUD-FLOW-012 | Assigned_Date__c stamped when Assigned_To__c set from null | Functional | P0 | Create finding with Assigned_To = null. Update Assigned_To to a user. Assert Assigned_Date__c = TODAY(). |
| AUD-FLOW-013 | Assigned_Date__c NOT updated when Assigned_To changes between users | Edge Case | P1 | Set Assigned_To to User A (stamps date). Change to User B. Assert Assigned_Date stays as original date. |
| AUD-FLOW-014 | Bulk assignment of 200 findings stamps date on all | Bulk | P1 | Create 200 findings. Bulk update Assigned_To. Assert all 200 have Assigned_Date = TODAY(). |

#### Flow 6: Set_Remediation_Due_Date (Before Save on Audit_Finding__c, Create only)

| Test ID | Scenario | Category | Priority | Steps |
|---------|----------|----------|----------|-------|
| AUD-FLOW-015 | Critical finding gets due date = TODAY + 7 days | Functional | P0 | Create finding with Severity = Critical. Assert Remediation_Due_Date__c = TODAY() + 7. |
| AUD-FLOW-016 | Warning finding gets due date = TODAY + 30 days | Functional | P0 | Create finding with Severity = Warning. Assert Remediation_Due_Date__c = TODAY() + 30. |
| AUD-FLOW-017 | Info finding gets due date = TODAY + 90 days | Functional | P0 | Create finding with Severity = Info. Assert Remediation_Due_Date__c = TODAY() + 90. |
| AUD-FLOW-018 | Due date not changed on update (only create) | Regression | P0 | Create finding (stamps due date). Update another field. Assert due date unchanged. |

#### Flow 7: Update_SLA_Status (Before Save on Audit_Finding__c, Create and Update)

| Test ID | Scenario | Category | Priority | Steps |
|---------|----------|----------|----------|-------|
| AUD-FLOW-019 | SLA = 'On Track' when due date is far future | Functional | P0 | Create finding with due date 30 days away. Assert SLA_Status__c = 'On Track'. |
| AUD-FLOW-020 | SLA = 'At Risk' when due date within 3 days | Functional | P0 | Create finding with Remediation_Due_Date = TODAY() + 2. Assert SLA_Status__c = 'At Risk'. |
| AUD-FLOW-021 | SLA = 'Breached' when past due | Functional | P0 | Create finding. Update Remediation_Due_Date to yesterday. Save. Assert SLA_Status = 'Breached'. |
| AUD-FLOW-022 | SLA cleared when Resolution_Status = 'Resolved' | Functional | P0 | Create breached finding. Set Resolution_Status = 'Resolved'. Assert SLA_Status__c is null/cleared. |

#### Flow 8: Access_Review_Attestation (Screen Flow)

| Test ID | Scenario | Category | Priority | Steps |
|---------|----------|----------|----------|-------|
| AUD-FLOW-023 | Screen flow deploys and activates without errors | Deployment | P0 | Verify flow is included in package and activates. |
| AUD-FLOW-024 | Manager can approve user access via flow screens | UAT | P1 | Initiate review, run screen flow, approve access. Assert Review_Status = 'Reviewed'. |
| AUD-FLOW-025 | Manager can flag user access for removal via flow | UAT | P1 | Run screen flow, flag access. Assert finding created. |

---

### 3.2 Batch->Queueable Chain Test Cases

The Audit product's most complex pattern is the execution chain: `UserAuditSnapshotBatch` -> `TerminationCrossCheckQueueable` -> `ProfileChangeDetectorQueueable`. ForceGuard must test this chain thoroughly.

| Test ID | Scenario | Category | Priority | Steps |
|---------|----------|----------|----------|-------|
| AUD-CHAIN-001 | Full chain completes successfully | Functional | P0 | Execute UserAuditSnapshotBatch. Assert: Audit_Run__c created, snapshots created, TerminationCrossCheckQueueable enqueued, ProfileChangeDetectorQueueable enqueued, run finalized as 'Completed'. |
| AUD-CHAIN-002 | Batch processes 2000+ users across multiple execute() calls | Bulk | P0 | Create 2000 test users. Execute batch with scope size 200. Assert: 10 execute() calls, 2000 snapshots created, no governor limits hit. |
| AUD-CHAIN-003 | SetupAuditTrailService called in finish() when feature enabled | Functional | P0 | Enable Setup_Audit_Trail feature. Run batch. Assert Setup_Change_Log__c records created. |
| AUD-CHAIN-004 | LoginHistoryService called in finish() when feature enabled | Functional | P0 | Enable Login_Anomaly_Detection feature. Run batch. Assert Login_Anomaly__c records created. |
| AUD-CHAIN-005 | SegregationOfDutiesService called in finish() when feature enabled | Functional | P0 | Enable Segregation_Of_Duties feature. Create users with toxic perm combos. Run batch. Assert SoD violation findings created. |
| AUD-CHAIN-006 | Features disabled -> corresponding checks skipped | Edge Case | P1 | Disable all features. Run batch. Assert no findings, no anomalies, no setup logs created. |
| AUD-CHAIN-007 | TerminationCrossCheckQueueable chains to ProfileChangeDetectorQueueable | Functional | P0 | Run batch. Assert: queueable chain completes, profile changes detected, run finalized. |
| AUD-CHAIN-008 | Error in TerminationCrossCheckQueueable does not prevent ProfileChangeDetector | Regression | P1 | Simulate error in cross-check (invalid data). Assert ProfileChangeDetectorQueueable still runs. |
| AUD-CHAIN-009 | QuarterlySignOffService blocks new run when unsigned | Functional | P0 | Enable Sign_Off_Enforcement. Create completed unsigned run. Attempt new run. Assert exception/error message. |
| AUD-CHAIN-010 | SnapshotDuplicateDetectionService prevents duplicate snapshots | Functional | P1 | Enable Snapshot_Duplicate_Detection. Run batch that would create duplicate user snapshots. Assert duplicates filtered. |

---

### 3.3 Finding Type Verification Scenarios

Each of the 14 finding types must be verified:

| Finding Type | Severity | Test ID | Scenario | Steps |
|-------------|----------|---------|----------|-------|
| Terminated User Active | Critical | AUD-FIND-001 | Terminated employee still active in Salesforce | Import termination CSV. Run cross-check. Assert finding created with severity=Critical and correct user email. |
| Profile Changed | Warning | AUD-FIND-002 | User's profile changed between runs | Run audit 1. Change user's profile. Run audit 2. Assert finding with old/new profile values. |
| Role Changed | Warning | AUD-FIND-003 | User's role changed between runs | Run audit 1. Change user's role. Run audit 2. Assert finding with old/new role values. |
| Permission Set Changed | Warning | AUD-FIND-004 | User's permission sets changed between runs | Run audit 1. Add/remove perm set. Run audit 2. Assert finding with old/new perm set values. |
| New User | Info | AUD-FIND-005 | New user detected since last run | Run audit 1. Create new user. Run audit 2. Assert "New User" finding for the new user. |
| Deactivated User | Info | AUD-FIND-006 | User deactivated triggers real-time finding | Deactivate user (set IsActive=false). Assert: UserDeactivationQueueable fired, finding created, on-demand run exists. |
| Privileged Access Granted | Warning | AUD-FIND-007 | System Admin or elevated perm set detected | Create user with System Administrator profile. Run audit. Assert privileged access finding created. |
| Overdue Access Review | Warning | AUD-FIND-008 | Pending review past due date | Initiate quarterly review. Set Next_Review_Due past date. Run processOverdueReviews. Assert finding created. |
| Segregation of Duties Violation | Critical | AUD-FIND-009 | User has toxic perm combo (e.g., Author Apex + Deploy) | Assign both conflicting perm sets to user. Run SoD validation. Assert Critical finding with rule details. |
| Unauthorized Deployment | Critical | AUD-FIND-010 | Deployment by unapproved deployer | Create setup change log with deployer not in Approved_Deployer__mdt. Run validation. Assert finding. |
| Deployment Without Change Ticket | Warning | AUD-FIND-011 | Deployment with no matching Change_Request__c | Create setup change log. No matching change request. Run CM validation. Assert finding. |
| Deployment Outside Window | Warning | AUD-FIND-012 | Deployment outside approved window | Create change request with narrow window. Create setup change outside window. Run validation. Assert finding. |
| Unauthorized Deployer | Critical | AUD-FIND-013 | Different person deployed than change ticket specifies | Create change request with Deployer = User A. Create setup change by User B. Run validation. Assert finding. |
| Access Flagged for Removal | Warning | AUD-FIND-014 | Access reviewer flags access for removal | Run quarterly review. Flag user access for removal. Assert finding created. |

---

### 3.4 Permission Set Security Test Cases

| Test ID | Permission Set | Object | Operation | Expected | Priority |
|---------|---------------|--------|-----------|----------|----------|
| AUD-PERM-001 | Audit_Administrator | Audit_Run__c | Create | Allowed | P0 |
| AUD-PERM-002 | Audit_Administrator | Audit_Run__c | Read | Allowed | P0 |
| AUD-PERM-003 | Audit_Administrator | Audit_Run__c | Update | Allowed | P0 |
| AUD-PERM-004 | Audit_Administrator | Audit_Run__c | Delete | Allowed | P0 |
| AUD-PERM-005 | Audit_Administrator | Audit_Finding__c | CRUD | All Allowed | P0 |
| AUD-PERM-006 | Audit_Administrator | All 7 objects | CRUD | All Allowed | P0 |
| AUD-PERM-007 | Audit_Administrator | Bypass_All_Flows | Custom Permission | Granted | P0 |
| AUD-PERM-008 | Audit_Full_Access | All 7 objects | CRUD | All Allowed | P0 |
| AUD-PERM-009 | Audit_Full_Access | Bypass_All_Flows | Custom Permission | NOT Granted | P0 |
| AUD-PERM-010 | Audit_Viewer | All 7 objects | Read | Allowed | P0 |
| AUD-PERM-011 | Audit_Viewer | All 7 objects | Create | Denied | P0 |
| AUD-PERM-012 | Audit_Viewer | All 7 objects | Update | Denied | P0 |
| AUD-PERM-013 | Audit_Viewer | All 7 objects | Delete | Denied | P0 |
| AUD-PERM-014 | Audit_Viewer | AuditController.runAuditNow | Invoke | Denied (insufficient access) | P0 |
| AUD-PERM-015 | No Permission Set | Any object | Any CRUD | Denied | P0 |
| AUD-PERM-016 | Audit_Viewer | AuditController.resolveFindings | Invoke | Denied (insufficient access) | P1 |

---

### 3.5 Feature Toggle Edge Case Tests

The 17 feature toggles control which audit checks run. ForceGuard must verify toggle behavior:

| Test ID | Toggle(s) | Scenario | Expected | Priority |
|---------|-----------|----------|----------|----------|
| AUD-TOGGLE-001 | User_Snapshot_Capture = false | Run batch with snapshots disabled | No snapshots created | P1 |
| AUD-TOGGLE-002 | Terminated_User_Detection = false | Import terminations, run cross-check | Cross-check skipped, no findings | P1 |
| AUD-TOGGLE-003 | Profile_Change_Detection = false | Profile changes between runs | Change detection skipped, no findings | P1 |
| AUD-TOGGLE-004 | Privileged_User_Monitoring = false | System Admin users exist | No privileged access findings created | P1 |
| AUD-TOGGLE-005 | Setup_Audit_Trail = false | Run batch | SetupAuditTrailService not called | P1 |
| AUD-TOGGLE-006 | Login_Anomaly_Detection = false | Run batch | LoginHistoryService not called | P1 |
| AUD-TOGGLE-007 | Segregation_Of_Duties = false | Users with toxic combos | SoD validation skipped | P1 |
| AUD-TOGGLE-008 | Access_Review_Workflow = false | Initiate review | Review workflow skipped | P1 |
| AUD-TOGGLE-009 | Quarterly_Sign_Off_Enforcement = false | Previous run not signed off | New run allowed (not blocked) | P1 |
| AUD-TOGGLE-010 | Snapshot_Duplicate_Detection = false | Duplicate snapshots | Duplicates NOT filtered | P2 |
| AUD-TOGGLE-011 | Unauthorized_Deployment = false | Unapproved deployer | Deployment auth check skipped | P1 |
| AUD-TOGGLE-012 | CM_Ticket_Validation = false | No change ticket | CM validation skipped | P1 |
| AUD-TOGGLE-013 | Finding_Assignment_SLA = false | Finding assigned | SLA calculation skipped | P2 |
| AUD-TOGGLE-014 | Overdue_Remediation_Reminders = false | Overdue findings | Reminder emails NOT sent | P2 |
| AUD-TOGGLE-015 | ALL toggles disabled | Run full batch | Minimal run: creates run + snapshots only, no findings | P1 |
| AUD-TOGGLE-016 | ALL toggles enabled (default) | Run full batch | Full run: all checks execute, all finding types possible | P0 |
| AUD-TOGGLE-017 | Toggle cache behavior | Toggle changed mid-transaction | Uses cached value from start of transaction (expected Apex behavior) | P2 |

---

### 3.6 MIXED_DML Pattern Test

| Test ID | Scenario | Category | Priority | Steps |
|---------|----------|----------|----------|-------|
| AUD-DML-001 | User deactivation uses async queueable to avoid MIXED_DML | Functional | P0 | Deactivate a User (IsActive=false). Assert: no MIXED_DML error thrown. Assert: UserDeactivationQueueable enqueued. Assert: on-demand Audit_Run__c created. Assert: snapshot and finding created. |
| AUD-DML-002 | Bypass_Jira_Ticket_Validation custom setting skips validation | Functional | P1 | Set Audit_Settings__c.Bypass_Jira_Ticket_Validation = true. Deactivate user without Jira ticket. Assert: no validation error. |
| AUD-DML-003 | On-demand audit run reused for same day | Regression | P1 | Deactivate User A (creates on-demand run). Deactivate User B same day. Assert: same Audit_Run__c used (identified by Notes = 'Real-Time Deactivation Detection'). |

---

### 3.7 Sample Sales Test Suite (Demonstrates Product-Agnostic Design)

This section shows how ForceGuard handles a completely different product - standard Salesforce Sales process. This is NOT built in Phase 4 (which is Audit-only) but demonstrates the reusability of the framework for future test suites.

**Test Suite:** Sales Process Regression
**Product_Name:** Sales Cloud (Standard)

#### Opportunity Lifecycle Tests

| Test ID | Scenario | Category | Priority | Steps |
|---------|----------|----------|----------|-------|
| SALES-OPP-001 | Create Opportunity with required fields | Functional | P0 | Create Account. Create Opportunity with Name, CloseDate, StageName='Prospecting', Amount. Assert: Opp created, Stage = Prospecting, Account linked. |
| SALES-OPP-002 | Stage progression through full sales cycle | Functional | P0 | Create Opp at Prospecting. Update Stage through: Qualification → Needs Analysis → Proposal → Negotiation → Closed Won. Assert: each stage transition succeeds, no validation errors. |
| SALES-OPP-003 | Closed Won requires Amount and CloseDate | Regression | P0 | Create Opp with no Amount. Attempt Stage = Closed Won. Assert: validation error fires. Set Amount, retry. Assert: succeeds. |
| SALES-OPP-004 | Closed Lost requires Loss Reason | Regression | P1 | Create Opp. Set Stage = Closed Lost without Loss_Reason__c. Assert: validation error. Add reason, retry. Assert: succeeds. |
| SALES-OPP-005 | Closed Opp cannot be reopened | Regression | P0 | Close-Win an Opp. Attempt to change Stage back to Prospecting. Assert: validation error or stage unchanged. |
| SALES-OPP-006 | Bulk create 200 Opportunities | Bulk | P1 | Insert 200 Opps in single DML. Assert: all 200 created, no governor limit errors. |

#### Products & Pricebook Tests

| Test ID | Scenario | Category | Priority | Steps |
|---------|----------|----------|----------|-------|
| SALES-PROD-001 | Add standard Pricebook entry for Product | Functional | P0 | Create Product2. Create PricebookEntry for standard Pricebook with UnitPrice. Assert: PBE active, linked to standard PB. |
| SALES-PROD-002 | Add custom Pricebook with Product | Functional | P0 | Create custom Pricebook2. Create PBE for custom PB. Assert: PBE linked to custom PB, UnitPrice set. |
| SALES-PROD-003 | Add Product to Opportunity via OpportunityLineItem | Functional | P0 | Create Opp. Add OpportunityLineItem with PricebookEntry, Quantity=1, UnitPrice. Assert: OLI created. Assert: Opp Amount updated (if rollup). Assert: Opp.HasOpportunityLineItem = true. |
| SALES-PROD-004 | Add multiple Products with different quantities | Functional | P1 | Create Opp. Add 3 OLIs with different products and quantities. Assert: all 3 linked, TotalPrice calculated correctly per line. |
| SALES-PROD-005 | Remove Product from Opportunity | Functional | P1 | Add OLI to Opp. Delete OLI. Assert: OLI removed, Opp.HasOpportunityLineItem = false (if last item). |
| SALES-PROD-006 | Deactivate Product prevents new OLI creation | Regression | P1 | Create Product, set IsActive=false. Attempt to create OLI. Assert: error or prevention. |

#### Contract & Trial Tests

| Test ID | Scenario | Category | Priority | Steps |
|---------|----------|----------|----------|-------|
| SALES-CON-001 | Create Contract from Closed Won Opp | Functional | P0 | Create Account. Close-Win Opp. Create Contract linked to Account with StartDate, ContractTerm=12, Status='Draft'. Assert: Contract created, linked to Account. |
| SALES-CON-002 | Activate Contract | Functional | P0 | Create Draft Contract. Set Status='Activated'. Assert: status updated, ActivatedDate stamped. |
| SALES-CON-003 | Contract end date calculated correctly | Functional | P0 | Create Contract with StartDate=TODAY, ContractTerm=12. Assert: EndDate = StartDate + 12 months. |
| SALES-CON-004 | Trial Opportunity with short contract term | Functional | P1 | Create Opp with Type='Trial'. Close-Win. Create Contract with ContractTerm=1 (trial month). Assert: Contract created with 1-month term. |
| SALES-CON-005 | Contract renewal reminder before expiry | Functional | P1 | Create Contract with EndDate 30 days from now. Run renewal check process. Assert: renewal task or notification created. |

#### Close-Win & Renewal Flow Tests

| Test ID | Scenario | Category | Priority | Steps |
|---------|----------|----------|----------|-------|
| SALES-WIN-001 | End-to-end: Opp → Close Win → Contract → Renewal Opp | Functional | P0 | Create Account. Create Opp with Products (Pricebook + OLI). Set Stage = Closed Won. Assert: Opp won. Create Contract. When Contract nears expiry, assert: Renewal Opportunity auto-created (if automation exists) OR verify manual renewal process works. |
| SALES-WIN-002 | Renewal Opp inherits Products from original | Functional | P0 | Close-Win Opp with 3 Products. Trigger renewal. Assert: Renewal Opp created with same 3 OLIs (same products, quantities, prices). |
| SALES-WIN-003 | Renewal Opp has correct CloseDate | Functional | P1 | Close-Win Opp. Trigger renewal. Assert: Renewal Opp CloseDate = Contract EndDate or configurable offset. |
| SALES-WIN-004 | Renewal Opp linked to parent Opp or Contract | Functional | P1 | Close-Win and create renewal. Assert: Renewal Opp has lookup to original Opp or Contract. |
| SALES-WIN-005 | Multiple renewals over time | Regression | P1 | Win Opp → Contract → Renewal 1 → Win Renewal 1 → Contract 2 → Renewal 2. Assert: full chain maintained, each renewal links correctly. |

#### Permission & Security Tests

| Test ID | Scenario | Category | Priority | Steps |
|---------|----------|----------|----------|-------|
| SALES-PERM-001 | Sales Rep can create and edit own Opportunities | Security | P0 | Run as Sales Rep profile. Create Opp. Edit Opp. Assert: both succeed. |
| SALES-PERM-002 | Sales Rep cannot delete Closed Won Opp | Security | P0 | Run as Sales Rep. Close-Win Opp. Attempt delete. Assert: denied. |
| SALES-PERM-003 | Sales Manager can view team's Opportunities | Security | P1 | Create Opp owned by Rep in Manager's role hierarchy. Run as Manager. Query Opp. Assert: visible. |
| SALES-PERM-004 | Read-only user cannot modify Opportunity fields | Security | P1 | Run as read-only profile. Attempt to update Opp Stage. Assert: insufficient access error. |

#### Edge Case & Validation Tests

| Test ID | Scenario | Category | Priority | Steps |
|---------|----------|----------|----------|-------|
| SALES-EDGE-001 | Opp with $0 Amount | Edge Case | P1 | Create Opp with Amount = 0. Close-Win. Assert: succeeds or validation rule fires (depending on org config). |
| SALES-EDGE-002 | Opp with CloseDate in the past | Edge Case | P1 | Create Opp with CloseDate = yesterday. Assert: validation rule prevents or allows (depending on config). |
| SALES-EDGE-003 | Delete Account cascades or blocks Opp deletion | Edge Case | P1 | Create Account with Opp. Attempt to delete Account. Assert: expected cascade/block behavior. |
| SALES-EDGE-004 | Currency conversion on multi-currency Opp | Edge Case | P2 | If multi-currency enabled: Create Opp in non-default currency. Assert: ConvertedAmount correct. |
| SALES-EDGE-005 | Opp Owner transfer updates team assignments | Edge Case | P1 | Transfer Opp to new owner. Assert: OpportunityTeamMember or sharing rules updated. |

**Total: 33 test cases** covering the full Sales lifecycle from Opp creation through renewal.

This demonstrates that ForceGuard's `Regression_Test_Case__c` records can capture ANY Salesforce business process - not just Audit. Each product simply gets its own Test Suite with scenarios tailored to its workflows.

---

## 4. Data Model

### 4.1 Confirmed Objects (6 objects from product vision)

The 6 custom objects from the product vision are confirmed as sufficient for the MVP. Here are refinements based on the Audit product analysis:

#### Regression_Test_Suite__c - CONFIRMED, with additions

| Field | Type | Addition? | Notes |
|-------|------|-----------|-------|
| Name | Standard | No | |
| Product_Name__c | Text(80) | No | |
| Version__c | Text(10) | No | |
| Target_Org__c | Text(100) | No | Org alias or username |
| Description__c | Long Text Area | No | |
| Is_Active__c | Checkbox | No | Default: true |
| Total_Test_Cases__c | Rollup Summary | No | Count of children |
| Last_Run_Date__c | DateTime | No | |
| Last_Run_Status__c | Picklist | No | Not Run/Passed/Failed/Running |
| **Source_Path__c** | **Text(255)** | **NEW** | Path to source directory (for deploy validation) |
| **Product_Namespace__c** | **Text(50)** | **NEW** | Namespace prefix for the product being tested |

**Rationale for additions:** Source_Path__c is needed for Layer 1 deployment validation to know where the product's source code lives. Product_Namespace__c helps identify which metadata belongs to the product vs. ForceGuard itself.

---

#### Regression_Test_Case__c - CONFIRMED, with additions

| Field | Type | Addition? | Notes |
|-------|------|-----------|-------|
| Name | Auto-Number (TC-{0000}) | No | |
| Test_Suite__c | Master-Detail | No | Parent suite |
| Title__c | Text(255) | No | |
| Description__c | Long Text Area | No | |
| Test_Layer__c | Picklist | No | Deployment/Apex Test/Data Scenario/Static Analysis |
| Category__c | Picklist | No | 8 categories |
| Perspective__c | Picklist | No | 5 perspectives |
| Priority__c | Picklist | No | P0/P1/P2 |
| Steps__c | Long Text Area(131072) | No | Apex script or component list |
| Expected_Result__c | Long Text Area | No | |
| Assertion_Type__c | Picklist | No | Record Exists/Field Value/Record Count/etc. |
| Is_Active__c | Checkbox | No | Default: true |
| Execution_Order__c | Number | No | Order within layer |
| **Target_Object__c** | **Text(100)** | **NEW** | sObject this test relates to (e.g., Audit_Run__c) |
| **Related_Metadata__c** | **Text(255)** | **NEW** | Specific metadata component tested (e.g., UserAuditSnapshotBatch) |
| **Tags__c** | **Long Text Area** | **NEW** | Semicolon-delimited tags for flexible grouping |
| **Last_Result_Status__c** | **Text(20)** | **NEW** | Cached status from most recent run (denormalized for quick filtering) |
| **Consecutive_Failures__c** | **Number** | **NEW** | Count of consecutive failures (for flaky test detection) |

**Rationale:** Target_Object__c and Related_Metadata__c enable the future Impact Analysis feature (mapping metadata changes to affected tests). Tags__c provides flexible grouping beyond the fixed picklists. Last_Result_Status__c avoids expensive joins when filtering test cases by recent status. Consecutive_Failures__c supports flaky test detection.

---

#### Regression_Test_Run__c - CONFIRMED, with additions

| Field | Type | Addition? | Notes |
|-------|------|-----------|-------|
| Name | Auto-Number (RUN-{0000}) | No | |
| Test_Suite__c | Lookup | No | |
| Run_Date__c | DateTime | No | |
| Completed_Date__c | DateTime | No | |
| Triggered_By__c | Picklist | No | Manual/Scheduled/CI CD/Pre-Deployment |
| Status__c | Picklist | No | Queued/Running/Completed/Failed/Cancelled |
| Total_Tests__c | Number | No | |
| Passed__c | Number | No | |
| Failed__c | Number | No | |
| Skipped__c | Number | No | |
| Duration_Seconds__c | Number | No | |
| Code_Coverage__c | Percent | No | |
| Run_By__c | Lookup(User) | No | |
| Pass_Rate__c | Formula | No | Passed / Total * 100 |
| **Regression_Count__c** | **Number** | **NEW** | Count of tests that regressed (previously passing, now failing) |
| **Layer_1_Status__c** | **Picklist** | **NEW** | Passed/Failed/Skipped - quick view of each layer |
| **Layer_2_Status__c** | **Picklist** | **NEW** | Passed/Failed/Skipped |
| **Layer_3_Status__c** | **Picklist** | **NEW** | Passed/Failed/Skipped |
| **Layer_4_Status__c** | **Picklist** | **NEW** | Passed/Failed/Skipped |
| **Batch_Job_Id__c** | **Text(18)** | **NEW** | AsyncApexJob ID for status polling from LWC |
| **Error_Summary__c** | **Long Text Area** | **NEW** | Quick summary of top failures for email/notifications |

**Rationale:** Per-layer status fields enable the dashboard to show layer-level results without querying child Result records. Regression_Count__c is a key metric for the dashboard. Batch_Job_Id__c enables the LWC to poll for job completion.

---

#### Regression_Test_Result__c - CONFIRMED, no additions needed

The original 11 fields are sufficient. The Is_Regression__c and Previous_Status__c fields handle regression detection.

---

#### Regression_Config__mdt - CONFIRMED, with additions

| Field | Type | Addition? | Notes |
|-------|------|-----------|-------|
| Coverage_Threshold__c | Number | No | Default: 85 |
| Org_Alias__c | Text(100) | No | |
| Auto_Ticket_Enabled__c | Checkbox | No | |
| Flaky_Threshold__c | Number | No | Default: 3 |
| Notification_Email__c | Email | No | |
| Schedule_Frequency__c | Picklist | No | |
| Enabled_Layers__c | Text(100) | No | "1;2;3;4" |
| Source_Path__c | Text(255) | No | |
| **Notification_Trigger__c** | **Picklist** | **NEW** | Always/Failures Only/Regressions Only |
| **Ticket_System_Named_Credential__c** | **Text(100)** | **NEW** | Named Credential for external ticketing |
| **Ticket_Project_Id__c** | **Text(50)** | **NEW** | Project ID in external ticket system |

---

#### Test_Coverage_Snapshot__c - CONFIRMED, no additions needed

The original 9 fields are sufficient.

---

### 4.2 No Additional Objects Needed

The 6 objects cover all requirements for the MVP. Future phases (Impact Analysis, Cross-Automation Conflict Detection) may require additional objects:
- `Metadata_Dependency__c` - for impact analysis mapping
- `Automation_Conflict__c` - for cross-automation detection

These will be added in Phase 2 of the product roadmap (Templatize phase), not in the current build.

---

## 5. LWC Component Specifications

### 5.1 regressionTestDashboard

**Purpose:** Main landing page showing overall testing health and quick actions.

**Wireframe Description:**

```
┌─────────────────────────────────────────────────────────────────────────┐
│ ForceGuard Dashboard                          [Run All] [Schedule] [?] │
├─────────────┬──────────────┬──────────────┬─────────────────────────────┤
│  Pass Rate  │ Total Tests  │   Failures   │  Automation Coverage        │
│    94%      │    156       │     3        │     67%                     │
│   +2% ▲     │ 12 suites    │  2 regress.  │  32/47 Automations         │
├─────────────┴──────────────┴──────────────┴─────────────────────────────┤
│                                                                         │
│  Pass Rate Trend (last 10 runs)                                        │
│  ▁▂▃▄▅▆▇█▇█                                                          │
│  88% ──────────────────── 94%                                          │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│ Recent Runs                                                    Filter ▼│
│┌────────┬─────────────┬───────────┬────────┬──┬──┬──┬─────┬──────────┐│
││ Run #  │ Suite       │ Date      │ Status │ P│ F│ S│ Dur │ Actions  ││
│├────────┼─────────────┼───────────┼────────┼──┼──┼──┼─────┼──────────┤│
││RUN-042 │ Audit (SOX) │ Feb 7     │ PASS   │38│ 0│ 2│13m  │ View     ││
││RUN-041 │ Contact Dup │ Feb 6     │ FAIL   │11│ 1│ 0│ 5m  │ View     ││
││RUN-040 │ Opp Assign  │ Feb 5     │ PASS   │22│ 0│ 0│ 8m  │ View     ││
│└────────┴─────────────┴───────────┴────────┴──┴──┴──┴─────┴──────────┘│
│                                                     [1] [2] [3] ►      │
└─────────────────────────────────────────────────────────────────────────┘
```

**Data Sources:**
- `RegressionDashboardController.getDashboardSummary()` - returns pass rate, total tests, failure count, coverage
- `RegressionDashboardController.getRecentRuns(20)` - returns last 20 runs
- `RegressionDashboardController.getTrendData(null)` - returns pass rates for trend chart (null = all suites)
- `RegressionDashboardController.runSuite(suiteId)` - triggers test execution
- `RegressionDashboardController.getBatchJobStatus(jobId)` - polls batch progress

**User Interactions:**
- **Run All button** - Opens confirmation modal ("Run all active suites?"), then calls runSuite for each active suite. Shows progress spinner with poll-based status updates.
- **Schedule button** - Opens modal with: frequency picklist (Daily/Weekly/Monthly), time picker, "Enable" toggle. Calls scheduler controller.
- **Suite filter dropdown** - Filters trend chart and recent runs by selected suite.
- **Run row click** - Navigates to testRunViewer filtered to that run.
- **View action** - Same as row click.
- **Trend chart hover** - Shows tooltip with run number, date, pass rate.

**SLDS Components:**
- `lightning-card` for summary cards
- `lightning-datatable` for recent runs table
- `lightning-badge` for status indicators
- `lightning-button-group` for action buttons
- `lightning-spinner` for loading states
- `lightning-modal` for schedule configuration (or `lightning-dialog` component)
- `lightning-icon` for trend arrows and status icons
- Custom SVG for sparkline chart (SLDS does not include chart components)

---

### 5.2 testSuiteManager

**Purpose:** CRUD interface for managing test suites and test cases.

**Wireframe Description:**

```
┌──────────────────────────────────────────────────────────────────────────┐
│ Test Suite Manager                              [+ New Suite] [Import]  │
├────────────────────┬─────────────────────────────────────────────────────┤
│ Suites             │ Test Cases for: Audit (SOX/IPE) v1.0              │
│                    │                                                     │
│ ● Audit (SOX/IPE)  │ Filter: [Layer ▼] [Category ▼] [Perspective ▼]    │
│   40 tests, PASS   │         [Priority ▼] [Active ▼] [Search...]       │
│                    │                                                     │
│ ○ Contact Dup Det  │ [+ New Test Case] [Bulk Activate] [Bulk Delete]   │
│   12 tests, FAIL   │                                                     │
│                    │ ┌─────┬────────────────────┬──────┬──────┬────┬──┐ │
│ ○ Opp Auto Assign  │ │ TC# │ Title              │Layer │Cat.  │Pri │✓ │ │
│   22 tests, PASS   │ ├─────┼────────────────────┼──────┼──────┼────┼──┤ │
│                    │ │ 001 │ Full audit run      │ L3   │ Func │ P0 │✓ │ │
│ [+ New Suite]      │ │ 002 │ Terminated detect   │ L3   │ Func │ P0 │✓ │ │
│                    │ │ 003 │ Profile change       │ L3   │ Func │ P0 │✓ │ │
│                    │ │ 004 │ Perm set security    │ L3   │ Sec  │ P0 │✓ │ │
│                    │ │ 005 │ 2000 user bulk      │ L3   │ Bulk │ P1 │✓ │ │
│                    │ └─────┴────────────────────┴──────┴──────┴────┴──┘ │
│                    │                                     [1] [2] ►      │
└────────────────────┴─────────────────────────────────────────────────────┘
```

**Data Sources:**
- `TestSuiteManagerController.getSuites()` - returns all suites with summary stats
- `TestSuiteManagerController.getTestCases(suiteId, filters)` - returns filtered test cases
- `TestSuiteManagerController.createSuite(suitData)` - creates new suite
- `TestSuiteManagerController.createTestCase(caseData)` - creates new test case
- `TestSuiteManagerController.updateTestCase(caseData)` - updates existing test case
- `TestSuiteManagerController.deleteTestCases(caseIds)` - bulk delete
- `TestSuiteManagerController.toggleActive(caseIds, isActive)` - bulk activate/deactivate

**User Interactions:**
- **Suite list click** - Loads test cases for that suite in the right panel.
- **New Suite button** - Opens modal: Name, Product Name, Version, Target Org, Description.
- **New Test Case button** - Opens 4-step wizard:
  1. General: Title, Description, Target Object, Related Metadata
  2. Classification: Layer (with description of each), Category, Perspective, Priority
  3. Test Definition: Steps (code editor textarea), Expected Result
  4. Review: Summary of all fields, Confirm button
- **Inline editing** - Double-click any cell to edit in-place.
- **Filter bar** - Multi-select picklist dropdowns for each dimension.
- **Bulk actions** - Checkbox column for multi-select, then Activate/Deactivate/Delete toolbar.
- **Import button** - Upload JSON/CSV of test case definitions.

**SLDS Components:**
- `lightning-layout` for two-panel design
- `lightning-tree` or custom list for suite navigation
- `lightning-datatable` for test case table (with inline editing enabled)
- `lightning-combobox` for filter dropdowns
- `lightning-modal` for creation wizard
- `lightning-progress-indicator` for wizard steps
- `lightning-textarea` for Steps__c with `font-family: monospace` styling
- `lightning-input` for search
- `lightning-checkbox-group` for bulk selection

---

### 5.3 testRunViewer

**Purpose:** History of all test runs with expandable per-layer detail.

**Wireframe Description:**

```
┌──────────────────────────────────────────────────────────────────────────┐
│ Test Run History                                                        │
│ Filter: [Suite ▼] [Status ▼] [Date Range ▼]              [Export All]  │
├──────────────────────────────────────────────────────────────────────────┤
│ ┌─ RUN-042  Audit (SOX/IPE)  Feb 7, 2026 2:00 PM  PASSED  13m 57s ──┐ │
│ │  ├ Layer 1: Deployment    ✓ PASS   5/5 passed    42s               │ │
│ │  ├ Layer 2: Apex Tests    ✓ PASS  18/18 passed   3m 12s  92% cov  │ │
│ │  ├ Layer 3: Data Scenar.  ✓ PASS  12/12 passed   8m 45s           │ │
│ │  └ Layer 4: Static Anal.  ✓ PASS   3/3 passed    1m 18s           │ │
│ │  Regressions: 0                                                     │ │
│ │  [Re-run All] [Re-run Failed] [View Details] [Export CSV] [PDF]    │ │
│ └────────────────────────────────────────────────────────────────────┘ │
│                                                                         │
│ ┌─ RUN-041  Contact Dup Det  Feb 6, 2026 9:15 AM  FAILED  5m 45s  ──┐ │
│ │  ├ Layer 1: Deployment    ✓ PASS   3/3 passed    38s               │ │
│ │  ├ Layer 2: Apex Tests    ✗ FAIL  11/12 passed   4m 02s  88% cov  │ │
│ │  ├ Layer 3: Data Scenar.  — SKIP   (blocked by Layer 2)            │ │
│ │  └ Layer 4: Static Anal.  ✓ PASS   2/2 passed    1m 05s           │ │
│ │  Regressions: 1  ⚠ NEW                                             │ │
│ │  [Re-run All] [Re-run Failed] [View Details] [Export CSV] [PDF]    │ │
│ └────────────────────────────────────────────────────────────────────┘ │
│                                                     [1] [2] [3] ►      │
└──────────────────────────────────────────────────────────────────────────┘
```

**Data Sources:**
- `TestRunViewerController.getTestRuns(suiteId, status, dateRange, page)` - paginated run list
- `TestRunViewerController.getRunDetail(runId)` - per-layer breakdown
- `TestRunViewerController.rerunFailed(runId)` - creates new run with failed tests only
- `TestRunViewerController.exportCsv(runId)` - returns CSV string

**User Interactions:**
- **Expand/collapse run** - Click run header to toggle detail view.
- **Layer row click** - Navigates to testResultDetail filtered to that layer.
- **Re-run All** - Re-executes the entire suite.
- **Re-run Failed** - Creates new run with only the tests that failed.
- **View Details** - Navigates to testResultDetail for full drill-down.
- **Export CSV** - Downloads CSV of all results for this run.
- **PDF** - Generates and downloads PDF report.
- **Filter** - By suite, status (Passed/Failed/All), date range.

**SLDS Components:**
- `lightning-accordion` or custom expandable sections for run cards
- `lightning-badge` for status (green PASS, red FAIL, gray SKIP)
- `lightning-icon` for layer status indicators
- `lightning-button-group` for action buttons
- `lightning-datatable` for layer detail view (inside expanded section)
- `lightning-combobox` for filters

---

### 5.4 testResultDetail

**Purpose:** Drill-down view showing individual test results with failure details.

**Wireframe Description:**

```
┌──────────────────────────────────────────────────────────────────────────┐
│ ← Back to Runs    RUN-041: Contact Dup Detection    Feb 6, 2026       │
│ Status: FAILED    Passed: 11/12    Duration: 5m 45s    Coverage: 88%   │
├──────────────────────────────────────────────────────────────────────────┤
│ ▼ Layer 1: Deployment Validation (3/3 PASSED - 38s)                    │
│   ┌────────────────────────────────────┬────────┬─────┐                │
│   │ Test Case                          │ Status │ Dur │                │
│   ├────────────────────────────────────┼────────┼─────┤                │
│   │ All Apex classes deploy            │ ✓ PASS │ 12s │                │
│   │ All LWC deploy                     │ ✓ PASS │ 14s │                │
│   │ All Flows activate                 │ ✓ PASS │ 12s │                │
│   └────────────────────────────────────┴────────┴─────┘                │
│                                                                         │
│ ▼ Layer 2: Apex Tests (11/12 PASSED - 4m 02s)     ⚠ 1 FAILURE         │
│   ┌────────────────────────────────────┬────────┬─────┬──────────────┐ │
│   │ Test Case                          │ Status │ Dur │ Actions      │ │
│   ├────────────────────────────────────┼────────┼─────┼──────────────┤ │
│   │ DuplicateDetectionServiceTest      │ ✓ PASS │ 45s │              │ │
│   │ ContactMergeHandlerTest            │ ✗ FAIL │ 28s │ [Expand]     │ │
│   │   ┌──────────────────────────────────────────────────────────┐   │ │
│   │   │ REGRESSION - Previously PASSED                           │   │ │
│   │   │                                                          │   │ │
│   │   │ Expected: Contact merged successfully with 2 duplicates  │   │ │
│   │   │ Actual:   System.DmlException: DUPLICATE_VALUE           │   │ │
│   │   │                                                          │   │ │
│   │   │ Error Message:                                           │   │ │
│   │   │ System.DmlException: Insert failed. First exception on   │   │ │
│   │   │ row 0; DUPLICATE_VALUE, duplicate value found:           │   │ │
│   │   │ Contact.Email__c duplicates value on record with id:     │   │ │
│   │   │ 003xx000001234                                           │   │ │
│   │   │                                                          │   │ │
│   │   │ ▶ Stack Trace (click to expand)                          │   │ │
│   │   │                                                          │   │ │
│   │   │ Related: ContactMergeHandler.cls, Contact_Merge_Flow     │   │ │
│   │   │                                                          │   │ │
│   │   │ [Mark Known Issue] [Re-run This Test] [Copy Error] [📋] │   │ │
│   │   └──────────────────────────────────────────────────────────┘   │ │
│   │ ContactSearchControllerTest        │ ✓ PASS │ 22s │              │ │
│   └────────────────────────────────────┴────────┴─────┴──────────────┘ │
│                                                                         │
│ ► Layer 3: Data Scenarios (SKIPPED - blocked by Layer 2)               │
│ ► Layer 4: Static Analysis (2/2 PASSED - 1m 05s)                      │
└──────────────────────────────────────────────────────────────────────────┘
```

**Data Sources:**
- `TestResultDetailController.getRunWithResults(runId)` - all results grouped by layer
- `TestResultDetailController.getResultDetail(resultId)` - single result with full error detail
- `TestResultDetailController.markKnownIssue(resultId, isKnown)` - toggles known issue flag
- `TestResultDetailController.rerunTest(testCaseId, suiteId)` - re-runs single test

**User Interactions:**
- **Back arrow** - Returns to testRunViewer.
- **Layer section expand/collapse** - Toggle visibility.
- **Failed test expand** - Shows error detail panel.
- **Mark Known Issue** - Toggles flag, dims the failure in the summary.
- **Re-run This Test** - Re-executes just this test case.
- **Copy Error** - Copies error message to clipboard.
- **Stack Trace expand** - Shows full stack trace in monospace block.
- **Related metadata links** - Click to navigate to the Apex class or Flow.

**SLDS Components:**
- `lightning-accordion` for layer sections
- `lightning-datatable` for test results within each layer
- `lightning-tile` for failure detail panel
- `lightning-formatted-text` for error messages (with `white-space: pre-wrap`)
- `lightning-button-icon` for copy-to-clipboard
- `lightning-badge` for REGRESSION indicator
- `lightning-icon` for pass/fail/skip status
- `lightning-breadcrumb` for navigation back to runs

---

## Summary

### Task Count by Phase

| Phase | Tasks | P0 | P1 | P2 | Effort |
|-------|-------|-----|-----|-----|--------|
| 1. Foundation | 4 | 3 | 1 | 0 | 3-5 days |
| 2. Data Model | 6 | 5 | 1 | 0 | 4-6 days |
| 3. Core Engine | 6 | 4 | 2 | 0 | 7-10 days |
| 4. Audit Scenarios | 7 | 4 | 2 | 1 | 6-8 days |
| 5. Lightning UI | 4 | 3 | 1 | 0 | 7-10 days |
| 6. Automation | 5 | 1 | 3 | 1 | 6-8 days |
| 7. Docs & Package | 6 | 3 | 2 | 1 | 5-7 days |
| **TOTAL** | **38** | **23** | **12** | **3** | **38-54 days** |

### Test Scenario Count

| Category | Count |
|----------|-------|
| Flow tests (8 Flows) | 25 |
| Batch/Queueable chain | 10 |
| Finding type verification (14 types) | 14 |
| Permission set security (3 sets) | 16 |
| Feature toggle edge cases (17 toggles) | 17 |
| MIXED_DML pattern | 3 |
| **TOTAL test scenarios** | **85** |

### Critical Path

```
Phase 1 (Foundation) ──► Phase 2 (Data Model) ──► Phase 3 (Core Engine)
                                                        │
                                                        ├──► Phase 4 (Audit Scenarios)
                                                        │
                                                        └──► Phase 5 (Lightning UI)
                                                                    │
                                                                    └──► Phase 6 (Automation)
                                                                              │
                                                                              └──► Phase 7 (Docs & Package)
```

Phases 4 and 5 can run in parallel after Phase 3 completes. Phase 6 depends on Phase 5 (for platform event subscription). Phase 7 depends on all other phases.
