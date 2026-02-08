/**
 * RegressionTestExecutorTest - Tests for the RegressionTestExecutor layer execution engine.
 * Covers: all 4 layer types, skipped results, empty inputs, null handling,
 * and invalid component detection.
 */
@IsTest
private class RegressionTestExecutorTest {

    @TestSetup
    static void setup() {
        User testUser = ForceGuardTestDataFactory.createTestUser();

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = ForceGuardTestDataFactory.createSuite('Executor Test Product');
            insert suite;

            Regression_Test_Run__c run = ForceGuardTestDataFactory.createRun(suite.Id, 'Running');
            insert run;
        }
    }

    @IsTest
    static void testExecuteDeploymentLayer() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = [SELECT Id FROM Regression_Test_Suite__c LIMIT 1];
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];

            // Create test cases with valid object names
            Regression_Test_Case__c tc = new Regression_Test_Case__c(
                Test_Suite__c = suite.Id,
                Title__c = 'Deploy Valid Objects',
                Test_Layer__c = 'Deployment',
                Category__c = 'Functional',
                Perspective__c = 'Developer',
                Priority__c = 'P1',
                Steps__c = 'CustomObject:Account;CustomObject:Contact',
                Expected_Result__c = 'Pass',
                Assertion_Type__c = 'No Error',
                Is_Active__c = true,
                Execution_Order__c = 1
            );
            insert tc;

            Test.startTest();
            List<Regression_Test_Result__c> results =
                RegressionTestExecutor.executeLayer(run.Id, new List<Regression_Test_Case__c>{ tc }, 1);
            Test.stopTest();

            System.assertEquals(1, results.size(), 'Should return 1 result for 1 test case');
            System.assertEquals('Passed', results[0].Status__c,
                'Account and Contact should be found as valid objects');
            System.assertEquals('Deployment', results[0].Layer__c,
                'Layer should be Deployment');
        }
    }

    @IsTest
    static void testExecuteDeploymentLayerInvalidComponent() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = [SELECT Id FROM Regression_Test_Suite__c LIMIT 1];
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];

            Regression_Test_Case__c tc = new Regression_Test_Case__c(
                Test_Suite__c = suite.Id,
                Title__c = 'Deploy Invalid Component',
                Test_Layer__c = 'Deployment',
                Category__c = 'Functional',
                Perspective__c = 'Developer',
                Priority__c = 'P1',
                Steps__c = 'CustomObject:NonExistentObject999__c',
                Expected_Result__c = 'Fail',
                Assertion_Type__c = 'No Error',
                Is_Active__c = true,
                Execution_Order__c = 1
            );
            insert tc;

            Test.startTest();
            List<Regression_Test_Result__c> results =
                RegressionTestExecutor.executeLayer(run.Id, new List<Regression_Test_Case__c>{ tc }, 1);
            Test.stopTest();

            System.assertEquals(1, results.size(), 'Should return 1 result');
            System.assertEquals('Config Error', results[0].Status__c,
                'Non-existent object should produce Config Error, not Failed');
            System.assert(String.isNotBlank(results[0].Error_Message__c),
                'Error message should describe the missing component');
        }
    }

    @IsTest
    static void testExecuteDeploymentLayerBlankSteps() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = [SELECT Id FROM Regression_Test_Suite__c LIMIT 1];
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];

            Regression_Test_Case__c tc = new Regression_Test_Case__c(
                Test_Suite__c = suite.Id,
                Title__c = 'Deploy No Steps',
                Test_Layer__c = 'Deployment',
                Category__c = 'Functional',
                Perspective__c = 'Developer',
                Priority__c = 'P1',
                Steps__c = '',
                Expected_Result__c = 'Pass',
                Assertion_Type__c = 'No Error',
                Is_Active__c = true,
                Execution_Order__c = 1
            );
            insert tc;

            Test.startTest();
            List<Regression_Test_Result__c> results =
                RegressionTestExecutor.executeLayer(run.Id, new List<Regression_Test_Case__c>{ tc }, 1);
            Test.stopTest();

            System.assertEquals(1, results.size(), 'Should return 1 result for blank steps');
            System.assertEquals('Passed', results[0].Status__c,
                'Blank steps should pass (nothing to validate)');
        }
    }

    @IsTest
    static void testExecuteApexTestLayer() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = [SELECT Id FROM Regression_Test_Suite__c LIMIT 1];
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];

            // Use a class that should exist in test context
            Regression_Test_Case__c tc = new Regression_Test_Case__c(
                Test_Suite__c = suite.Id,
                Title__c = 'Check Apex Test Class',
                Test_Layer__c = 'Apex Test',
                Category__c = 'Functional',
                Perspective__c = 'Developer',
                Priority__c = 'P1',
                Steps__c = '',
                Expected_Result__c = 'Pass',
                Assertion_Type__c = 'No Error',
                Is_Active__c = true,
                Execution_Order__c = 1
            );
            insert tc;

            Test.startTest();
            List<Regression_Test_Result__c> results =
                RegressionTestExecutor.executeLayer(run.Id, new List<Regression_Test_Case__c>{ tc }, 2);
            Test.stopTest();

            System.assertEquals(1, results.size(), 'Should return 1 result');
            System.assertEquals('Apex Test', results[0].Layer__c,
                'Layer should be Apex Test');
        }
    }

    @IsTest
    static void testExecuteDataScenarioLayer() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = [SELECT Id FROM Regression_Test_Suite__c LIMIT 1];
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];

            // Create an account to query
            Account acc = new Account(Name = 'DataScenario Test Account');
            insert acc;

            Regression_Test_Case__c tc = new Regression_Test_Case__c(
                Test_Suite__c = suite.Id,
                Title__c = 'Data Scenario - Record Exists',
                Test_Layer__c = 'Data Scenario',
                Category__c = 'Functional',
                Perspective__c = 'Developer',
                Priority__c = 'P1',
                Steps__c = 'Account|Name = \'DataScenario Test Account\'',
                Expected_Result__c = 'At least 1 record',
                Assertion_Type__c = 'Record Exists',
                Is_Active__c = true,
                Execution_Order__c = 1
            );
            insert tc;

            Test.startTest();
            List<Regression_Test_Result__c> results =
                RegressionTestExecutor.executeLayer(run.Id, new List<Regression_Test_Case__c>{ tc }, 3);
            Test.stopTest();

            System.assertEquals(1, results.size(), 'Should return 1 result');
            System.assertEquals('Data Scenario', results[0].Layer__c,
                'Layer should be Data Scenario');
            System.assertEquals('Passed', results[0].Status__c,
                'Record Exists assertion should pass for inserted account');
        }
    }

    @IsTest
    static void testExecuteStaticAnalysisLayer() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = [SELECT Id FROM Regression_Test_Suite__c LIMIT 1];
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];

            Regression_Test_Case__c tc = new Regression_Test_Case__c(
                Test_Suite__c = suite.Id,
                Title__c = 'Static Analysis Check',
                Test_Layer__c = 'Static Analysis',
                Category__c = 'Functional',
                Perspective__c = 'Developer',
                Priority__c = 'P1',
                Steps__c = '',
                Expected_Result__c = '0 violations',
                Assertion_Type__c = 'No Error',
                Is_Active__c = true,
                Execution_Order__c = 1
            );
            insert tc;

            Test.startTest();
            List<Regression_Test_Result__c> results =
                RegressionTestExecutor.executeLayer(run.Id, new List<Regression_Test_Case__c>{ tc }, 4);
            Test.stopTest();

            System.assertEquals(1, results.size(), 'Should return 1 result');
            System.assertEquals('Static Analysis', results[0].Layer__c,
                'Layer should be Static Analysis');
        }
    }

    @IsTest
    static void testEmptyTestCaseList() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];

            Test.startTest();
            List<Regression_Test_Result__c> results =
                RegressionTestExecutor.executeLayer(run.Id, new List<Regression_Test_Case__c>(), 1);
            Test.stopTest();

            System.assertEquals(0, results.size(), 'Empty test case list should return no results');
        }
    }

    @IsTest
    static void testNullHandling() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];

            Test.startTest();
            // Null test cases
            List<Regression_Test_Result__c> results1 =
                RegressionTestExecutor.executeLayer(run.Id, null, 1);
            // Null layer number
            List<Regression_Test_Result__c> results2 =
                RegressionTestExecutor.executeLayer(run.Id, new List<Regression_Test_Case__c>(), null);
            Test.stopTest();

            System.assertEquals(0, results1.size(), 'Null test cases should return empty results');
            System.assertEquals(0, results2.size(), 'Null layer number should return empty results');
        }
    }

    @IsTest
    static void testUnknownLayerNumber() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = [SELECT Id FROM Regression_Test_Suite__c LIMIT 1];
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];

            Regression_Test_Case__c tc = new Regression_Test_Case__c(
                Test_Suite__c = suite.Id,
                Title__c = 'Unknown Layer',
                Test_Layer__c = 'Deployment',
                Category__c = 'Functional',
                Perspective__c = 'Developer',
                Priority__c = 'P1',
                Steps__c = 'Account',
                Expected_Result__c = 'Pass',
                Assertion_Type__c = 'No Error',
                Is_Active__c = true,
                Execution_Order__c = 1
            );
            insert tc;

            Test.startTest();
            List<Regression_Test_Result__c> results =
                RegressionTestExecutor.executeLayer(run.Id, new List<Regression_Test_Case__c>{ tc }, 99);
            Test.stopTest();

            System.assertEquals(1, results.size(), 'Unknown layer should return error result');
            System.assertEquals('Error', results[0].Status__c,
                'Unknown layer number should produce Error status');
            System.assert(results[0].Error_Message__c.contains('Unknown layer number'),
                'Error message should mention unknown layer, got: ' + results[0].Error_Message__c);
        }
    }

    @IsTest
    static void testCustomScriptRejectsDmlKeywords() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Test.startTest();
            // Test that DML keywords in the SOQL string are rejected
            RegressionTestAssertion.AssertionResult resultDelete =
                RegressionTestExecutor.executeCustomScript(
                    'DELETE FROM Account', 'anything');
            RegressionTestAssertion.AssertionResult resultInsert =
                RegressionTestExecutor.executeCustomScript(
                    'INSERT INTO Account', 'anything');
            RegressionTestAssertion.AssertionResult resultUpdate =
                RegressionTestExecutor.executeCustomScript(
                    'UPDATE Account SET Name = \'hack\'', 'anything');
            RegressionTestAssertion.AssertionResult resultUpsert =
                RegressionTestExecutor.executeCustomScript(
                    'UPSERT Account', 'anything');
            RegressionTestAssertion.AssertionResult resultMerge =
                RegressionTestExecutor.executeCustomScript(
                    'MERGE Account', 'anything');
            Test.stopTest();

            System.assertEquals(false, resultDelete.passed, 'DELETE keyword should be rejected');
            System.assert(resultDelete.message.contains('forbidden keyword'),
                'Message should mention forbidden keyword, got: ' + resultDelete.message);

            System.assertEquals(false, resultInsert.passed, 'INSERT keyword should be rejected');
            System.assertEquals(false, resultUpdate.passed, 'UPDATE keyword should be rejected');
            System.assertEquals(false, resultUpsert.passed, 'UPSERT keyword should be rejected');
            System.assertEquals(false, resultMerge.passed, 'MERGE keyword should be rejected');
        }
    }

    @IsTest
    static void testCustomScriptValidSelectQuery() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Account acc = new Account(Name = 'CustomScript Test Account');
            insert acc;

            Test.startTest();
            RegressionTestAssertion.AssertionResult result =
                RegressionTestExecutor.executeCustomScript(
                    'SELECT Name FROM Account WHERE Name = \'CustomScript Test Account\' LIMIT 1',
                    'CustomScript Test Account');
            Test.stopTest();

            System.assertEquals(true, result.passed,
                'Valid SELECT query should pass when result matches expected');
            System.assertEquals('CustomScript Test Account', result.actual,
                'Actual should be the queried account name');
        }
    }

    @IsTest
    static void testCustomScriptBlankQuery() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Test.startTest();
            RegressionTestAssertion.AssertionResult result =
                RegressionTestExecutor.executeCustomScript('', 'anything');
            Test.stopTest();

            System.assertEquals(false, result.passed,
                'Blank query should fail');
            System.assert(result.message.contains('No SOQL query'),
                'Message should indicate no query, got: ' + result.message);
        }
    }

    @IsTest
    static void testFieldValueDynamicLookup() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = [SELECT Id FROM Regression_Test_Suite__c LIMIT 1];
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];

            Account acc = new Account(Name = 'DynLookup Test', Industry = 'Technology');
            insert acc;

            Regression_Test_Case__c tc = new Regression_Test_Case__c(
                Test_Suite__c = suite.Id,
                Title__c = 'Field Value - Dynamic Lookup',
                Test_Layer__c = 'Data Scenario',
                Category__c = 'Functional',
                Perspective__c = 'Developer',
                Priority__c = 'P1',
                Steps__c = 'Account|Name=DynLookup Test|Industry',
                Expected_Result__c = 'Technology',
                Assertion_Type__c = 'Field Value',
                Is_Active__c = true,
                Execution_Order__c = 1
            );
            insert tc;

            Test.startTest();
            List<Regression_Test_Result__c> results =
                RegressionTestExecutor.executeLayer(run.Id, new List<Regression_Test_Case__c>{ tc }, 3);
            Test.stopTest();

            System.assertEquals(1, results.size(), 'Should return 1 result');
            System.assertEquals('Passed', results[0].Status__c,
                'Dynamic lookup should find record and match Industry value');
            System.assertEquals('Technology', results[0].Actual_Result__c,
                'Actual result should be Technology');
        }
    }

    @IsTest
    static void testFieldValueDynamicLookupNotFound() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = [SELECT Id FROM Regression_Test_Suite__c LIMIT 1];
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];

            Regression_Test_Case__c tc = new Regression_Test_Case__c(
                Test_Suite__c = suite.Id,
                Title__c = 'Field Value - Dynamic Not Found',
                Test_Layer__c = 'Data Scenario',
                Category__c = 'Functional',
                Perspective__c = 'Developer',
                Priority__c = 'P1',
                Steps__c = 'Account|Name=NonExistent Account 999|Industry',
                Expected_Result__c = 'Technology',
                Assertion_Type__c = 'Field Value',
                Is_Active__c = true,
                Execution_Order__c = 1
            );
            insert tc;

            Test.startTest();
            List<Regression_Test_Result__c> results =
                RegressionTestExecutor.executeLayer(run.Id, new List<Regression_Test_Case__c>{ tc }, 3);
            Test.stopTest();

            System.assertEquals(1, results.size(), 'Should return 1 result');
            System.assertEquals('Failed', results[0].Status__c,
                'Should fail when record not found via dynamic lookup');
        }
    }

    @IsTest
    static void testFieldValueDynamicLookupInvalidFormat() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = [SELECT Id FROM Regression_Test_Suite__c LIMIT 1];
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];

            // Missing equals sign in lookup expression
            Regression_Test_Case__c tc = new Regression_Test_Case__c(
                Test_Suite__c = suite.Id,
                Title__c = 'Field Value - Invalid Lookup',
                Test_Layer__c = 'Data Scenario',
                Category__c = 'Functional',
                Perspective__c = 'Developer',
                Priority__c = 'P1',
                Steps__c = 'Account|NameMissingEquals|Industry',
                Expected_Result__c = 'Technology',
                Assertion_Type__c = 'Field Value',
                Is_Active__c = true,
                Execution_Order__c = 1
            );
            insert tc;

            Test.startTest();
            List<Regression_Test_Result__c> results =
                RegressionTestExecutor.executeLayer(run.Id, new List<Regression_Test_Case__c>{ tc }, 3);
            Test.stopTest();

            System.assertEquals(1, results.size(), 'Should return 1 result');
            System.assertEquals('Failed', results[0].Status__c,
                'Should fail when lookup expression missing equals sign');
        }
    }

    @IsTest
    static void testExecuteDataScenarioRecordCount() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = [SELECT Id FROM Regression_Test_Suite__c LIMIT 1];
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];

            // Create 3 accounts
            List<Account> accounts = new List<Account>();
            for (Integer i = 0; i < 3; i++) {
                accounts.add(new Account(Name = 'CountTest Account ' + i));
            }
            insert accounts;

            Regression_Test_Case__c tc = new Regression_Test_Case__c(
                Test_Suite__c = suite.Id,
                Title__c = 'Data Scenario - Record Count',
                Test_Layer__c = 'Data Scenario',
                Category__c = 'Functional',
                Perspective__c = 'Developer',
                Priority__c = 'P1',
                Steps__c = 'Account|Name LIKE \'CountTest Account%\'',
                Expected_Result__c = '3',
                Assertion_Type__c = 'Record Count',
                Is_Active__c = true,
                Execution_Order__c = 1
            );
            insert tc;

            Test.startTest();
            List<Regression_Test_Result__c> results =
                RegressionTestExecutor.executeLayer(run.Id, new List<Regression_Test_Case__c>{ tc }, 3);
            Test.stopTest();

            System.assertEquals(1, results.size(), 'Should return 1 result');
            System.assertEquals('Passed', results[0].Status__c,
                'Record count of 3 should match expected value of 3');
        }
    }

    @IsTest
    static void testExecuteDataScenarioCoverageThreshold() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = [SELECT Id FROM Regression_Test_Suite__c LIMIT 1];
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];

            // Coverage Threshold for a real class (exists but no coverage data in test context)
            Regression_Test_Case__c tc = new Regression_Test_Case__c(
                Test_Suite__c = suite.Id,
                Title__c = 'Coverage Threshold Check',
                Test_Layer__c = 'Data Scenario',
                Category__c = 'Functional',
                Perspective__c = 'Developer',
                Priority__c = 'P1',
                Steps__c = 'RegressionTestExecutor',
                Expected_Result__c = '75',
                Assertion_Type__c = 'Coverage Threshold',
                Is_Active__c = true,
                Execution_Order__c = 1
            );
            insert tc;

            Test.startTest();
            List<Regression_Test_Result__c> results =
                RegressionTestExecutor.executeLayer(run.Id, new List<Regression_Test_Case__c>{ tc }, 3);
            Test.stopTest();

            System.assertEquals(1, results.size(), 'Should return 1 result');
            System.assertEquals('Data Scenario', results[0].Layer__c,
                'Layer should be Data Scenario');
            // Class exists but coverage data requires Tooling API - returns passed with skip message
            System.assertEquals('Passed', results[0].Status__c,
                'Coverage threshold without Tooling API data should pass (skipped)');
            System.assertEquals('No data', results[0].Actual_Result__c,
                'Actual result should indicate no data');
        }
    }

    @IsTest
    static void testExecuteDataScenarioCoverageThresholdNonexistentClass() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = [SELECT Id FROM Regression_Test_Suite__c LIMIT 1];
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];

            // Coverage Threshold with a class that does not exist in the org
            Regression_Test_Case__c tc = new Regression_Test_Case__c(
                Test_Suite__c = suite.Id,
                Title__c = 'Coverage Threshold Missing Class',
                Test_Layer__c = 'Data Scenario',
                Category__c = 'Functional',
                Perspective__c = 'Developer',
                Priority__c = 'P1',
                Steps__c = 'NonExistentClassForCoverage999',
                Expected_Result__c = '75',
                Assertion_Type__c = 'Coverage Threshold',
                Is_Active__c = true,
                Execution_Order__c = 1
            );
            insert tc;

            Test.startTest();
            List<Regression_Test_Result__c> results =
                RegressionTestExecutor.executeLayer(run.Id, new List<Regression_Test_Case__c>{ tc }, 3);
            Test.stopTest();

            System.assertEquals(1, results.size(), 'Should return 1 result');
            // Nonexistent class should return Failed with "Class not found"
            System.assertEquals('Failed', results[0].Status__c,
                'Nonexistent class should fail');
            System.assert(results[0].Error_Message__c.contains('not found'),
                'Error should mention class not found');
        }
    }

    @IsTest
    static void testConfigErrorForMissingApexTestClass() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = [SELECT Id FROM Regression_Test_Suite__c LIMIT 1];
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];

            Regression_Test_Case__c tc = new Regression_Test_Case__c(
                Test_Suite__c = suite.Id,
                Title__c = 'Apex Test - Missing Class',
                Test_Layer__c = 'Apex Test',
                Category__c = 'Functional',
                Perspective__c = 'Developer',
                Priority__c = 'P1',
                Steps__c = 'NonExistentTestClass999',
                Expected_Result__c = 'Pass',
                Assertion_Type__c = 'No Error',
                Is_Active__c = true,
                Execution_Order__c = 1
            );
            insert tc;

            Test.startTest();
            List<Regression_Test_Result__c> results =
                RegressionTestExecutor.executeLayer(run.Id, new List<Regression_Test_Case__c>{ tc }, 2);
            Test.stopTest();

            System.assertEquals(1, results.size(), 'Should return 1 result');
            System.assertEquals('Config Error', results[0].Status__c,
                'Missing test class should produce Config Error, not Failed');
            System.assert(results[0].Error_Message__c.contains('not found'),
                'Error should mention class not found, got: ' + results[0].Error_Message__c);
        }
    }

    @IsTest
    static void testConfigErrorForMissingStaticAnalysisClass() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = [SELECT Id FROM Regression_Test_Suite__c LIMIT 1];
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];

            Regression_Test_Case__c tc = new Regression_Test_Case__c(
                Test_Suite__c = suite.Id,
                Title__c = 'Static Analysis - Missing Class',
                Test_Layer__c = 'Static Analysis',
                Category__c = 'Functional',
                Perspective__c = 'Developer',
                Priority__c = 'P1',
                Steps__c = 'NonExistentClassForAnalysis999',
                Expected_Result__c = '0 violations',
                Assertion_Type__c = 'No Error',
                Is_Active__c = true,
                Execution_Order__c = 1
            );
            insert tc;

            Test.startTest();
            List<Regression_Test_Result__c> results =
                RegressionTestExecutor.executeLayer(run.Id, new List<Regression_Test_Case__c>{ tc }, 4);
            Test.stopTest();

            System.assertEquals(1, results.size(), 'Should return 1 result');
            System.assertEquals('Warning', results[0].Status__c,
                'Missing class in static analysis should produce Warning (advisory, not a real failure)');
            System.assert(results[0].Error_Message__c.contains('not found'),
                'Error should mention class not found, got: ' + results[0].Error_Message__c);
        }
    }

    @IsTest
    static void testStaticAnalysisWithoutSharingNotFlagged() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = [SELECT Id FROM Regression_Test_Suite__c LIMIT 1];
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];

            // RegressionTestExecutor uses 'with sharing' - should NOT trigger missing sharing
            Regression_Test_Case__c tc = new Regression_Test_Case__c(
                Test_Suite__c = suite.Id,
                Title__c = 'Sharing Declaration Check',
                Test_Layer__c = 'Static Analysis',
                Category__c = 'Functional',
                Perspective__c = 'Developer',
                Priority__c = 'P2',
                Steps__c = 'RegressionTestExecutor',
                Expected_Result__c = '0 violations',
                Assertion_Type__c = 'No Error',
                Is_Active__c = true,
                Execution_Order__c = 1
            );
            insert tc;

            Test.startTest();
            List<Regression_Test_Result__c> results =
                RegressionTestExecutor.executeLayer(run.Id, new List<Regression_Test_Case__c>{ tc }, 4);
            Test.stopTest();

            System.assertEquals(1, results.size(), 'Should return 1 result');
            // Class uses 'with sharing' so should not trigger missing sharing declaration
            System.assert(!results[0].Actual_Result__c.contains('Missing sharing'),
                'Class with "with sharing" should not be flagged for missing sharing declaration');
        }
    }

    @IsTest
    static void testStaticAnalysisExpectedViolationsPass() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = [SELECT Id FROM Regression_Test_Suite__c LIMIT 1];
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];

            // Analyze a real class and set Expected_Violations__c to match actual count
            // RegressionTestAssertion uses 'with sharing' and has no anti-patterns = 0 violations
            Regression_Test_Case__c tc = new Regression_Test_Case__c(
                Test_Suite__c = suite.Id,
                Title__c = 'Expected Violations Match',
                Test_Layer__c = 'Static Analysis',
                Category__c = 'Functional',
                Perspective__c = 'Developer',
                Priority__c = 'P2',
                Steps__c = 'RegressionTestScheduler',
                Expected_Result__c = '0 violations',
                Assertion_Type__c = 'No Error',
                Is_Active__c = true,
                Execution_Order__c = 1,
                Expected_Violations__c = 0
            );
            insert tc;

            Test.startTest();
            List<Regression_Test_Result__c> results =
                RegressionTestExecutor.executeLayer(run.Id, new List<Regression_Test_Case__c>{ tc }, 4);
            Test.stopTest();

            System.assertEquals(1, results.size(), 'Should return 1 result');
            // Class exists, 0 violations found, matches Expected_Violations__c of 0
            System.assertEquals('Passed', results[0].Status__c,
                'Zero violations matching Expected_Violations__c of 0 should pass');
        }
    }

    @IsTest
    static void testStaticAnalysisWarningForMissingClasses() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = [SELECT Id FROM Regression_Test_Suite__c LIMIT 1];
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];

            // Static Analysis with missing class should return Warning status (not Config Error)
            Regression_Test_Case__c tc = new Regression_Test_Case__c(
                Test_Suite__c = suite.Id,
                Title__c = 'Static Analysis Missing Class',
                Test_Layer__c = 'Static Analysis',
                Category__c = 'Functional',
                Perspective__c = 'Developer',
                Priority__c = 'P2',
                Steps__c = 'NonExistentClass999',
                Expected_Result__c = '0 violations',
                Assertion_Type__c = 'No Error',
                Is_Active__c = true,
                Execution_Order__c = 1
            );
            insert tc;

            Test.startTest();
            List<Regression_Test_Result__c> results =
                RegressionTestExecutor.executeLayer(run.Id, new List<Regression_Test_Case__c>{ tc }, 4);
            Test.stopTest();

            System.assertEquals(1, results.size(), 'Should return 1 result');
            System.assertEquals('Warning', results[0].Status__c,
                'Missing classes in Static Analysis should produce Warning status (advisory)');
            System.assert(results[0].Error_Message__c.contains('Class not found'),
                'Error message should describe missing class, got: ' + results[0].Error_Message__c);
        }
    }
}
