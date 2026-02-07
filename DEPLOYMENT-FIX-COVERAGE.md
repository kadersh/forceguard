# Deployment Fix: Coverage Assertion Refactoring

## Problem
`RegressionTestAssertion.cls` was attempting to query `ApexCodeCoverageAggregate` using standard SOQL, but this object is only accessible via the Tooling API. This caused compilation failure.

## Root Cause
Lines 199-204 in `RegressionTestAssertion.cls`:
```apex
List<ApexCodeCoverageAggregate> coverages = [
    SELECT ApexClassOrTrigger.Name, NumLinesCovered, NumLinesUncovered
    FROM ApexCodeCoverageAggregate
    WHERE ApexClassOrTrigger.Name = :className
    WITH USER_MODE
];
```

**Error**: `ApexCodeCoverageAggregate` is not available in standard SOQL - it requires Tooling API callouts.

## Solution
Refactored `assertCoverage` method to accept coverage percentage as a parameter instead of querying it:

**Before**:
```apex
public static AssertionResult assertCoverage(String className, Decimal minPercent)
```

**After**:
```apex
public static AssertionResult assertCoverage(String className, Decimal actualCoverage, Decimal minPercent)
```

The coverage data will be fetched by the caller via Tooling API (to be implemented in a future phase).

## Files Changed

### 1. RegressionTestAssertion.cls
- **Lines 183-229**: Refactored `assertCoverage` method
- Removed SOQL query to `ApexCodeCoverageAggregate`
- Added `actualCoverage` parameter (Decimal)
- Method now compares the provided coverage against the threshold

### 2. RegressionTestAssertionTest.cls
- **Line 272**: Updated `testAssertCoverage` - pass `null` for coverage
- **Line 289**: Updated `testAssertCoverageBlankClassName` - pass `80.0` for coverage
- **Line 395**: Updated `testAssertCoverageNullMinPercent` - pass `null` for coverage
- **Lines 403-443**: Added two new tests:
  - `testAssertCoveragePassesThreshold` - verifies 85% passes 75% threshold
  - `testAssertCoverageFailsThreshold` - verifies 60% fails 75% threshold

### 3. RegressionTestExecutor.cls
- **Lines 412-419**: Updated `Coverage Threshold` case in `executeAssertion`
- Added `actualCoverage = null` with TODO comment
- Updated call to `assertCoverage` with 3 parameters
- Added comment: "For MVP, coverage data is null until Tooling API integration is built"

## MVP Status
For MVP, the `Coverage Threshold` assertion type will always fail when executed because:
1. `actualCoverage` is passed as `null`
2. `assertCoverage` returns failure when `actualCoverage == null`
3. Error message: "No coverage data for [ClassName]"

This is **expected behavior** for MVP. Coverage checking will be implemented in a future phase via Tooling API callouts.

## Testing
All test methods updated to match the new signature:
- Tests pass `null` to simulate no coverage data
- Tests pass explicit coverage percentages (85.0, 60.0, 80.0) to test threshold logic
- All tests continue to verify expected failure messages and pass/fail states

## Next Steps (Future Phase)
1. Implement Tooling API callout in `RegressionTestExecutor`
2. Query `ApexCodeCoverageAggregate` via Tooling API
3. Calculate coverage percentage: `(NumLinesCovered / (NumLinesCovered + NumLinesUncovered)) * 100`
4. Pass calculated percentage to `assertCoverage` method
5. Update tests to use mock Tooling API responses

## Deployment Readiness
✅ All compilation errors resolved
✅ No references to `ApexCodeCoverageAggregate` in standard SOQL
✅ All test methods updated
✅ Code follows CRUD/FLS standards (WITH USER_MODE retained where applicable)
✅ No breaking changes to existing functionality (only affects Coverage Threshold assertion)
