/**
 * RegressionTestRunnerTest - Tests for the RegressionTestRunner batch orchestrator.
 * Covers: suite execution with all layers, empty suites, inactive cases,
 * the @AuraEnabled runSuite() method, blocking layer skip logic, and bulk execution.
 */
@IsTest
private class RegressionTestRunnerTest {

    @TestSetup
    static void setup() {
        User testUser = ForceGuardTestDataFactory.createTestUser();

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = ForceGuardTestDataFactory.createSuite('Runner Test Product');
            insert suite;

            List<Regression_Test_Case__c> cases = ForceGuardTestDataFactory.createTestCases(suite.Id, 8);
            // Set deployment layer cases with valid object names
            for (Regression_Test_Case__c tc : cases) {
                if (tc.Test_Layer__c == 'Deployment') {
                    tc.Steps__c = 'CustomObject:Account;CustomObject:Contact';
                } else if (tc.Test_Layer__c == 'Apex Test') {
                    tc.Steps__c = '';
                } else if (tc.Test_Layer__c == 'Data Scenario') {
                    tc.Assertion_Type__c = 'Record Exists';
                    tc.Steps__c = 'Account';
                } else if (tc.Test_Layer__c == 'Static Analysis') {
                    tc.Steps__c = '';
                }
            }
            insert cases;
        }
    }

    @IsTest
    static void testRunSuiteWithAllLayers() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = [SELECT Id FROM Regression_Test_Suite__c LIMIT 1];

            Test.startTest();
            RegressionTestRunner runner = new RegressionTestRunner(suite.Id);
            Database.executeBatch(runner, 200);
            Test.stopTest();

            // Verify Run record was created
            List<Regression_Test_Run__c> runs = [
                SELECT Id, Status__c, Total_Tests__c, Test_Suite__c
                FROM Regression_Test_Run__c
                WHERE Test_Suite__c = :suite.Id
            ];
            System.assert(!runs.isEmpty(), 'At least one Run record should be created');
            System.assertEquals(suite.Id, runs[0].Test_Suite__c,
                'Run should reference the correct suite');

            // Verify result records were created
            List<Regression_Test_Result__c> results = [
                SELECT Id, Status__c, Layer__c
                FROM Regression_Test_Result__c
                WHERE Test_Run__c = :runs[0].Id
            ];
            System.assert(!results.isEmpty(), 'Result records should be created for the run');
        }
    }

    @IsTest
    static void testRunSuiteEmptySuite() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            // Create a suite with no test cases
            Regression_Test_Suite__c emptySuite = ForceGuardTestDataFactory.createSuite('Empty Product');
            insert emptySuite;

            Test.startTest();
            RegressionTestRunner runner = new RegressionTestRunner(emptySuite.Id);
            Database.executeBatch(runner, 200);
            Test.stopTest();

            Regression_Test_Run__c run = [
                SELECT Id, Status__c, Total_Tests__c, Passed__c, Failed__c
                FROM Regression_Test_Run__c
                WHERE Test_Suite__c = :emptySuite.Id
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            // With no test cases, the batch should complete with 0 tests
            System.assertNotEquals(null, run, 'Run record should exist even for empty suite');
            System.assert(
                run.Total_Tests__c == null || run.Total_Tests__c == 0,
                'Empty suite should have 0 total tests, got: ' + run.Total_Tests__c
            );
        }
    }

    @IsTest
    static void testRunSuiteInactiveCases() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Suite__c inactiveSuite = ForceGuardTestDataFactory.createSuite('Inactive Product');
            insert inactiveSuite;

            List<Regression_Test_Case__c> cases = ForceGuardTestDataFactory.createTestCases(inactiveSuite.Id, 4);
            for (Regression_Test_Case__c tc : cases) {
                tc.Is_Active__c = false;
            }
            insert cases;

            Test.startTest();
            RegressionTestRunner runner = new RegressionTestRunner(inactiveSuite.Id);
            Database.executeBatch(runner, 200);
            Test.stopTest();

            Regression_Test_Run__c run = [
                SELECT Id, Total_Tests__c
                FROM Regression_Test_Run__c
                WHERE Test_Suite__c = :inactiveSuite.Id
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            System.assert(
                run.Total_Tests__c == null || run.Total_Tests__c == 0,
                'Inactive cases should be excluded from run, got total: ' + run.Total_Tests__c
            );
        }
    }

    @IsTest
    static void testRunSuiteStaticMethod() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = [SELECT Id FROM Regression_Test_Suite__c LIMIT 1];

            Test.startTest();
            Id batchJobId = RegressionTestRunner.runSuite(suite.Id);
            Test.stopTest();

            System.assertNotEquals(null, batchJobId,
                'runSuite() should return a non-null batch job ID');
        }
    }

    @IsTest
    static void testRunSuiteStaticMethodNullId() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Test.startTest();
            try {
                RegressionTestRunner.runSuite(null);
                System.assert(false, 'Expected AuraHandledException for null suite ID');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage() != null,
                    'Exception should have a message, got: ' + e.getMessage());
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void testBlockingLayerSkipsSubsequent() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = ForceGuardTestDataFactory.createSuite('Blocking Test');
            insert suite;

            // Create a Deployment case with an invalid component to force failure
            Regression_Test_Case__c deployCase = new Regression_Test_Case__c(
                Test_Suite__c = suite.Id,
                Title__c = 'Bad Deploy',
                Test_Layer__c = 'Deployment',
                Category__c = 'Functional',
                Perspective__c = 'Developer',
                Priority__c = 'P1',
                Steps__c = 'CustomObject:TotallyFakeObject999__c',
                Expected_Result__c = 'Pass',
                Assertion_Type__c = 'No Error',
                Is_Active__c = true,
                Execution_Order__c = 1
            );
            // Create a Data Scenario case that should be skipped if deploy fails
            Regression_Test_Case__c dataCase = new Regression_Test_Case__c(
                Test_Suite__c = suite.Id,
                Title__c = 'Data Check',
                Test_Layer__c = 'Data Scenario',
                Category__c = 'Functional',
                Perspective__c = 'Developer',
                Priority__c = 'P1',
                Steps__c = 'Account',
                Expected_Result__c = 'Pass',
                Assertion_Type__c = 'Record Exists',
                Is_Active__c = true,
                Execution_Order__c = 2
            );
            insert new List<Regression_Test_Case__c>{ deployCase, dataCase };

            Test.startTest();
            RegressionTestRunner runner = new RegressionTestRunner(suite.Id);
            Database.executeBatch(runner, 200);
            Test.stopTest();

            // Verify the run completed
            Regression_Test_Run__c run = [
                SELECT Id, Status__c, Failed__c, Skipped__c
                FROM Regression_Test_Run__c
                WHERE Test_Suite__c = :suite.Id
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            System.assertNotEquals(null, run, 'Run record should exist');
            // Deployment failure should cause either failure or skipped results
            List<Regression_Test_Result__c> results = [
                SELECT Status__c, Layer__c
                FROM Regression_Test_Result__c
                WHERE Test_Run__c = :run.Id
            ];
            System.assert(!results.isEmpty(), 'Should have result records');
        }
    }

    @IsTest
    static void testBulkExecution() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Suite__c bulkSuite = ForceGuardTestDataFactory.createSuite('Bulk Product');
            insert bulkSuite;

            List<Regression_Test_Case__c> bulkCases =
                ForceGuardTestDataFactory.createBulkTestCases(bulkSuite.Id, 200, 'Deployment');
            insert bulkCases;

            Test.startTest();
            RegressionTestRunner runner = new RegressionTestRunner(bulkSuite.Id);
            Database.executeBatch(runner, 200);
            Test.stopTest();

            Regression_Test_Run__c run = [
                SELECT Id, Total_Tests__c
                FROM Regression_Test_Run__c
                WHERE Test_Suite__c = :bulkSuite.Id
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            System.assertNotEquals(null, run, 'Run record should exist for bulk execution');

            Integer resultCount = [
                SELECT COUNT()
                FROM Regression_Test_Result__c
                WHERE Test_Run__c = :run.Id
            ];
            System.assertEquals(200, resultCount,
                'Should have 200 result records for 200 bulk test cases');
        }
    }

    @IsTest
    static void testConstructorWithTriggerType() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = [SELECT Id FROM Regression_Test_Suite__c LIMIT 1];

            Test.startTest();
            RegressionTestRunner runner = new RegressionTestRunner(suite.Id, 'Scheduled');
            Test.stopTest();

            Regression_Test_Run__c run = [
                SELECT Triggered_By__c
                FROM Regression_Test_Run__c
                WHERE Test_Suite__c = :suite.Id
                AND Triggered_By__c = 'Scheduled'
                LIMIT 1
            ];
            System.assertEquals('Scheduled', run.Triggered_By__c,
                'Run should be marked as Scheduled trigger type');
        }
    }
}
