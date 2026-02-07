# ForceGuard Testing Guide

A practical reference for creating test suites and test cases in ForceGuard.

---

## The 4-Layer Testing Model

ForceGuard tests Salesforce products through 4 sequential layers. Blocking layers halt the pipeline on failure.

```
Layer 1: Deployment Validation  [BLOCKING]     ~30-60s
Layer 2: Apex Test Execution    [BLOCKING]     ~2-5m
Layer 3: Data Scenario Testing  [VERIFICATION] ~5-15m
Layer 4: Static Analysis        [QUALITY GATE] ~1-2m
```

**Why sequential?** There is no point running expensive data scenario tests if the code does not compile. Layer 1 catches broken metadata. Layer 2 catches broken logic. Layer 3 catches broken business rules. Layer 4 catches code quality issues.

If Layer 1 fails, Layers 2-4 are skipped. If Layer 2 fails, Layer 3 is skipped. Layer 4 always runs (advisory only).

---

## Creating a Test Suite

A Test Suite (`Regression_Test_Suite__c`) groups test cases for a single product or functional area.

| Field | Purpose | Example |
|-------|---------|---------|
| Name | Display name | "User Access Audit v1.0" |
| Product_Name__c | Product being tested | "User Access Audit" |
| Version__c | Product version | "1.0" |
| Target_Org__c | Org alias or username | "my-sandbox" |
| Description__c | What this suite covers | "Full regression suite for the Audit product..." |
| Is_Active__c | Whether the suite runs on schedule | true |
| Source_Path__c | Path to product source (for Layer 1) | "force-app/main/default" |
| Product_Namespace__c | Namespace prefix of the product | "audit" |

**Tips:**
- One suite per product or major functional area.
- Keep suites focused. A 200-test suite is harder to maintain than four 50-test suites.
- Set `Is_Active__c = false` to temporarily disable a suite without deleting its test cases.

---

## Creating a Test Case

A Test Case (`Regression_Test_Case__c`) defines a single test that ForceGuard executes and evaluates.

### Required Fields

| Field | Purpose | Values |
|-------|---------|--------|
| Test_Suite__c | Parent suite (Master-Detail) | Lookup to suite |
| Title__c | Short description of what is tested | "Closed Won Opp requires Amount" |
| Test_Layer__c | Which layer executes this test | Deployment / Apex Test / Data Scenario / Static Analysis |
| Category__c | Type of test | See categories below |
| Priority__c | Execution priority | P0 / P1 / P2 |
| Steps__c | The executable content | Apex script, class names, or component list |
| Expected_Result__c | What a passing test looks like | "All 35 Apex classes deploy without errors" |
| Assertion_Type__c | How to evaluate the result | Record Exists / Field Value / Record Count / Coverage Threshold / No Error / Custom Script |

### Optional Fields

| Field | Purpose |
|-------|---------|
| Description__c | Detailed explanation of what this test covers and why |
| Perspective__c | Stakeholder viewpoint (Developer / Admin / Product Manager / Designer / Client) |
| Is_Active__c | Enable/disable without deleting (default: true) |
| Execution_Order__c | Controls order within a layer (lower numbers run first) |
| Target_Object__c | The sObject this test relates to (e.g., `Audit_Run__c`) |
| Related_Metadata__c | Specific metadata component tested (e.g., `UserAuditSnapshotBatch`) |
| Tags__c | Semicolon-delimited tags for flexible grouping |

---

## Layer Details

### Layer 1: Deployment Validation

**Purpose:** Verify that all metadata components compile and deploy without errors.

**When to use:** Every suite should have at least one Layer 1 test. If the product's code does not deploy, nothing else matters.

**Steps__c contains:** A list of metadata components to validate (Apex classes, Flows, LWC, objects).

**Example:**

```
Title:       All Audit Apex classes compile and deploy
Layer:       Deployment
Category:    Deployment
Priority:    P0
Steps:       UserAuditSnapshotBatch, AuditController, AuditControlCenterController,
             ProfileChangeDetector, TerminationCrossCheckService, LoginHistoryService,
             SegregationOfDutiesService, AuditReportService, AuditFeatureService
Expected:    All components deploy without errors
Assertion:   No Error
```

### Layer 2: Apex Test Execution

**Purpose:** Run existing Apex test classes and verify they pass with sufficient code coverage.

**When to use:** When the product has Apex test classes you want ForceGuard to execute and monitor.

**Steps__c contains:** Apex test class names to execute.

**Example:**

```
Title:       Core batch and service tests pass
Layer:       Apex Test
Category:    Functional
Priority:    P0
Steps:       UserAuditSnapshotBatchTest, AuditControllerTest,
             AuditControlCenterControllerTest
Expected:    All tests pass. Code coverage >= 85%.
Assertion:   Coverage Threshold
```

### Layer 3: Data Scenario Testing

**Purpose:** Execute real business scenarios by creating data, triggering automations, and verifying outcomes.

**When to use:** When you need to test end-to-end business logic that goes beyond unit tests. This is where ForceGuard delivers the most value.

**Steps__c contains:** Anonymous Apex that sets up data, triggers the action, and runs assertions.

**Example:**

```
Title:       Critical finding gets 7-day remediation due date
Layer:       Data Scenario
Category:    Functional
Priority:    P0
Steps:
  // Setup
  Audit_Run__c run = new Audit_Run__c(Status__c = 'Running');
  insert run;

  // Action
  Audit_Finding__c finding = new Audit_Finding__c(
      Audit_Run__c = run.Id,
      Severity__c = 'Critical',
      Finding_Type__c = 'Terminated User Active'
  );
  insert finding;

  // Verify
  finding = [SELECT Remediation_Due_Date__c FROM Audit_Finding__c WHERE Id = :finding.Id];
  System.assertEquals(Date.today().addDays(7), finding.Remediation_Due_Date__c,
      'Critical finding should get 7-day due date');

Expected:    Remediation_Due_Date__c = TODAY + 7 days
Assertion:   Field Value
```

### Layer 4: Static Analysis

**Purpose:** Analyze source code for quality issues like SOQL in loops, hardcoded IDs, and missing CRUD checks.

**When to use:** When you want to enforce code quality standards as part of the regression pipeline.

**Steps__c contains:** Class names to analyze and the pattern to check for.

**Example:**

```
Title:       No SOQL queries inside loops in service classes
Layer:       Static Analysis
Category:    Deployment
Priority:    P1
Steps:       AuditController, AuditReportService, ProfileChangeDetector,
             TerminationCrossCheckService | PATTERN: SOQL_IN_LOOP
Expected:    0 violations found
Assertion:   Record Count
```

---

## Test Categories

| Category | When to Use | Example |
|----------|-------------|---------|
| **Deployment** | Verifying metadata compiles and deploys | "All Apex classes deploy" |
| **Functional** | Testing happy-path business logic | "Finding gets correct due date" |
| **Edge Case** | Boundary conditions and unusual inputs | "User with no Profile" |
| **Bulk/Performance** | High-volume data operations (200+ records) | "Snapshot 2000 users" |
| **Security/Permission** | CRUD, FLS, permission set verification | "Viewer cannot delete findings" |
| **Integration** | Cross-system or API interactions | "External ticket creation" |
| **Regression** | Previously broken scenarios that must stay fixed | "Closed Opp cannot reopen" |
| **UAT** | End-user acceptance scenarios | "Manager approves access review" |

---

## Stakeholder Perspectives

Perspectives answer the question: "Who cares if this test fails?"

| Perspective | Focus | Example Test |
|-------------|-------|--------------|
| **Developer** | Code compiles, tests pass, no governor limits | "Batch processes 2000 records without limits" |
| **Admin** | Configurations work, Flows fire correctly | "SLA status updates on save" |
| **Product Manager** | Business requirements are met | "Full audit lifecycle completes" |
| **Designer** | UI renders correctly, user experience works | "Dashboard loads with no errors" |
| **Client** | The product does what was promised | "Terminated users are detected within 24h" |

---

## Assertion Types

| Type | What It Checks | Use When |
|------|---------------|----------|
| **Record Exists** | At least 1 record matches a SOQL query | Verifying a record was created |
| **Field Value** | A specific field equals an expected value | Checking a formula, Flow update, or trigger |
| **Record Count** | Exact number of records match a query | Verifying bulk operations or rollups |
| **Coverage Threshold** | Code coverage >= a percentage | Layer 2 coverage checks |
| **No Error** | Execution completes without exceptions | Deployment validation, smoke tests |
| **Custom Script** | Custom assertion logic in Steps__c | Complex multi-step verification |

---

## Best Practices

**Writing maintainable tests:**

1. **One test, one thing.** Each test case should verify a single behavior. "Create finding and verify due date" is good. "Create finding, verify due date, check SLA, send email, and generate PDF" is five tests crammed into one.

2. **Clear titles.** Someone reading the test case title should immediately understand what it tests. Bad: "Test 1". Good: "Critical finding gets 7-day remediation due date".

3. **Precise expected results.** "It works" is not an expected result. "Remediation_Due_Date__c = TODAY + 7 days" is.

4. **Set execution order.** Within a layer, use `Execution_Order__c` to control which tests run first. Put fast smoke tests early, expensive bulk tests last.

5. **Use tags for grouping.** Tags__c supports semicolon-delimited values like `"SOX;quarterly;critical-path"` for filtering beyond the fixed picklists.

6. **Keep Steps__c self-contained.** Each Layer 3 test should create its own data, execute the action, and verify the result. Do not rely on data from other test cases.

7. **Test the negative.** For every "it should work" test, consider a "it should fail gracefully" counterpart. What happens with null input? Missing permissions? Empty collections?

8. **Tag related metadata.** Fill in `Target_Object__c` and `Related_Metadata__c` so future impact analysis can map metadata changes to affected tests.

---

## Common Patterns

### Pattern: Testing a Flow fires correctly

```
// Setup - create the record that triggers the Flow
Account acc = new Account(Name = 'Test');
insert acc;
Opportunity opp = new Opportunity(
    AccountId = acc.Id,
    Name = 'Test Opp',
    StageName = 'Prospecting',
    CloseDate = Date.today().addDays(30)
);
insert opp;

// Action - perform the update that fires the Flow
opp.StageName = 'Closed Won';
opp.Amount = 10000;
update opp;

// Verify - check the Flow's expected outcome
opp = [SELECT Is_Won__c FROM Opportunity WHERE Id = :opp.Id];
System.assertEquals(true, opp.Is_Won__c, 'Flow should set Is_Won flag');
```

### Pattern: Testing permission enforcement

```
// Setup - create a test user with specific permissions
Profile p = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce'];
User testUser = new User(
    ProfileId = p.Id,
    // ... required user fields
);
insert testUser;
PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'Audit_Viewer'];
insert new PermissionSetAssignment(AssigneeId = testUser.Id, PermissionSetId = ps.Id);

// Action + Verify - run as the restricted user
System.runAs(testUser) {
    try {
        insert new Audit_Finding__c(/* fields */);
        System.assert(false, 'Viewer should not be able to create findings');
    } catch (DmlException e) {
        System.assert(e.getMessage().contains('insufficient access'),
            'Should get access error, got: ' + e.getMessage());
    }
}
```

### Pattern: Testing bulk operations

```
// Setup - create 200+ records
List<Audit_Finding__c> findings = new List<Audit_Finding__c>();
for (Integer i = 0; i < 200; i++) {
    findings.add(new Audit_Finding__c(
        Audit_Run__c = runId,
        Severity__c = 'Warning',
        Finding_Type__c = 'Profile Changed'
    ));
}

// Action
insert findings;

// Verify - all records processed correctly
List<Audit_Finding__c> inserted = [
    SELECT Remediation_Due_Date__c
    FROM Audit_Finding__c
    WHERE Audit_Run__c = :runId
];
System.assertEquals(200, inserted.size(), 'All 200 findings should be created');
for (Audit_Finding__c f : inserted) {
    System.assertNotEquals(null, f.Remediation_Due_Date__c,
        'Each finding should have a due date set by the Flow');
}
```
