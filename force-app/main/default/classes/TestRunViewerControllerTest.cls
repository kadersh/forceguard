/**
 * TestRunViewerControllerTest - Tests for the TestRunViewerController class.
 * Covers: paginated run listing, run detail with layer breakdown,
 * re-run of failed tests, and CSV export.
 */
@IsTest
private class TestRunViewerControllerTest {

    @TestSetup
    static void setup() {
        User testUser = ForceGuardTestDataFactory.createTestUser();

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = ForceGuardTestDataFactory.createSuite('Viewer Test Product');
            insert suite;

            List<Regression_Test_Case__c> cases = ForceGuardTestDataFactory.createTestCases(suite.Id, 8);
            insert cases;

            // Create two runs - one completed, one failed
            Regression_Test_Run__c completedRun = new Regression_Test_Run__c(
                Test_Suite__c = suite.Id,
                Run_Date__c = DateTime.now().addDays(-1),
                Status__c = 'Completed',
                Triggered_By__c = 'Manual',
                Run_By__c = UserInfo.getUserId(),
                Total_Tests__c = 8,
                Passed__c = 8,
                Failed__c = 0,
                Skipped__c = 0,
                Duration_Seconds__c = 3.5,
                Layer_1_Status__c = 'Passed',
                Layer_2_Status__c = 'Passed',
                Layer_3_Status__c = 'Passed',
                Layer_4_Status__c = 'Passed'
            );
            insert completedRun;

            // Insert all-passed results for completed run
            List<Regression_Test_Result__c> passedResults = ForceGuardTestDataFactory.createResults(
                completedRun.Id, cases, 'Passed');
            insert passedResults;

            Regression_Test_Run__c failedRun = new Regression_Test_Run__c(
                Test_Suite__c = suite.Id,
                Run_Date__c = DateTime.now(),
                Status__c = 'Failed',
                Triggered_By__c = 'Scheduled',
                Run_By__c = UserInfo.getUserId(),
                Total_Tests__c = 8,
                Passed__c = 5,
                Failed__c = 3,
                Skipped__c = 0,
                Duration_Seconds__c = 5.0,
                Layer_1_Status__c = 'Passed',
                Layer_2_Status__c = 'Failed',
                Layer_3_Status__c = 'Failed',
                Layer_4_Status__c = 'Passed'
            );
            insert failedRun;

            // Insert mixed results for failed run
            List<Regression_Test_Result__c> mixedResults = new List<Regression_Test_Result__c>();
            for (Integer i = 0; i < cases.size(); i++) {
                String status = (i < 5) ? 'Passed' : 'Failed';
                Regression_Test_Result__c r = new Regression_Test_Result__c(
                    Test_Run__c = failedRun.Id,
                    Test_Case__c = cases[i].Id,
                    Status__c = status,
                    Layer__c = cases[i].Test_Layer__c,
                    Duration_Ms__c = 150
                );
                if (status == 'Failed') {
                    r.Error_Message__c = 'Failure in case ' + (i + 1);
                }
                mixedResults.add(r);
            }
            insert mixedResults;
        }
    }

    @IsTest
    static void testGetTestRuns() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Test.startTest();
            TestRunViewerController.RunListResult result =
                TestRunViewerController.getTestRuns(null, 'All', 10, 0);
            Test.stopTest();

            System.assertNotEquals(null, result, 'Result should not be null');
            System.assertEquals(2, result.totalCount, 'Should have 2 runs total');
            System.assertEquals(2, result.runs.size(), 'Should return 2 runs');
        }
    }

    @IsTest
    static void testGetTestRunsWithFilters() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = [SELECT Id FROM Regression_Test_Suite__c LIMIT 1];

            Test.startTest();
            // Filter by status
            TestRunViewerController.RunListResult failedOnly =
                TestRunViewerController.getTestRuns(null, 'Failed', 10, 0);
            System.assertEquals(1, failedOnly.totalCount, 'Should have 1 failed run');

            // Filter by suite
            TestRunViewerController.RunListResult bySuite =
                TestRunViewerController.getTestRuns(suite.Id, 'All', 10, 0);
            System.assertEquals(2, bySuite.totalCount, 'Suite should have 2 runs');

            // Pagination
            TestRunViewerController.RunListResult page1 =
                TestRunViewerController.getTestRuns(null, 'All', 1, 0);
            System.assertEquals(1, page1.runs.size(), 'Page 1 should have 1 run');
            System.assertEquals(2, page1.totalCount, 'Total should still be 2');
            Test.stopTest();
        }
    }

    @IsTest
    static void testGetRunDetail() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Run__c failedRun = [
                SELECT Id FROM Regression_Test_Run__c
                WHERE Status__c = 'Failed' LIMIT 1
            ];

            Test.startTest();
            TestRunViewerController.RunDetail detail =
                TestRunViewerController.getRunDetail(failedRun.Id);
            Test.stopTest();

            System.assertNotEquals(null, detail, 'Detail should not be null');
            System.assertNotEquals(null, detail.run, 'Run record should not be null');
            System.assertEquals('Failed', detail.run.Status__c, 'Status should be Failed');
            System.assert(!detail.layerSummaries.isEmpty(),
                'Layer summaries should have entries');
            System.assert(detail.totalFailures > 0, 'Should have failures');
        }
    }

    @IsTest
    static void testRerunFailed() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Run__c failedRun = [
                SELECT Id FROM Regression_Test_Run__c
                WHERE Status__c = 'Failed' LIMIT 1
            ];

            Test.startTest();
            Id newRunId = TestRunViewerController.rerunFailed(failedRun.Id);
            Test.stopTest();

            System.assertNotEquals(null, newRunId, 'New run Id should not be null');

            Regression_Test_Run__c newRun = [
                SELECT Status__c, Triggered_By__c, Total_Tests__c
                FROM Regression_Test_Run__c
                WHERE Id = :newRunId
            ];
            System.assertEquals('Queued', newRun.Status__c, 'New run should be Queued');
            System.assertEquals('Re-run Failed', newRun.Triggered_By__c, 'Triggered by should be Re-run Failed');
            System.assertEquals(3, newRun.Total_Tests__c, 'Should target 3 failed tests');
        }
    }

    @IsTest
    static void testRerunFailedNoFailures() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Run__c completedRun = [
                SELECT Id FROM Regression_Test_Run__c
                WHERE Status__c = 'Completed' LIMIT 1
            ];

            Test.startTest();
            try {
                TestRunViewerController.rerunFailed(completedRun.Id);
                System.assert(false, 'Should have thrown AuraHandledException');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('No failed tests'),
                    'Error should mention no failed tests');
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void testExportCsv() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Run__c run = [
                SELECT Id FROM Regression_Test_Run__c
                WHERE Status__c = 'Failed' LIMIT 1
            ];

            Test.startTest();
            String csv = TestRunViewerController.exportCsv(run.Id);
            Test.stopTest();

            System.assert(String.isNotBlank(csv), 'CSV should not be blank');
            System.assert(csv.startsWith('Test Case,'), 'CSV should start with header');
            List<String> lines = csv.split('\n');
            System.assert(lines.size() > 1, 'CSV should have header plus data rows');
        }
    }
}
