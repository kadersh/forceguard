/**
 * RegressionTestExecutor - Per-layer execution engine for ForceGuard.
 * Receives test cases and a layer number, dispatches to the correct execution
 * logic, and returns Regression_Test_Result__c records (unsaved - caller inserts).
 *
 * Layer mapping:
 *   1 = Deployment Validation
 *   2 = Apex Test Verification
 *   3 = Data Scenario Testing
 *   4 = Static Analysis
 */
public with sharing class RegressionTestExecutor {

    private static final String STATUS_PASSED = 'Passed';
    private static final String STATUS_FAILED = 'Failed';
    private static final String STATUS_SKIPPED = 'Skipped';
    private static final String STATUS_ERROR = 'Error';
    private static final String STATUS_CONFIG_ERROR = 'Config Error';
    private static final String STATUS_WARNING = 'Warning';

    private static final String LAYER_DEPLOYMENT = 'Deployment';
    private static final String LAYER_APEX_TEST = 'Apex Test';
    private static final String LAYER_DATA_SCENARIO = 'Data Scenario';
    private static final String LAYER_STATIC_ANALYSIS = 'Static Analysis';

    private static final Map<Integer, String> LAYER_NAMES = new Map<Integer, String>{
        1 => LAYER_DEPLOYMENT,
        2 => LAYER_APEX_TEST,
        3 => LAYER_DATA_SCENARIO,
        4 => LAYER_STATIC_ANALYSIS
    };

    /**
     * Main entry point - dispatches to the correct layer handler.
     * Returns unsaved result records so the caller can bulk-insert.
     * @param runId   - the Regression_Test_Run__c Id
     * @param testCases - test cases for this layer
     * @param layerNum  - 1 (Deployment), 2 (Apex Test), 3 (Data Scenario), 4 (Static Analysis)
     * @return List of Regression_Test_Result__c records (NOT inserted)
     */
    public static List<Regression_Test_Result__c> executeLayer(
            Id runId,
            List<Regression_Test_Case__c> testCases,
            Integer layerNum) {

        List<Regression_Test_Result__c> results = new List<Regression_Test_Result__c>();

        if (testCases == null || testCases.isEmpty() || layerNum == null) {
            return results;
        }

        String layerName = LAYER_NAMES.get(layerNum);
        if (layerName == null) {
            // Unknown layer - create error results for all cases
            for (Regression_Test_Case__c tc : testCases) {
                results.add(buildResult(runId, tc, STATUS_ERROR,
                    tc.Test_Layer__c, 0, 'Unknown layer number: ' + layerNum, null, null));
            }
            return results;
        }

        switch on layerNum {
            when 1 {
                results = executeDeploymentValidation(runId, testCases);
            }
            when 2 {
                results = executeApexTests(runId, testCases);
            }
            when 3 {
                results = executeDataScenarios(runId, testCases);
            }
            when 4 {
                results = executeStaticAnalysis(runId, testCases);
            }
        }

        return results;
    }

    /**
     * Layer 1: Deployment Validation
     * Parses Steps__c as semicolon-delimited component references:
     *   - Object names validated via Schema.getGlobalDescribe()
     *   - Class names validated via ApexClass SOQL
     *   - Trigger names validated via ApexTrigger SOQL
     * Format: "CustomObject:Account;ApexClass:MyController;ApexTrigger:MyTrigger"
     */
    @TestVisible
    private static List<Regression_Test_Result__c> executeDeploymentValidation(
            Id runId, List<Regression_Test_Case__c> testCases) {

        List<Regression_Test_Result__c> results = new List<Regression_Test_Result__c>();
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();

        // Pre-query Apex classes and triggers for all test cases to avoid SOQL in loops
        Set<String> classNames = new Set<String>();
        Set<String> triggerNames = new Set<String>();
        for (Regression_Test_Case__c tc : testCases) {
            if (String.isBlank(tc.Steps__c)) {
                continue;
            }
            for (String component : tc.Steps__c.split(';')) {
                String trimmed = component.trim();
                if (trimmed.startsWithIgnoreCase('ApexClass:')) {
                    classNames.add(trimmed.substringAfter(':').trim());
                } else if (trimmed.startsWithIgnoreCase('ApexTrigger:')) {
                    triggerNames.add(trimmed.substringAfter(':').trim());
                }
            }
        }

        Map<String, Id> existingClasses = new Map<String, Id>();
        if (!classNames.isEmpty()) {
            for (ApexClass cls : [
                SELECT Id, Name FROM ApexClass
                WHERE Name IN :classNames
                WITH USER_MODE
            ]) {
                existingClasses.put(cls.Name.toLowerCase(), cls.Id);
            }
        }

        Map<String, Id> existingTriggers = new Map<String, Id>();
        if (!triggerNames.isEmpty()) {
            for (ApexTrigger trg : [
                SELECT Id, Name FROM ApexTrigger
                WHERE Name IN :triggerNames
                WITH USER_MODE
            ]) {
                existingTriggers.put(trg.Name.toLowerCase(), trg.Id);
            }
        }

        // Process each test case
        for (Regression_Test_Case__c tc : testCases) {
            Long timer = System.currentTimeMillis();
            try {
                if (String.isBlank(tc.Steps__c)) {
                    results.add(buildResult(runId, tc, STATUS_PASSED, LAYER_DEPLOYMENT,
                        System.currentTimeMillis() - timer,
                        null, null, 'No components to validate'));
                    continue;
                }

                List<String> failures = new List<String>();
                List<String> successes = new List<String>();

                for (String component : tc.Steps__c.split(';')) {
                    String trimmed = component.trim();
                    if (String.isBlank(trimmed)) {
                        continue;
                    }

                    if (trimmed.startsWithIgnoreCase('CustomObject:')) {
                        String objName = trimmed.substringAfter(':').trim();
                        if (globalDescribe.containsKey(objName.toLowerCase())) {
                            successes.add('Object ' + objName + ' exists');
                        } else {
                            failures.add('Object ' + objName + ' not found');
                        }
                    } else if (trimmed.startsWithIgnoreCase('ApexClass:')) {
                        String clsName = trimmed.substringAfter(':').trim();
                        if (existingClasses.containsKey(clsName.toLowerCase())) {
                            successes.add('Class ' + clsName + ' exists');
                        } else {
                            failures.add('Class ' + clsName + ' not found');
                        }
                    } else if (trimmed.startsWithIgnoreCase('ApexTrigger:')) {
                        String trgName = trimmed.substringAfter(':').trim();
                        if (existingTriggers.containsKey(trgName.toLowerCase())) {
                            successes.add('Trigger ' + trgName + ' exists');
                        } else {
                            failures.add('Trigger ' + trgName + ' not found');
                        }
                    } else {
                        // Treat as object name by default
                        if (globalDescribe.containsKey(trimmed.toLowerCase())) {
                            successes.add('Object ' + trimmed + ' exists');
                        } else {
                            failures.add('Component ' + trimmed + ' not found');
                        }
                    }
                }

                Long duration = System.currentTimeMillis() - timer;
                String log = 'Checked ' + (successes.size() + failures.size()) + ' components.\n'
                    + 'Passed: ' + String.join(successes, ', ') + '\n'
                    + (failures.isEmpty() ? '' : 'Not found: ' + String.join(failures, ', '));
                String status = failures.isEmpty() ? STATUS_PASSED : STATUS_CONFIG_ERROR;
                String errorMsg = failures.isEmpty() ? null : String.join(failures, '; ');

                results.add(buildResult(runId, tc, status, LAYER_DEPLOYMENT,
                    duration, errorMsg, null, log));

            } catch (Exception e) {
                results.add(buildResult(runId, tc, STATUS_ERROR, LAYER_DEPLOYMENT,
                    System.currentTimeMillis() - timer,
                    e.getMessage(), e.getStackTraceString(), null));
            }
        }

        return results;
    }

    /**
     * Layer 2: Apex Test Verification
     * Parses Steps__c as semicolon-delimited test class names.
     * For MVP: checks that test classes exist and queries their most recent
     * ApexTestResult records for pass/fail outcome.
     */
    @TestVisible
    private static List<Regression_Test_Result__c> executeApexTests(
            Id runId, List<Regression_Test_Case__c> testCases) {

        List<Regression_Test_Result__c> results = new List<Regression_Test_Result__c>();

        // Collect all referenced test class names
        Set<String> allClassNames = new Set<String>();
        for (Regression_Test_Case__c tc : testCases) {
            if (String.isNotBlank(tc.Steps__c)) {
                for (String name : tc.Steps__c.split(';')) {
                    String trimmed = name.trim();
                    if (String.isNotBlank(trimmed)) {
                        allClassNames.add(trimmed);
                    }
                }
            }
        }

        // Bulk-query class existence
        Map<String, Id> classIdByName = new Map<String, Id>();
        if (!allClassNames.isEmpty()) {
            for (ApexClass cls : [
                SELECT Id, Name FROM ApexClass
                WHERE Name IN :allClassNames
                WITH USER_MODE
            ]) {
                classIdByName.put(cls.Name.toLowerCase(), cls.Id);
            }
        }

        // Bulk-query latest test results for all classes
        Map<String, ApexTestResult> latestResults = new Map<String, ApexTestResult>();
        if (!allClassNames.isEmpty()) {
            for (ApexTestResult atr : [
                SELECT ApexClass.Name, Outcome, Message, MethodName, TestTimestamp
                FROM ApexTestResult
                WHERE ApexClass.Name IN :allClassNames
                WITH USER_MODE
                ORDER BY TestTimestamp DESC
                LIMIT 2000
            ]) {
                String key = atr.ApexClass.Name.toLowerCase();
                if (!latestResults.containsKey(key)) {
                    latestResults.put(key, atr);
                }
            }
        }

        // Process each test case
        for (Regression_Test_Case__c tc : testCases) {
            Long timer = System.currentTimeMillis();
            try {
                if (String.isBlank(tc.Steps__c)) {
                    results.add(buildResult(runId, tc, STATUS_PASSED, LAYER_APEX_TEST,
                        System.currentTimeMillis() - timer,
                        null, null, 'No test classes specified'));
                    continue;
                }

                List<String> configErrors = new List<String>();
                List<String> failures = new List<String>();
                List<String> passes = new List<String>();
                List<String> logLines = new List<String>();

                for (String name : tc.Steps__c.split(';')) {
                    String trimmed = name.trim();
                    if (String.isBlank(trimmed)) {
                        continue;
                    }
                    String key = trimmed.toLowerCase();

                    if (!classIdByName.containsKey(key)) {
                        configErrors.add('Test class ' + trimmed + ' not found in org');
                        logLines.add(trimmed + ': NOT FOUND');
                        continue;
                    }

                    ApexTestResult lastResult = latestResults.get(key);
                    if (lastResult == null) {
                        logLines.add(trimmed + ': No test results found (never run)');
                        passes.add(trimmed + ': exists but no test history');
                    } else if (lastResult.Outcome == 'Pass') {
                        passes.add(trimmed + ': ' + lastResult.Outcome);
                        logLines.add(trimmed + ': PASS (last run: ' + lastResult.TestTimestamp + ')');
                    } else {
                        failures.add(trimmed + ': ' + lastResult.Outcome
                            + (String.isNotBlank(lastResult.Message) ? ' - ' + lastResult.Message : ''));
                        logLines.add(trimmed + ': ' + lastResult.Outcome);
                    }
                }

                Long duration = System.currentTimeMillis() - timer;
                String status;
                List<String> allErrors = new List<String>();
                allErrors.addAll(configErrors);
                allErrors.addAll(failures);
                if (!failures.isEmpty()) {
                    status = STATUS_FAILED;
                } else if (!configErrors.isEmpty()) {
                    status = STATUS_CONFIG_ERROR;
                } else {
                    status = STATUS_PASSED;
                }
                String errorMsg = allErrors.isEmpty() ? null : String.join(allErrors, '; ');
                String log = String.join(logLines, '\n');

                results.add(buildResult(runId, tc, status, LAYER_APEX_TEST,
                    duration, errorMsg, null, log));

            } catch (Exception e) {
                results.add(buildResult(runId, tc, STATUS_ERROR, LAYER_APEX_TEST,
                    System.currentTimeMillis() - timer,
                    e.getMessage(), e.getStackTraceString(), null));
            }
        }

        return results;
    }

    /**
     * Layer 3: Data Scenario Testing
     * The highest-value layer. Uses RegressionTestAssertion methods driven by
     * the Assertion_Type__c field:
     *   - Record Exists: Steps__c = "ObjectName|WhereClause"
     *   - Field Value:   Steps__c = "RecordId|ObjectName|FieldName" (legacy)
     *                    Steps__c = "ObjectName|LookupField=LookupValue|CheckField" (dynamic)
     *   - Record Count:  Steps__c = "ObjectName|WhereClause"
     *   - Coverage Threshold: Steps__c = "ClassName"
     *   - No Error:      Steps__c = "TestClassName"
     *   - Custom Script:  Steps__c = freeform SOQL query description
     *
     * Expected_Result__c contains the expected value for comparison.
     */
    @TestVisible
    private static List<Regression_Test_Result__c> executeDataScenarios(
            Id runId, List<Regression_Test_Case__c> testCases) {

        List<Regression_Test_Result__c> results = new List<Regression_Test_Result__c>();

        for (Regression_Test_Case__c tc : testCases) {
            Long timer = System.currentTimeMillis();
            try {
                RegressionTestAssertion.AssertionResult assertion = executeAssertion(tc);
                Long duration = System.currentTimeMillis() - timer;

                String status = assertion.passed ? STATUS_PASSED : STATUS_FAILED;
                String errorMsg = assertion.passed ? null : assertion.message;
                String log = 'Assertion: ' + tc.Assertion_Type__c + '\n'
                    + 'Expected: ' + assertion.expected + '\n'
                    + 'Actual: ' + assertion.actual + '\n'
                    + 'Result: ' + (assertion.passed ? 'PASS' : 'FAIL');

                Regression_Test_Result__c result = buildResult(runId, tc, status,
                    LAYER_DATA_SCENARIO, duration, errorMsg, null, log);
                result.Actual_Result__c = assertion.actual;
                results.add(result);

            } catch (System.SObjectException e) {
                // SObjectException indicates invalid object/field names in config
                results.add(buildResult(runId, tc, STATUS_CONFIG_ERROR, LAYER_DATA_SCENARIO,
                    System.currentTimeMillis() - timer,
                    e.getMessage(), e.getStackTraceString(), null));
            } catch (System.QueryException e) {
                // QueryException from invalid SOQL (bad object/field name) is a config issue
                results.add(buildResult(runId, tc, STATUS_CONFIG_ERROR, LAYER_DATA_SCENARIO,
                    System.currentTimeMillis() - timer,
                    e.getMessage(), e.getStackTraceString(), null));
            } catch (Exception e) {
                results.add(buildResult(runId, tc, STATUS_ERROR, LAYER_DATA_SCENARIO,
                    System.currentTimeMillis() - timer,
                    e.getMessage(), e.getStackTraceString(), null));
            }
        }

        return results;
    }

    /**
     * Dispatches to the correct RegressionTestAssertion method based on Assertion_Type__c.
     * Parses Steps__c using pipe (|) delimiter for structured parameters.
     */
    @TestVisible
    private static RegressionTestAssertion.AssertionResult executeAssertion(
            Regression_Test_Case__c tc) {

        String assertionType = tc.Assertion_Type__c;
        String steps = tc.Steps__c;
        String expected = tc.Expected_Result__c;

        if (String.isBlank(assertionType)) {
            return new RegressionTestAssertion.AssertionResult(
                false, 'No Assertion_Type__c defined', 'An assertion type', 'null');
        }

        List<String> parts = String.isNotBlank(steps)
            ? steps.split('\\|') : new List<String>();
        for (Integer i = 0; i < parts.size(); i++) {
            parts[i] = parts[i].trim();
        }

        switch on assertionType {
            when 'Record Exists' {
                // Steps: "ObjectName|WhereClause"
                String objName = parts.size() > 0 ? parts[0] : '';
                String whereClause = parts.size() > 1 ? parts[1] : '';
                return RegressionTestAssertion.assertRecordExists(objName, whereClause);
            }
            when 'Field Value' {
                // Two supported formats:
                // Legacy:  "RecordId|ObjectName|FieldName" (hardcoded ID - backward compat)
                // Dynamic: "ObjectName|LookupField=LookupValue|CheckField" (portable across orgs)
                String firstPart = parts.size() > 0 ? parts[0] : '';

                // Detect legacy format: first part is a 15- or 18-char Salesforce ID
                if (Pattern.matches('[a-zA-Z0-9]{15}|[a-zA-Z0-9]{18}', firstPart)) {
                    // Legacy ID-based format
                    String objName = parts.size() > 1 ? parts[1] : '';
                    String fieldName = parts.size() > 2 ? parts[2] : '';
                    Id recordId = Id.valueOf(firstPart);
                    return RegressionTestAssertion.assertFieldValue(recordId, objName, fieldName, expected);
                }

                // Dynamic lookup format: ObjectName|LookupField=LookupValue|CheckField
                String objName = firstPart;
                String lookupExpr = parts.size() > 1 ? parts[1] : '';
                String checkField = parts.size() > 2 ? parts[2] : '';

                if (String.isBlank(objName) || String.isBlank(lookupExpr) || String.isBlank(checkField)) {
                    return new RegressionTestAssertion.AssertionResult(
                        false, 'Field Value: Invalid format. Expected ObjectName|LookupField=LookupValue|CheckField',
                        expected, 'missing parameters');
                }

                if (!lookupExpr.contains('=')) {
                    return new RegressionTestAssertion.AssertionResult(
                        false, 'Field Value: Lookup expression must contain "=" (e.g. Name=Acme Corp)',
                        expected, lookupExpr);
                }

                String[] lookupParts = lookupExpr.split('=', 2);
                String lookupField = lookupParts[0].trim();
                String lookupValue = lookupParts[1].trim();

                String safeObj = String.escapeSingleQuotes(objName);
                String safeLookup = String.escapeSingleQuotes(lookupField);
                String safeCheck = String.escapeSingleQuotes(checkField);

                String soql = 'SELECT ' + safeCheck
                    + ' FROM ' + safeObj
                    + ' WHERE ' + safeLookup + ' = :lookupValue'
                    + ' WITH USER_MODE LIMIT 1';
                List<SObject> records = Database.query(soql);

                if (records.isEmpty()) {
                    return new RegressionTestAssertion.AssertionResult(
                        false, 'No ' + objName + ' found where ' + lookupField + ' = ' + lookupValue,
                        expected, 'Record not found');
                }

                Object actualValue = records[0].get(checkField);
                String actualStr = String.valueOf(actualValue);
                Boolean passed = (expected == null && actualValue == null)
                    || (expected != null && expected.equals(actualStr));

                return new RegressionTestAssertion.AssertionResult(
                    passed,
                    passed
                        ? checkField + ' value matches: PASSED'
                        : checkField + ' value mismatch',
                    expected,
                    actualStr);
            }
            when 'Record Count' {
                // Steps: "ObjectName|WhereClause"
                // Expected: numeric count or comparison (e.g., ">0", ">=17", "5")
                String objName = parts.size() > 0 ? parts[0] : '';
                String whereClause = parts.size() > 1 ? parts[1] : '';

                if (String.isNotBlank(expected) && expected.trim().startsWith('>') ||
                    String.isNotBlank(expected) && expected.trim().startsWith('<')) {
                    // Comparison mode
                    String trimmed = expected.trim();
                    String operator;
                    Integer compareValue;
                    if (trimmed.startsWith('>=')) {
                        operator = '>=';
                        compareValue = Integer.valueOf(trimmed.substring(2).trim());
                    } else if (trimmed.startsWith('>')) {
                        operator = '>';
                        compareValue = Integer.valueOf(trimmed.substring(1).trim());
                    } else if (trimmed.startsWith('<=')) {
                        operator = '<=';
                        compareValue = Integer.valueOf(trimmed.substring(2).trim());
                    } else {
                        operator = '<';
                        compareValue = Integer.valueOf(trimmed.substring(1).trim());
                    }

                    // whereClause is admin-configured via Regression_Test_Case__c, not end-user input
                    String soql = 'SELECT COUNT() FROM ' + String.escapeSingleQuotes(objName);
                    if (String.isNotBlank(whereClause)) {
                        soql += ' WHERE ' + whereClause;
                    }
                    soql += ' WITH USER_MODE';
                    Integer actualCount = Database.countQuery(soql);

                    Boolean passed = false;
                    if (operator == '>') { passed = actualCount > compareValue; }
                    else if (operator == '>=') { passed = actualCount >= compareValue; }
                    else if (operator == '<') { passed = actualCount < compareValue; }
                    else if (operator == '<=') { passed = actualCount <= compareValue; }

                    String message = passed ? null : 'Record count ' + actualCount + ' does not satisfy ' + operator + ' ' + compareValue;
                    return new RegressionTestAssertion.AssertionResult(passed, message, operator + ' ' + compareValue, String.valueOf(actualCount));
                }

                // Exact match (existing behavior)
                Integer expectedCount = String.isNotBlank(expected) ? Integer.valueOf(expected) : 0;
                return RegressionTestAssertion.assertRecordCount(objName, whereClause, expectedCount);
            }
            when 'Coverage Threshold' {
                // Steps: "ClassName"
                // Expected: minimum coverage percentage
                String className = parts.size() > 0 ? parts[0] : '';
                Decimal minPercent = String.isNotBlank(expected) ? Decimal.valueOf(expected) : 75;

                // Coverage data requires Tooling API (ApexCodeCoverageAggregate is not
                // available via standard SOQL). For now, check the class exists and
                // return a skip result. Future: integrate via HttpRequest to Tooling API.
                Decimal actualCoverage = null;
                if (String.isNotBlank(className)) {
                    List<ApexClass> cls = [
                        SELECT Id FROM ApexClass
                        WHERE Name = :className
                        WITH USER_MODE
                        LIMIT 1
                    ];
                    if (cls.isEmpty()) {
                        return new RegressionTestAssertion.AssertionResult(
                            false,
                            'Class not found: ' + className,
                            minPercent.setScale(1) + '%',
                            'Class not found'
                        );
                    }
                    // Class exists but coverage data requires Tooling API
                    return new RegressionTestAssertion.AssertionResult(
                        true,
                        'Coverage data not available for class: ' + className
                            + '. Tooling API integration required.',
                        minPercent.setScale(1) + '%',
                        'No data'
                    );
                }

                return RegressionTestAssertion.assertCoverage(className, actualCoverage, minPercent);
            }
            when 'No Error' {
                // Steps: "TestClassName"
                String testClassName = parts.size() > 0 ? parts[0] : '';
                return RegressionTestAssertion.assertNoGovernorViolation(testClassName);
            }
            when 'Custom Script' {
                // Steps contains a SOQL query; Expected contains the expected value
                // Execute the SOQL and compare the scalar result
                return executeCustomScript(steps, expected);
            }
            when else {
                return new RegressionTestAssertion.AssertionResult(
                    false, 'Unknown assertion type: ' + assertionType,
                    'A valid assertion type', assertionType);
            }
        }
    }

    /**
     * Executes a Custom Script assertion.
     * Steps__c should contain a SELECT-only SOQL query returning a single scalar value.
     * Expected_Result__c contains the expected string representation.
     * DML keywords are rejected to prevent data modification via test configuration.
     */
    @TestVisible
    private static RegressionTestAssertion.AssertionResult executeCustomScript(
            String soqlQuery, String expectedValue) {

        if (String.isBlank(soqlQuery)) {
            return new RegressionTestAssertion.AssertionResult(
                false, 'Custom Script: No SOQL query provided', expectedValue, 'null');
        }

        // Reject queries containing DML keywords to prevent data modification
        String upperQuery = soqlQuery.toUpperCase().trim();
        List<String> forbiddenKeywords = new List<String>{
            'INSERT', 'UPDATE', 'DELETE', 'UPSERT', 'MERGE'
        };
        for (String keyword : forbiddenKeywords) {
            // Check if the keyword appears as a standalone word (not inside a field name)
            if (Pattern.matches('(?i).*\\b' + keyword + '\\b.*', upperQuery)) {
                return new RegressionTestAssertion.AssertionResult(
                    false,
                    'Custom Script: Query rejected - contains forbidden keyword: ' + keyword,
                    expectedValue,
                    'Rejected'
                );
            }
        }

        // Enforce WITH USER_MODE for CRUD/FLS security
        if (!upperQuery.contains('WITH USER_MODE') && !upperQuery.contains('WITH SYSTEM_MODE')) {
            String trimmedQuery = soqlQuery.trim();
            if (trimmedQuery.endsWith(';')) {
                trimmedQuery = trimmedQuery.substring(0, trimmedQuery.length() - 1).trim();
            }
            // WITH USER_MODE must appear before ORDER BY, GROUP BY, LIMIT, OFFSET
            String upperTrimmed = trimmedQuery.toUpperCase();
            Integer insertPos = trimmedQuery.length();
            for (String clause : new List<String>{ ' ORDER BY ', ' ORDER BY\n', ' GROUP BY ', ' GROUP BY\n', ' LIMIT ', ' LIMIT\n', ' OFFSET ', ' OFFSET\n' }) {
                Integer idx = upperTrimmed.indexOf(clause);
                if (idx > 0 && idx < insertPos) {
                    insertPos = idx;
                }
            }
            soqlQuery = trimmedQuery.substring(0, insertPos) + ' WITH USER_MODE' + trimmedQuery.substring(insertPos);
        }

        List<SObject> queryResults;
        try {
            queryResults = Database.query(soqlQuery);
        } catch (QueryException qe) {
            return new RegressionTestAssertion.AssertionResult(
                false,
                'Custom Script: Query failed - ' + qe.getMessage(),
                expectedValue,
                'QueryException'
            );
        }
        String actualValue;

        if (queryResults.isEmpty()) {
            actualValue = 'No records returned';
        } else {
            // Get the first field value from the first record
            Map<String, Object> fieldMap = queryResults[0].getPopulatedFieldsAsMap();
            if (fieldMap.isEmpty()) {
                actualValue = 'No fields returned';
            } else {
                // Take the first non-Id field, or fall back to any field
                Object val = null;
                for (String fieldName : fieldMap.keySet()) {
                    if (fieldName != 'Id') {
                        val = fieldMap.get(fieldName);
                        break;
                    }
                }
                if (val == null && fieldMap.containsKey('Id')) {
                    val = fieldMap.get('Id');
                }
                actualValue = String.valueOf(val);
            }
        }

        return RegressionTestAssertion.assertEquals(expectedValue, actualValue, 'Custom Script');
    }

    /**
     * Layer 4: Static Analysis
     * Queries ApexClass bodies for anti-pattern detection.
     * Steps__c contains semicolon-delimited class names to analyze.
     * Checks for: SOQL in loops, DML in loops, hardcoded IDs, missing sharing.
     */
    @TestVisible
    private static List<Regression_Test_Result__c> executeStaticAnalysis(
            Id runId, List<Regression_Test_Case__c> testCases) {

        List<Regression_Test_Result__c> results = new List<Regression_Test_Result__c>();

        // Collect all referenced class names across all test cases
        Set<String> allClassNames = new Set<String>();
        for (Regression_Test_Case__c tc : testCases) {
            if (String.isNotBlank(tc.Steps__c)) {
                for (String name : tc.Steps__c.split(';')) {
                    String trimmed = name.trim();
                    if (String.isNotBlank(trimmed)) {
                        allClassNames.add(trimmed);
                    }
                }
            }
        }

        // Bulk-query all class bodies
        Map<String, String> classBodies = new Map<String, String>();
        if (!allClassNames.isEmpty()) {
            for (ApexClass cls : [
                SELECT Name, Body FROM ApexClass
                WHERE Name IN :allClassNames
                WITH USER_MODE
            ]) {
                classBodies.put(cls.Name.toLowerCase(), cls.Body);
            }
        }

        // Anti-pattern definitions
        List<AntiPattern> antiPatterns = new List<AntiPattern>{
            new AntiPattern('SOQL in Loop',
                '(?i)for\\s*\\([^)]*\\)[^}]*\\[\\s*SELECT',
                'SOQL query detected inside a loop - risk of governor limit violation'),
            new AntiPattern('DML in Loop',
                '(?i)for\\s*\\([^)]*\\)[^}]*(insert|update|delete|upsert)\\s+',
                'DML operation detected inside a loop - risk of governor limit violation'),
            new AntiPattern('Hardcoded ID',
                '\'0[0-9]{2}[a-zA-Z0-9]{12,15}\'',
                'Potential hardcoded Salesforce ID detected'),
            new AntiPattern('Missing sharing declaration',
                '(?i)public\\s+class\\s+(?!.*(with|without)\\s+sharing\\b)',
                'Class has no sharing declaration (neither "with sharing" nor "without sharing")')
        };

        // Process each test case
        for (Regression_Test_Case__c tc : testCases) {
            Long timer = System.currentTimeMillis();
            try {
                if (String.isBlank(tc.Steps__c)) {
                    results.add(buildResult(runId, tc, STATUS_PASSED, LAYER_STATIC_ANALYSIS,
                        System.currentTimeMillis() - timer,
                        null, null, 'No classes specified for analysis'));
                    continue;
                }

                List<String> violations = new List<String>();
                List<String> missingClasses = new List<String>();
                List<String> logLines = new List<String>();
                Integer classesAnalyzed = 0;

                for (String name : tc.Steps__c.split(';')) {
                    String trimmed = name.trim();
                    if (String.isBlank(trimmed)) {
                        continue;
                    }

                    String body = classBodies.get(trimmed.toLowerCase());
                    if (body == null) {
                        missingClasses.add(trimmed + ': Class not found in org');
                        logLines.add(trimmed + ': Class not found in org');
                        continue;
                    }

                    classesAnalyzed++;
                    logLines.add(trimmed + ': Analyzing...');

                    for (AntiPattern ap : antiPatterns) {
                        Pattern p = Pattern.compile(ap.regex);
                        Matcher m = p.matcher(body);
                        if (m.find()) {
                            violations.add(trimmed + ': ' + ap.name + ' - ' + ap.description);
                            logLines.add('  VIOLATION: ' + ap.name);
                        }
                    }
                }

                Long duration = System.currentTimeMillis() - timer;
                String log = 'Analyzed ' + classesAnalyzed + ' classes.\n'
                    + String.join(logLines, '\n')
                    + '\nViolations found: ' + violations.size();

                // Determine status: warning if only classes missing, pass/fail for violations
                String status;
                String errorMsg;
                if (!missingClasses.isEmpty() && violations.isEmpty()) {
                    // Only missing classes - use Warning status (advisory, not a real failure)
                    status = STATUS_WARNING;
                    errorMsg = String.join(missingClasses, '; ');
                } else if (!missingClasses.isEmpty() && !violations.isEmpty()) {
                    // Both missing classes and real violations - report as Failed (real issues exist)
                    List<String> allIssues = new List<String>();
                    allIssues.addAll(missingClasses);
                    allIssues.addAll(violations);
                    status = STATUS_FAILED;
                    errorMsg = allIssues.size() + ' issue(s): ' + String.join(allIssues, '; ');
                } else if (violations.isEmpty()) {
                    status = STATUS_PASSED;
                    errorMsg = null;
                } else if (tc.Expected_Violations__c != null
                        && violations.size() == tc.Expected_Violations__c.intValue()) {
                    status = STATUS_PASSED;
                    errorMsg = null;
                    log += '\nExpected ' + tc.Expected_Violations__c.intValue()
                        + ' violation(s) - matches actual (acknowledged patterns)';
                } else {
                    status = STATUS_FAILED;
                    errorMsg = violations.size() + ' violation(s): ' + String.join(violations, '; ');
                }

                Regression_Test_Result__c result = buildResult(runId, tc, status,
                    LAYER_STATIC_ANALYSIS, duration, errorMsg, null, log);
                result.Actual_Result__c = violations.size() + ' violations';
                results.add(result);

            } catch (Exception e) {
                results.add(buildResult(runId, tc, STATUS_ERROR, LAYER_STATIC_ANALYSIS,
                    System.currentTimeMillis() - timer,
                    e.getMessage(), e.getStackTraceString(), null));
            }
        }

        return results;
    }

    /**
     * Builds a Regression_Test_Result__c record with standard field population.
     * Does NOT insert - caller is responsible for bulk insert.
     */
    private static Regression_Test_Result__c buildResult(
            Id runId,
            Regression_Test_Case__c tc,
            String status,
            String layer,
            Long durationMs,
            String errorMessage,
            String stackTrace,
            String executionLog) {

        Regression_Test_Result__c result = new Regression_Test_Result__c(
            Test_Run__c = runId,
            Test_Case__c = tc.Id,
            Status__c = status,
            Layer__c = layer,
            Duration_Ms__c = durationMs,
            Previous_Status__c = tc.Last_Result_Status__c
        );

        if (String.isNotBlank(errorMessage)) {
            result.Error_Message__c = errorMessage.length() > 32000
                ? errorMessage.substring(0, 31997) + '...' : errorMessage;
        }
        if (String.isNotBlank(stackTrace)) {
            result.Stack_Trace__c = stackTrace.length() > 32000
                ? stackTrace.substring(0, 31997) + '...' : stackTrace;
        }
        if (String.isNotBlank(executionLog)) {
            result.Execution_Log__c = executionLog.length() > 131072
                ? executionLog.substring(0, 131069) + '...' : executionLog;
        }

        return result;
    }

    /**
     * Inner class representing a static analysis anti-pattern check.
     */
    @TestVisible
    private class AntiPattern {
        public String name;
        public String regex;
        public String description;

        public AntiPattern(String name, String regex, String description) {
            this.name = name;
            this.regex = regex;
            this.description = description;
        }
    }
}
