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
            System.assertEquals('Failed', results[0].Status__c,
                'Non-existent object should cause failure');
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
}
