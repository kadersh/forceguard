/**
 * TestResultDetailControllerTest - Tests for the TestResultDetailController class.
 * Covers: result listing by layer, single result detail, known issue toggle,
 * and single test case re-run.
 */
@IsTest
private class TestResultDetailControllerTest {

    @TestSetup
    static void setup() {
        User testUser = ForceGuardTestDataFactory.createTestUser();

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = ForceGuardTestDataFactory.createSuite('Detail Test Product');
            insert suite;

            List<Regression_Test_Case__c> cases = ForceGuardTestDataFactory.createTestCases(suite.Id, 8);
            insert cases;

            Regression_Test_Run__c run = new Regression_Test_Run__c(
                Test_Suite__c = suite.Id,
                Run_Date__c = DateTime.now(),
                Status__c = 'Failed',
                Triggered_By__c = 'Manual',
                Run_By__c = UserInfo.getUserId(),
                Total_Tests__c = 8,
                Passed__c = 5,
                Failed__c = 3,
                Skipped__c = 0,
                Duration_Seconds__c = 4.2,
                Layer_1_Status__c = 'Passed',
                Layer_2_Status__c = 'Failed',
                Layer_3_Status__c = 'Failed',
                Layer_4_Status__c = 'Passed'
            );
            insert run;

            List<Regression_Test_Result__c> results = new List<Regression_Test_Result__c>();
            for (Integer i = 0; i < cases.size(); i++) {
                String status = (i < 5) ? 'Passed' : 'Failed';
                Regression_Test_Result__c r = new Regression_Test_Result__c(
                    Test_Run__c = run.Id,
                    Test_Case__c = cases[i].Id,
                    Status__c = status,
                    Layer__c = cases[i].Test_Layer__c,
                    Duration_Ms__c = 200,
                    Is_Regression__c = (status == 'Failed'),
                    Is_Known_Issue__c = false
                );
                if (status == 'Failed') {
                    r.Error_Message__c = 'Assert failed: expected X got Y';
                    r.Stack_Trace__c = 'Class.TestClass.method: line 42, column 1';
                    r.Execution_Log__c = 'Step 1: Setup\nStep 2: Execute\nStep 3: Assert - FAILED';
                    r.Actual_Result__c = 'Got Y instead of X';
                }
                results.add(r);
            }
            insert results;
        }
    }

    @IsTest
    static void testGetRunResults() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];

            Test.startTest();
            TestResultDetailController.ResultsByLayer response =
                TestResultDetailController.getRunResults(run.Id);
            Test.stopTest();

            System.assertNotEquals(null, response, 'Response should not be null');
            System.assertNotEquals(null, response.runInfo, 'Run info should not be null');
            System.assertNotEquals(null, response.layers, 'Layers map should not be null');
            System.assert(!response.layers.isEmpty(), 'Layers should have entries');

            // Verify results are grouped by layer
            Integer totalItems = 0;
            for (String layer : response.layers.keySet()) {
                List<TestResultDetailController.ResultItem> items = response.layers.get(layer);
                System.assert(!items.isEmpty(), 'Layer ' + layer + ' should have items');
                for (TestResultDetailController.ResultItem item : items) {
                    System.assertNotEquals(null, item.testCaseTitle,
                        'Test case title should not be null');
                    System.assertNotEquals(null, item.result,
                        'Result record should not be null');
                    totalItems++;
                }
            }
            System.assertEquals(8, totalItems, 'Should have 8 total result items');
        }
    }

    @IsTest
    static void testGetResultDetail() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Result__c failedResult = [
                SELECT Id FROM Regression_Test_Result__c
                WHERE Status__c = 'Failed' LIMIT 1
            ];

            Test.startTest();
            TestResultDetailController.ResultItem item =
                TestResultDetailController.getResultDetail(failedResult.Id);
            Test.stopTest();

            System.assertNotEquals(null, item, 'Result item should not be null');
            System.assertEquals('Failed', item.result.Status__c, 'Status should be Failed');
            System.assertNotEquals(null, item.result.Error_Message__c,
                'Error message should not be null');
            System.assertNotEquals(null, item.result.Stack_Trace__c,
                'Stack trace should not be null');
            System.assertNotEquals(null, item.testCaseTitle,
                'Test case title should not be null');
            System.assertNotEquals(null, item.priority,
                'Priority should not be null');
        }
    }

    @IsTest
    static void testMarkKnownIssue() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Result__c failedResult = [
                SELECT Id, Is_Known_Issue__c FROM Regression_Test_Result__c
                WHERE Status__c = 'Failed' LIMIT 1
            ];
            System.assertEquals(false, failedResult.Is_Known_Issue__c,
                'Should start as not known issue');

            Test.startTest();
            // Mark as known issue
            TestResultDetailController.markKnownIssue(failedResult.Id, true);

            Regression_Test_Result__c updated = [
                SELECT Is_Known_Issue__c FROM Regression_Test_Result__c
                WHERE Id = :failedResult.Id
            ];
            System.assertEquals(true, updated.Is_Known_Issue__c,
                'Should be marked as known issue');

            // Unmark
            TestResultDetailController.markKnownIssue(failedResult.Id, false);
            Test.stopTest();

            Regression_Test_Result__c unmarked = [
                SELECT Is_Known_Issue__c FROM Regression_Test_Result__c
                WHERE Id = :failedResult.Id
            ];
            System.assertEquals(false, unmarked.Is_Known_Issue__c,
                'Should be unmarked as known issue');
        }
    }

    @IsTest
    static void testRerunTestCase() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = [SELECT Id FROM Regression_Test_Suite__c LIMIT 1];
            Regression_Test_Case__c testCase = [SELECT Id FROM Regression_Test_Case__c LIMIT 1];

            Test.startTest();
            Id newRunId = TestResultDetailController.rerunTestCase(testCase.Id, suite.Id);
            Test.stopTest();

            System.assertNotEquals(null, newRunId, 'New run Id should not be null');

            Regression_Test_Run__c newRun = [
                SELECT Status__c, Triggered_By__c, Total_Tests__c, Test_Suite__c
                FROM Regression_Test_Run__c
                WHERE Id = :newRunId
            ];
            System.assertEquals('Queued', newRun.Status__c, 'New run should be Queued');
            System.assertEquals('Re-run Single', newRun.Triggered_By__c,
                'Triggered by should be Re-run Single');
            System.assertEquals(1, newRun.Total_Tests__c, 'Should target 1 test case');
            System.assertEquals(suite.Id, newRun.Test_Suite__c,
                'Should belong to the correct suite');
        }
    }
}
