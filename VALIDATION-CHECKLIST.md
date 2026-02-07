# Validation Checklist: Coverage Assertion Fix

## Files Modified
- ✅ `RegressionTestAssertion.cls` - Refactored `assertCoverage` method
- ✅ `RegressionTestAssertionTest.cls` - Updated 3 tests, added 2 new tests
- ✅ `RegressionTestExecutor.cls` - Updated call to `assertCoverage`
- ✅ `RegressionTestExecutorTest.cls` - No changes needed (doesn't test coverage path)

## Pre-Deployment Checks

### Compilation
- [ ] All classes compile without errors
- [ ] No references to `ApexCodeCoverageAggregate` in standard SOQL
- [ ] All method signatures match at call sites

### Code Quality
- [x] `with sharing` declared on all classes
- [x] `WITH USER_MODE` used on all SOQL queries (where applicable)
- [x] No SOQL in loops
- [x] No DML in loops
- [x] Null-safe handling (actualCoverage can be null)

### Test Coverage
- [x] `testAssertCoverage` - Tests null coverage (no data scenario)
- [x] `testAssertCoverageBlankClassName` - Tests blank class name validation
- [x] `testAssertCoverageNullMinPercent` - Tests null minPercent default to 75
- [x] `testAssertCoveragePassesThreshold` - NEW: Tests 85% passes 75% threshold
- [x] `testAssertCoverageFailsThreshold` - NEW: Tests 60% fails 75% threshold

### Functionality
- [x] Method returns failure when `actualCoverage == null` (MVP behavior)
- [x] Method returns pass when `actualCoverage >= minPercent`
- [x] Method returns fail when `actualCoverage < minPercent`
- [x] Method defaults `minPercent` to 75 if null
- [x] Method validates `className` is not blank

## Deployment Command

```bash
sf project deploy start \
  -d force-app/main/default/classes/RegressionTestAssertion.cls \
  -d force-app/main/default/classes/RegressionTestAssertion.cls-meta.xml \
  -d force-app/main/default/classes/RegressionTestAssertionTest.cls \
  -d force-app/main/default/classes/RegressionTestAssertionTest.cls-meta.xml \
  -d force-app/main/default/classes/RegressionTestExecutor.cls \
  -d force-app/main/default/classes/RegressionTestExecutor.cls-meta.xml \
  -o "org-alias"
```

Or deploy entire classes directory:

```bash
sf project deploy start \
  -d force-app/main/default/classes \
  -o "org-alias"
```

## Post-Deployment Validation

1. **Run All Tests**
   ```bash
   sf apex run test \
     -n RegressionTestAssertionTest \
     -o "org-alias" \
     -r human \
     -c
   ```

2. **Expected Results**
   - ✅ All tests pass
   - ✅ Code coverage > 85%
   - ✅ No compilation errors
   - ✅ No warnings

3. **Manual Verification**
   - Create a test case with `Assertion_Type__c = 'Coverage Threshold'`
   - Execute via `RegressionTestExecutor.executeLayer()`
   - Verify result shows "No coverage data" (expected MVP behavior)

## Known Limitations (MVP)
- Coverage Threshold assertions will always fail in MVP because:
  - `actualCoverage` is hardcoded to `null`
  - Tooling API integration not yet implemented
  - Error message: "No coverage data for [ClassName]"

This is **expected behavior** and documented in the architecture plan.

## Future Enhancement
Phase 2 will implement:
1. HTTP Callout to Tooling API endpoint: `/services/data/vXX.0/tooling/query?q=SELECT+ApexClassOrTrigger.Name,NumLinesCovered,NumLinesUncovered+FROM+ApexCodeCoverageAggregate+WHERE+ApexClassOrTrigger.Name='ClassName'`
2. Parse JSON response
3. Calculate coverage percentage
4. Pass to `assertCoverage` method
5. Coverage assertions will then work as designed
