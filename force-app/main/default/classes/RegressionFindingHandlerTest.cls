/**
 * RegressionFindingHandlerTest - Tests for RegressionFindingHandler and
 * RegressionTestResultTrigger. Validates that Regression_Finding__c records
 * are created correctly for regression results, with deduplication and bulk support.
 */
@IsTest
private with sharing class RegressionFindingHandlerTest {

    @TestSetup
    static void setup() {
        // Create test user inside System.runAs to avoid MIXED_DML with custom objects
        User testUser;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            testUser = ForceGuardTestDataFactory.createTestUser();
        }

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = ForceGuardTestDataFactory.createSuite('FindingTest');
            insert suite;

            List<Regression_Test_Case__c> cases = ForceGuardTestDataFactory.createTestCases(suite.Id, 4);
            insert cases;

            Regression_Test_Run__c run = ForceGuardTestDataFactory.createRun(suite.Id, 'Completed');
            insert run;
        }
    }

    @IsTest
    static void testFindingCreatedOnRegression() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];
        System.runAs(testUser) {
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];
            Regression_Test_Case__c tc = [SELECT Id, Test_Layer__c FROM Regression_Test_Case__c LIMIT 1];

            Regression_Test_Result__c result = new Regression_Test_Result__c(
                Test_Run__c = run.Id,
                Test_Case__c = tc.Id,
                Status__c = 'Failed',
                Is_Regression__c = true,
                Layer__c = tc.Test_Layer__c,
                Duration_Ms__c = 50,
                Error_Message__c = 'Assertion failed: expected true got false'
            );

            Test.startTest();
            insert result;
            Test.stopTest();

            List<Regression_Finding__c> findings = [
                SELECT Id, Test_Case__c, Test_Run__c, Test_Result__c, Error_Message__c,
                       Status__c, Layer__c, Priority__c, Finding_Date__c, Suite_Name__c
                FROM Regression_Finding__c
                WHERE Test_Run__c = :run.Id
            ];
            System.assertEquals(1, findings.size(), 'One finding should be created for the regression');
            System.assertEquals(tc.Id, findings[0].Test_Case__c, 'Finding should reference the test case');
            System.assertEquals(result.Id, findings[0].Test_Result__c, 'Finding should reference the result');
            System.assertEquals('Open', findings[0].Status__c, 'Default status should be Open');
            System.assertNotEquals(null, findings[0].Finding_Date__c, 'Finding date should be set');
            System.assertNotEquals(null, findings[0].Suite_Name__c, 'Suite name should be populated');
        }
    }

    @IsTest
    static void testNoFindingForNonRegression() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];
        System.runAs(testUser) {
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];
            Regression_Test_Case__c tc = [SELECT Id, Test_Layer__c FROM Regression_Test_Case__c LIMIT 1];

            Regression_Test_Result__c result = new Regression_Test_Result__c(
                Test_Run__c = run.Id,
                Test_Case__c = tc.Id,
                Status__c = 'Failed',
                Is_Regression__c = false,
                Layer__c = tc.Test_Layer__c,
                Duration_Ms__c = 50,
                Error_Message__c = 'Test failed but not a regression'
            );

            Test.startTest();
            insert result;
            Test.stopTest();

            List<Regression_Finding__c> findings = [
                SELECT Id FROM Regression_Finding__c WHERE Test_Run__c = :run.Id
            ];
            System.assertEquals(0, findings.size(), 'No finding for non-regression failure');
        }
    }

    @IsTest
    static void testNoFindingForPassedTests() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];
        System.runAs(testUser) {
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];
            Regression_Test_Case__c tc = [SELECT Id, Test_Layer__c FROM Regression_Test_Case__c LIMIT 1];

            Regression_Test_Result__c result = new Regression_Test_Result__c(
                Test_Run__c = run.Id,
                Test_Case__c = tc.Id,
                Status__c = 'Passed',
                Is_Regression__c = false,
                Layer__c = tc.Test_Layer__c,
                Duration_Ms__c = 50
            );

            Test.startTest();
            insert result;
            Test.stopTest();

            List<Regression_Finding__c> findings = [
                SELECT Id FROM Regression_Finding__c WHERE Test_Run__c = :run.Id
            ];
            System.assertEquals(0, findings.size(), 'No finding for passed test');
        }
    }

    @IsTest
    static void testBulkFindingCreation() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];
        System.runAs(testUser) {
            Regression_Test_Suite__c suite = [SELECT Id FROM Regression_Test_Suite__c LIMIT 1];

            // Create 200+ test cases for bulk testing
            List<Regression_Test_Case__c> bulkCases = ForceGuardTestDataFactory.createBulkTestCases(
                suite.Id, 210, 'Apex Test'
            );
            insert bulkCases;

            // Create a new run for bulk results
            Regression_Test_Run__c bulkRun = ForceGuardTestDataFactory.createRun(suite.Id, 'Completed');
            insert bulkRun;

            // Build mixed results: 105 regressions + 105 non-regressions
            List<Regression_Test_Result__c> results = new List<Regression_Test_Result__c>();
            for (Integer i = 0; i < bulkCases.size(); i++) {
                Boolean isRegression = Math.mod(i, 2) == 0;
                results.add(new Regression_Test_Result__c(
                    Test_Run__c = bulkRun.Id,
                    Test_Case__c = bulkCases[i].Id,
                    Status__c = 'Failed',
                    Is_Regression__c = isRegression,
                    Layer__c = 'Apex Test',
                    Duration_Ms__c = 10,
                    Error_Message__c = isRegression ? 'Regression error ' + i : 'Normal failure ' + i
                ));
            }

            Test.startTest();
            insert results;
            Test.stopTest();

            Integer findingCount = [
                SELECT COUNT() FROM Regression_Finding__c WHERE Test_Run__c = :bulkRun.Id
            ];
            System.assertEquals(105, findingCount, 'Should create 105 findings for 105 regressions out of 210 results');
        }
    }

    @IsTest
    static void testDeduplication() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];
        System.runAs(testUser) {
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];
            Regression_Test_Case__c tc = [SELECT Id, Test_Layer__c FROM Regression_Test_Case__c LIMIT 1];

            // Insert first regression result - should create a finding
            Regression_Test_Result__c result1 = new Regression_Test_Result__c(
                Test_Run__c = run.Id,
                Test_Case__c = tc.Id,
                Status__c = 'Failed',
                Is_Regression__c = true,
                Layer__c = tc.Test_Layer__c,
                Duration_Ms__c = 50,
                Error_Message__c = 'First regression'
            );
            insert result1;

            Integer firstCount = [SELECT COUNT() FROM Regression_Finding__c WHERE Test_Run__c = :run.Id];
            System.assertEquals(1, firstCount, 'First regression should create one finding');

            // Insert second regression result for same test case + run - should NOT create another finding
            Regression_Test_Result__c result2 = new Regression_Test_Result__c(
                Test_Run__c = run.Id,
                Test_Case__c = tc.Id,
                Status__c = 'Failed',
                Is_Regression__c = true,
                Layer__c = tc.Test_Layer__c,
                Duration_Ms__c = 60,
                Error_Message__c = 'Second regression - duplicate'
            );

            Test.startTest();
            insert result2;
            Test.stopTest();

            Integer secondCount = [SELECT COUNT() FROM Regression_Finding__c WHERE Test_Run__c = :run.Id];
            System.assertEquals(1, secondCount, 'Duplicate regression should not create a second finding');
        }
    }

    @IsTest
    static void testBypassPermission() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];
        System.runAs(testUser) {
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];
            Regression_Test_Case__c tc = [SELECT Id, Test_Layer__c FROM Regression_Test_Case__c LIMIT 1];

            // Verify handler can be called directly without errors
            List<Regression_Test_Result__c> emptyList = new List<Regression_Test_Result__c>();

            Test.startTest();
            RegressionFindingHandler.handleAfterInsert(emptyList);
            Test.stopTest();

            // Verify no findings created from empty list
            Integer count = [SELECT COUNT() FROM Regression_Finding__c WHERE Test_Run__c = :run.Id];
            System.assertEquals(0, count, 'No findings should be created from empty list');
        }
    }
}
