# ForceGuard Coding Standards

Standards for developers building ForceGuard. Follow these without exception.

---

## No Flows Policy (IP Protection for Managed Packages)

**ForceGuard is a managed package. ForceGuard contains NO Flows. All automation is implemented in Apex.**

### Why?

Flows in managed packages are distributed as transparent XML metadata. Subscribers can view your entire automation logic, including:
- Business rules and validation criteria
- Formula calculations
- Decision trees and process flow
- Field mappings and transformations

Apex classes are compiled into bytecode before distribution. Subscribers cannot view your source code. For an AppExchange product, this is a critical IP protection strategy.

### Implementation Rules

| Automation Type | ❌ Avoid (Transparent) | ✅ Use Instead (Protected) |
|-----------------|------------------------|---------------------------|
| Record-triggered automation | Record-Triggered Flow | Apex Trigger + Handler Class |
| Scheduled automation | Scheduled Flow | Schedulable Apex |
| Screen-based UI | Screen Flow | Lightning Web Component |
| Reusable actions | Autolaunched Flow | @InvocableMethod Apex |
| Bulk processing | Flow Loop + DML | Batch Apex |

### Patterns

**Instead of Record-Triggered Flow:**
```apex
// Trigger (minimal logic)
trigger RegressionTestRunTrigger on Regression_Test_Run__c (after insert, after update) {
    RegressionTestRunHandler.handle(Trigger.new, Trigger.oldMap, Trigger.operationType);
}

// Handler (all business logic)
public with sharing class RegressionTestRunHandler {
    public static void handle(
        List<Regression_Test_Run__c> newRecords,
        Map<Id, Regression_Test_Run__c> oldMap,
        System.TriggerOperation operation
    ) {
        if (operation == System.TriggerOperation.AFTER_INSERT) {
            handleAfterInsert(newRecords);
        }
        // additional operations
    }

    private static void handleAfterInsert(List<Regression_Test_Run__c> runs) {
        // business logic here
    }
}
```

**Instead of Scheduled Flow:**
```apex
public class RegressionTestScheduler implements Schedulable {
    public void execute(SchedulableContext ctx) {
        // Launch batch or queueable
        Database.executeBatch(new RegressionTestRunner(), 10);
    }
}

// Schedule via Setup → Scheduled Jobs or Anonymous Apex:
// System.schedule('Daily Regression Tests', '0 0 2 * * ?', new RegressionTestScheduler());
```

**Instead of Screen Flow:**
```javascript
// Use LWC with imperative Apex calls
import { LightningElement } from 'lwc';
import runTests from '@salesforce/apex/RegressionTestController.runTests';

export default class TestSuiteManager extends LightningElement {
    async handleRunTests() {
        await runTests({ suiteId: this.selectedSuiteId });
    }
}
```

**For extensibility (invocable actions):**
```apex
// @InvocableMethod allows admins to call this from Process Builder or Flow
public class RegressionTestInvocable {
    @InvocableMethod(label='Run Regression Test Suite')
    public static void runSuite(List<RunRequest> requests) {
        for (RunRequest req : requests) {
            Database.executeBatch(new RegressionTestRunner(req.suiteId), 10);
        }
    }

    public class RunRequest {
        @InvocableVariable(required=true)
        public Id suiteId;
    }
}
```

### Exception

If a feature is declarative by nature (e.g., a "Test Builder" tool that generates flows), that's acceptable. The rule applies to **ForceGuard's core automation**, not to metadata that ForceGuard generates or tests.

---

## Naming Conventions

### Apex Classes

| Type | Convention | Example |
|------|-----------|---------|
| Core framework class | `RegressionTest` prefix | `RegressionTestRunner`, `RegressionTestExecutor` |
| Controller (LWC) | Descriptive + `Controller` | `RegressionDashboardController`, `TestSuiteManagerController` |
| Utility/Static helper | Descriptive name | `RegressionTestAssertion` |
| Test class | Same name + `_Test` | `RegressionTestRunner_Test` |
| Test data factory | `ForceGuardTestDataFactory` | Single shared factory |
| Batch class | Descriptive + `Batch` | `RegressionTestRunner` (implements Batchable) |
| Queueable class | Descriptive + `Queueable` | `RegressionTestNotifier` |
| Schedulable class | Descriptive + `Scheduler` | `RegressionTestScheduler` |

### Variables and Methods

| Type | Convention | Example |
|------|-----------|---------|
| Local variables | camelCase, descriptive | `testCasesByLayer`, `failedResultIds` |
| Method names | camelCase, verb-first | `executeLayer()`, `detectRegressions()` |
| Constants | UPPER_SNAKE_CASE | `MAX_BATCH_SIZE`, `DEFAULT_COVERAGE_THRESHOLD` |
| Boolean variables | `is`/`has`/`should` prefix | `isBlocking`, `hasRegressions`, `shouldSkipLayer` |
| Collections | Plural or descriptive suffix | `testCases`, `resultsByLayerMap`, `failedIdSet` |

### Custom Objects and Fields

| Type | Convention | Example |
|------|-----------|---------|
| Custom objects | `Regression_` prefix or product-specific | `Regression_Test_Suite__c` |
| Custom fields | Descriptive, underscores between words | `Test_Layer__c`, `Pass_Rate__c` |
| Custom metadata | Descriptive + `__mdt` | `Regression_Config__mdt` |
| Platform events | Product prefix + descriptive | `ForceGuard_Test_Complete__e` |

---

## Bulkification

All code must handle 200+ records in a single transaction. No exceptions.

### Required Patterns

**Collect, then act:**
```apex
// CORRECT - collect all records, single DML
List<Regression_Test_Result__c> results = new List<Regression_Test_Result__c>();
for (Regression_Test_Case__c tc : testCases) {
    results.add(new Regression_Test_Result__c(
        Test_Run__c = runId,
        Test_Case__c = tc.Id,
        Status__c = 'Passed'
    ));
}
insert results;
```

```apex
// WRONG - DML inside loop
for (Regression_Test_Case__c tc : testCases) {
    insert new Regression_Test_Result__c(
        Test_Run__c = runId,
        Test_Case__c = tc.Id,
        Status__c = 'Passed'
    );
}
```

**Pre-query related data:**
```apex
// CORRECT - query once, use map
Map<Id, Regression_Test_Case__c> caseMap = new Map<Id, Regression_Test_Case__c>(
    [SELECT Id, Title__c, Test_Layer__c FROM Regression_Test_Case__c
     WHERE Test_Suite__c = :suiteId]
);

for (Regression_Test_Result__c result : results) {
    Regression_Test_Case__c tc = caseMap.get(result.Test_Case__c);
    // use tc fields
}
```

---

## Single DML Pattern

Consolidate all DML operations. One insert, one update per object type per transaction where possible.

```apex
// CORRECT
List<Regression_Test_Result__c> toInsert = new List<Regression_Test_Result__c>();
List<Regression_Test_Case__c> toUpdate = new List<Regression_Test_Case__c>();

for (/* processing logic */) {
    toInsert.add(resultRecord);
    toUpdate.add(caseRecord);
}

insert toInsert;
update toUpdate;
```

Use `Database.insert(records, false)` when partial success is acceptable (e.g., bulk operations where individual failures should not roll back the entire batch).

---

## SOQL Best Practices

### No queries in loops

```apex
// WRONG
for (Regression_Test_Case__c tc : testCases) {
    List<Regression_Test_Result__c> results =
        [SELECT Id FROM Regression_Test_Result__c WHERE Test_Case__c = :tc.Id];
}

// CORRECT
List<Regression_Test_Result__c> allResults =
    [SELECT Id, Test_Case__c FROM Regression_Test_Result__c
     WHERE Test_Case__c IN :testCaseIds];
Map<Id, List<Regression_Test_Result__c>> resultsByCase = new Map<Id, List<Regression_Test_Result__c>>();
for (Regression_Test_Result__c r : allResults) {
    if (!resultsByCase.containsKey(r.Test_Case__c)) {
        resultsByCase.put(r.Test_Case__c, new List<Regression_Test_Result__c>());
    }
    resultsByCase.get(r.Test_Case__c).add(r);
}
```

### Use selective queries

- Always include a `WHERE` clause. Never query all records of an object.
- Use indexed fields in `WHERE` clauses (`Id`, `Name`, lookup fields, `CreatedDate`).
- Use `LIMIT` when you only need a subset.
- Use `WITH USER_MODE` in all controller queries for CRUD/FLS enforcement.

### Use AggregateResult for counts and sums

```apex
// CORRECT - let the database do the math
AggregateResult[] results = [
    SELECT Status__c, COUNT(Id) cnt
    FROM Regression_Test_Result__c
    WHERE Test_Run__c = :runId
    GROUP BY Status__c
];

// WRONG - query all records and count in Apex
List<Regression_Test_Result__c> allResults =
    [SELECT Status__c FROM Regression_Test_Result__c WHERE Test_Run__c = :runId];
Integer passCount = 0;
for (Regression_Test_Result__c r : allResults) {
    if (r.Status__c == 'Passed') passCount++;
}
```

---

## Error Handling

### Rules

1. **Never swallow exceptions.** Every `catch` block must either re-throw, log, or take corrective action.
2. **Use meaningful messages.** Include context: what operation failed, what record was involved, what the inputs were.
3. **@AuraEnabled methods must use try/catch with AuraHandledException.** Raw DML exceptions leak implementation details to the UI.

### Standard Pattern for Controllers

```apex
@AuraEnabled
public static RunSummary getDashboardSummary() {
    try {
        // business logic
        return summary;
    } catch (Exception e) {
        throw new AuraHandledException(
            'Failed to load dashboard: ' + e.getMessage()
        );
    }
}
```

### Standard Pattern for Batch/Queueable

```apex
public void execute(QueueableContext ctx) {
    try {
        // business logic
    } catch (Exception e) {
        // Log the error to the run record
        Regression_Test_Run__c run = new Regression_Test_Run__c(
            Id = this.runId,
            Status__c = 'Failed',
            Error_Summary__c = e.getMessage() + '\n' + e.getStackTraceString()
        );
        update run;
    }
}
```

### What NOT to do

```apex
// WRONG - swallowed exception
try {
    insert results;
} catch (Exception e) {
    // do nothing
}

// WRONG - generic message
throw new AuraHandledException('Error');

// WRONG - exposing internal details to UI
throw new AuraHandledException(e.getStackTraceString());
```

---

## Governor Limit Awareness

### Monitor limits in batch jobs

```apex
public void execute(Database.BatchableContext bc, List<SObject> scope) {
    // Check remaining limits before expensive operations
    if (Limits.getCallouts() >= Limits.getLimitCallouts() - 5) {
        // Log and stop - do not try to push through
        return;
    }

    // Process scope
}
```

### Key limits to track

| Limit | Value | Where It Matters |
|-------|-------|-----------------|
| SOQL queries | 100 (sync) / 200 (async) | Executor, Reporter |
| DML statements | 150 | Runner (creating results) |
| Callouts | 100 | Executor (Tooling API calls) |
| Heap size | 6MB (sync) / 12MB (async) | Large result sets, CSV export |
| CPU time | 10s (sync) / 60s (async) | Data scenario execution |

### Batch size recommendations

- Default batch size: 200 (Salesforce standard).
- For callout-heavy operations: batch size 10-50 (to stay under callout limit).
- For CPU-heavy operations: batch size 50-100.
- Set batch size in the `Database.executeBatch()` call, not hardcoded in the class.

---

## Test Class Requirements

### Coverage

- **Minimum: 90% per class.** Not 90% overall -- 90% on every individual class.
- If a class drops below 90%, the PR is blocked.

### Required test scenarios per class

| Scenario Type | What It Covers |
|---------------|---------------|
| **Positive** | Happy path -- valid inputs, expected outcomes |
| **Negative** | Invalid inputs, missing data, null values |
| **Bulk** | 200+ records in a single transaction |
| **Permission** | `System.runAs()` with different permission sets |
| **Edge case** | Empty collections, boundary values, first-ever run |

### Test data factory

All tests use `ForceGuardTestDataFactory` for consistent data creation. Never create test data inline in test methods if the same data structure is needed in multiple tests.

```apex
@IsTest
public class ForceGuardTestDataFactory {

    public static Regression_Test_Suite__c createSuite(String productName) {
        Regression_Test_Suite__c suite = new Regression_Test_Suite__c(
            Name = productName + ' Test Suite',
            Product_Name__c = productName,
            Version__c = '1.0',
            Is_Active__c = true
        );
        insert suite;
        return suite;
    }

    public static List<Regression_Test_Case__c> createTestCases(
        Id suiteId, Integer count, String layer
    ) {
        List<Regression_Test_Case__c> cases = new List<Regression_Test_Case__c>();
        for (Integer i = 0; i < count; i++) {
            cases.add(new Regression_Test_Case__c(
                Test_Suite__c = suiteId,
                Title__c = layer + ' Test Case ' + i,
                Test_Layer__c = layer,
                Category__c = 'Functional',
                Priority__c = 'P1',
                Steps__c = '// test steps',
                Expected_Result__c = 'Pass',
                Assertion_Type__c = 'No Error',
                Is_Active__c = true,
                Execution_Order__c = i
            ));
        }
        insert cases;
        return cases;
    }
}
```

### Assertion standards

- Every `System.assert` must have a meaningful message parameter.
- Never use `System.assert(true)` or `System.assert(false)` without context.
- Prefer `System.assertEquals` / `System.assertNotEquals` over `System.assert` with boolean expressions.

```apex
// CORRECT
System.assertEquals(
    'Completed', run.Status__c,
    'Run should be Completed after all layers pass'
);

// WRONG
System.assert(run.Status__c == 'Completed');
```

### Mock callouts

All Tooling API callouts must be mocked in tests using `HttpCalloutMock`.

```apex
@IsTest
private class RegressionTestExecutor_Test {

    private class ToolingApiMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"success": true}');
            return res;
        }
    }

    @IsTest
    static void testLayerTwoExecution() {
        Test.setMock(HttpCalloutMock.class, new ToolingApiMock());
        // test logic
    }
}
```

---

## Code Review Checklist

Before submitting any PR, verify:

- [ ] **No SOQL in loops.** Every query is outside of for/while/do-while blocks.
- [ ] **No DML in loops.** All insert/update/delete/upsert calls are outside loops.
- [ ] **No hardcoded IDs.** No 15 or 18-character Salesforce IDs in code.
- [ ] **Bulk safe.** Code handles 200+ records without governor limit errors.
- [ ] **Single DML.** DML operations are consolidated (one insert per object type).
- [ ] **CRUD/FLS enforced.** All controller queries use `WITH USER_MODE` or `Security.stripInaccessible()`.
- [ ] **AuraHandledException.** All `@AuraEnabled` methods wrap errors in `AuraHandledException`.
- [ ] **No swallowed exceptions.** Every `catch` block takes action.
- [ ] **Test coverage >= 90%.** Run `sf apex run test` and verify per-class coverage.
- [ ] **Tests have assertions.** No test methods that only insert data without verifying outcomes.
- [ ] **Meaningful assertion messages.** Every `System.assert*` call includes a descriptive third parameter.
- [ ] **Callout mocks.** All HTTP callouts are mocked in tests.
- [ ] **Naming follows conventions.** Classes, methods, and variables follow the naming rules above.
- [ ] **No debug logs left in.** Remove `System.debug()` calls used during development. Intentional logging for production monitoring is fine.
