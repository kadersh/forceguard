/**
 * RegressionTestAssertion - Static utility class providing 7 assertion methods
 * for ForceGuard data scenario testing. All methods return AssertionResult
 * which can be consumed by RegressionTestExecutor or directly by LWC.
 *
 * Assertion types:
 *   1. assertEquals      - Type-safe equality comparison
 *   2. assertNotNull     - Null check
 *   3. assertRecordExists - Dynamic SOQL existence check
 *   4. assertRecordCount  - Dynamic SOQL count comparison
 *   5. assertFieldValue   - Query record field and compare
 *   6. assertCoverage     - Code coverage threshold check
 *   7. assertNoGovernorViolation - Governor limit failure detection
 */
public with sharing class RegressionTestAssertion {

    /**
     * Structured assertion result with @AuraEnabled for LWC consumption.
     */
    public class AssertionResult {
        @AuraEnabled public Boolean passed;
        @AuraEnabled public String message;
        @AuraEnabled public String expected;
        @AuraEnabled public String actual;

        public AssertionResult(Boolean passed, String message, String expected, String actual) {
            this.passed = passed;
            this.message = message;
            this.expected = expected;
            this.actual = actual;
        }
    }

    /**
     * 1. Type-safe equality check.
     * Handles null-safe comparison using Object.equals().
     * @param expected The expected value
     * @param actual   The actual value
     * @param message  Description of what is being asserted
     * @return AssertionResult with pass/fail and formatted message
     */
    public static AssertionResult assertEquals(Object expected, Object actual, String message) {
        Boolean passed = (expected == null && actual == null)
            || (expected != null && expected.equals(actual));
        String expectedStr = String.valueOf(expected);
        String actualStr = String.valueOf(actual);

        return new AssertionResult(
            passed,
            passed
                ? message + ': PASSED'
                : message + ': Expected [' + expectedStr + '] but got [' + actualStr + ']',
            expectedStr,
            actualStr
        );
    }

    /**
     * 2. Not-null check.
     * @param value   The value to check
     * @param message Description of what is being asserted
     * @return AssertionResult indicating whether value is non-null
     */
    public static AssertionResult assertNotNull(Object value, String message) {
        Boolean passed = value != null;
        return new AssertionResult(
            passed,
            passed ? message + ': PASSED' : message + ': Value was null',
            'Not null',
            value == null ? 'null' : String.valueOf(value)
        );
    }

    /**
     * 3. Record existence check using dynamic SOQL COUNT().
     * @param sObjectType The API name of the sObject (e.g. 'Account', 'My_Object__c')
     * @param whereClause Optional WHERE clause (without the WHERE keyword)
     * @return AssertionResult indicating whether at least 1 record exists
     */
    public static AssertionResult assertRecordExists(String sObjectType, String whereClause) {
        if (String.isBlank(sObjectType)) {
            return new AssertionResult(false, 'sObjectType is required', 'A valid sObject name', 'blank');
        }

        String query = 'SELECT COUNT() FROM ' + String.escapeSingleQuotes(sObjectType);
        if (String.isNotBlank(whereClause)) {
            query += ' WHERE ' + whereClause;
        }

        Integer count = Database.countQuery(query);
        Boolean passed = count > 0;

        return new AssertionResult(
            passed,
            passed
                ? sObjectType + ' record exists: PASSED'
                : 'No ' + sObjectType + ' records found matching criteria',
            'At least 1 record',
            String.valueOf(count) + ' records'
        );
    }

    /**
     * 4. Record count check using dynamic SOQL COUNT().
     * @param sObjectType   The API name of the sObject
     * @param whereClause   Optional WHERE clause (without the WHERE keyword)
     * @param expectedCount The exact count expected
     * @return AssertionResult indicating whether count matches exactly
     */
    public static AssertionResult assertRecordCount(String sObjectType, String whereClause, Integer expectedCount) {
        if (String.isBlank(sObjectType)) {
            return new AssertionResult(false, 'sObjectType is required', String.valueOf(expectedCount), 'blank');
        }

        String query = 'SELECT COUNT() FROM ' + String.escapeSingleQuotes(sObjectType);
        if (String.isNotBlank(whereClause)) {
            query += ' WHERE ' + whereClause;
        }

        Integer actualCount = Database.countQuery(query);
        Boolean passed = actualCount == expectedCount;

        return new AssertionResult(
            passed,
            passed
                ? sObjectType + ' count matches: PASSED'
                : sObjectType + ' count mismatch',
            String.valueOf(expectedCount),
            String.valueOf(actualCount)
        );
    }

    /**
     * 5. Field value check - queries a specific record and compares a field value.
     * Uses bind variable for recordId (SOQL-injection safe).
     * @param recordId     The record to query
     * @param objectType   The sObject API name
     * @param fieldName    The field API name to check
     * @param expectedValue The expected value (compared as string)
     * @return AssertionResult with field comparison result
     */
    public static AssertionResult assertFieldValue(Id recordId, String objectType, String fieldName, Object expectedValue) {
        if (recordId == null) {
            return new AssertionResult(false, 'Record ID is required', String.valueOf(expectedValue), 'null ID');
        }
        if (String.isBlank(objectType) || String.isBlank(fieldName)) {
            return new AssertionResult(false, 'objectType and fieldName are required',
                String.valueOf(expectedValue), 'missing parameters');
        }

        String safeFieldName = String.escapeSingleQuotes(fieldName);
        String safeObjectType = String.escapeSingleQuotes(objectType);
        String query = 'SELECT ' + safeFieldName + ' FROM ' + safeObjectType + ' WHERE Id = :recordId WITH USER_MODE';

        List<SObject> records = Database.query(query);
        if (records.isEmpty()) {
            return new AssertionResult(
                false,
                'Record not found: ' + recordId,
                String.valueOf(expectedValue),
                'Record not found'
            );
        }

        Object actualValue = records[0].get(fieldName);
        String expectedStr = String.valueOf(expectedValue);
        String actualStr = String.valueOf(actualValue);

        // Compare as strings for cross-type compatibility
        Boolean passed = (expectedValue == null && actualValue == null)
            || (expectedStr != null && expectedStr.equals(actualStr));

        return new AssertionResult(
            passed,
            passed
                ? fieldName + ' value matches: PASSED'
                : fieldName + ' value mismatch',
            expectedStr,
            actualStr
        );
    }

    /**
     * 6. Code coverage threshold check.
     * Accepts coverage percentage as parameter (fetched by caller via Tooling API).
     * @param className       The Apex class name being checked
     * @param actualCoverage  The actual coverage percentage (e.g. 85.5 for 85.5%)
     * @param minPercent      The minimum acceptable coverage percentage (e.g. 75 for 75%)
     * @return AssertionResult indicating whether coverage meets threshold
     */
    public static AssertionResult assertCoverage(String className, Decimal actualCoverage, Decimal minPercent) {
        if (String.isBlank(className)) {
            return new AssertionResult(false, 'className is required',
                (minPercent != null ? minPercent.setScale(1) : 0) + '%', 'blank');
        }
        if (minPercent == null) {
            minPercent = 75;
        }
        if (actualCoverage == null) {
            return new AssertionResult(
                false,
                'No coverage data for ' + className,
                minPercent.setScale(1) + '%',
                'No data'
            );
        }

        Boolean passed = actualCoverage >= minPercent;

        return new AssertionResult(
            passed,
            passed
                ? className + ' coverage meets threshold: PASSED'
                : className + ' coverage below threshold',
            minPercent.setScale(1) + '%',
            actualCoverage.setScale(1) + '%'
        );
    }

    /**
     * 7. Governor limit violation detection.
     * Checks the most recent ApexTestResult records for the given test class,
     * looking for failures with "limit" in the message (governor limit errors).
     * @param testClassName The test class name to check
     * @return AssertionResult indicating whether any governor violations were found
     */
    public static AssertionResult assertNoGovernorViolation(String testClassName) {
        if (String.isBlank(testClassName)) {
            return new AssertionResult(false, 'testClassName is required', '0 violations', 'blank');
        }

        List<ApexTestResult> failedResults = [
            SELECT Outcome, Message
            FROM ApexTestResult
            WHERE ApexClass.Name = :testClassName
              AND Outcome = 'Fail'
              AND Message LIKE '%limit%'
            WITH USER_MODE
            ORDER BY TestTimestamp DESC
            LIMIT 10
        ];

        Boolean passed = failedResults.isEmpty();

        return new AssertionResult(
            passed,
            passed
                ? testClassName + ' no governor violations: PASSED'
                : testClassName + ' has governor limit violations',
            '0 violations',
            String.valueOf(failedResults.size()) + ' violations'
        );
    }
}
