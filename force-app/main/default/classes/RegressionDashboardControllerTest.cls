/**
 * RegressionDashboardControllerTest - Unit tests for RegressionDashboardController.
 * Tests all 6 @AuraEnabled methods with proper test data setup using ForceGuardTestDataFactory.
 */
@IsTest
private class RegressionDashboardControllerTest {

    @TestSetup
    static void setupTestData() {
        // Create two active suites
        Regression_Test_Suite__c suite1 = ForceGuardTestDataFactory.createSuite('Product Alpha');
        Regression_Test_Suite__c suite2 = ForceGuardTestDataFactory.createSuite('Product Beta');
        insert new List<Regression_Test_Suite__c>{ suite1, suite2 };

        // Create test cases for suite 1 (8 cases across 4 layers)
        List<Regression_Test_Case__c> cases1 = ForceGuardTestDataFactory.createTestCases(suite1.Id, 8);
        insert cases1;

        // Create test cases for suite 2 (4 cases)
        List<Regression_Test_Case__c> cases2 = ForceGuardTestDataFactory.createTestCases(suite2.Id, 4);
        insert cases2;

        // Create a completed run for suite 1
        Regression_Test_Run__c run1 = ForceGuardTestDataFactory.createRun(suite1.Id, 'Completed');
        run1.Total_Tests__c = 8;
        run1.Passed__c = 7;
        run1.Failed__c = 1;
        run1.Duration_Seconds__c = 45.5;
        run1.Run_Date__c = DateTime.now().addHours(-2);
        insert run1;

        // Create results for run1
        List<Regression_Test_Result__c> results1 = ForceGuardTestDataFactory.createResults(run1.Id, cases1, 'Passed');
        // Make one result Failed
        results1[0].Status__c = 'Failed';
        results1[0].Error_Message__c = 'Assertion failed';
        insert results1;

        // Update suite 1 last run fields
        suite1.Last_Run_Date__c = run1.Run_Date__c;
        suite1.Last_Run_Status__c = 'Passed';
        update suite1;

        // Create a failed run for suite 2
        Regression_Test_Run__c run2 = ForceGuardTestDataFactory.createRun(suite2.Id, 'Failed');
        run2.Total_Tests__c = 4;
        run2.Passed__c = 2;
        run2.Failed__c = 2;
        run2.Duration_Seconds__c = 30.0;
        run2.Run_Date__c = DateTime.now().addHours(-1);
        insert run2;

        suite2.Last_Run_Date__c = run2.Run_Date__c;
        suite2.Last_Run_Status__c = 'Failed';
        update suite2;
    }

    @IsTest
    static void testGetDashboardSummary() {
        User testUser = ForceGuardTestDataFactory.createTestUser();
        System.runAs(testUser) {
            Test.startTest();
            RegressionDashboardController.DashboardSummary summary =
                RegressionDashboardController.getDashboardSummary();
            Test.stopTest();

            System.assertNotEquals(null, summary, 'Summary should not be null');
            System.assertEquals(2, summary.totalSuites, 'Should have 2 active suites');
            System.assertEquals(12, summary.totalTestCases, 'Should have 12 test cases total');
            System.assertNotEquals(null, summary.lastRunDate, 'Last run date should be set');
            // Overall pass rate: (7+2)/(8+4) = 9/12 = 75%
            System.assert(summary.overallPassRate > 0, 'Pass rate should be positive');
            System.assertEquals(3, summary.totalFailures, 'Should have 3 total failures (1+2)');
        }
    }

    @IsTest
    static void testGetDashboardSummaryNoSuites() {
        // Create test user in isolated runAs to avoid MIXED_DML_OPERATION
        // (PermissionSetAssignment is setup DML, suite update is non-setup DML)
        User testUser;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            testUser = ForceGuardTestDataFactory.createTestUser();
        }

        // Deactivate all suites
        List<Regression_Test_Suite__c> allSuites = [
            SELECT Id FROM Regression_Test_Suite__c
        ];
        for (Regression_Test_Suite__c s : allSuites) {
            s.Is_Active__c = false;
        }
        update allSuites;

        System.runAs(testUser) {
            Test.startTest();
            RegressionDashboardController.DashboardSummary summary =
                RegressionDashboardController.getDashboardSummary();
            Test.stopTest();

            System.assertEquals(0, summary.totalSuites, 'Should have 0 suites');
            System.assertEquals(0, summary.totalTestCases, 'Should have 0 test cases');
        }
    }

    @IsTest
    static void testGetSuiteOverviews() {
        User testUser = ForceGuardTestDataFactory.createTestUser();
        System.runAs(testUser) {
            Test.startTest();
            List<RegressionDashboardController.SuiteOverview> overviews =
                RegressionDashboardController.getSuiteOverviews();
            Test.stopTest();

            System.assertEquals(2, overviews.size(), 'Should return 2 suite overviews');

            // Verify first suite (sorted by Product_Name__c: Alpha before Beta)
            RegressionDashboardController.SuiteOverview alpha = overviews[0];
            System.assertEquals('Product Alpha', alpha.productName, 'First should be Product Alpha');
            System.assertEquals(true, alpha.isActive, 'Should be active');
            System.assertEquals(8, alpha.testCaseCount, 'Alpha should have 8 test cases');
            System.assertNotEquals(null, alpha.passRate, 'Alpha pass rate should be set');

            RegressionDashboardController.SuiteOverview beta = overviews[1];
            System.assertEquals('Product Beta', beta.productName, 'Second should be Product Beta');
            System.assertEquals(4, beta.testCaseCount, 'Beta should have 4 test cases');
        }
    }

    @IsTest
    static void testGetRecentRuns() {
        User testUser = ForceGuardTestDataFactory.createTestUser();
        System.runAs(testUser) {
            Test.startTest();
            List<Regression_Test_Run__c> runs =
                RegressionDashboardController.getRecentRuns(5);
            Test.stopTest();

            System.assertEquals(2, runs.size(), 'Should return 2 runs');
            // Ordered by Run_Date__c DESC - most recent first (suite 2 run)
            System.assertEquals('Failed', runs[0].Status__c, 'Most recent run should be Failed');
        }
    }

    @IsTest
    static void testGetRecentRunsDefaultLimit() {
        User testUser = ForceGuardTestDataFactory.createTestUser();
        System.runAs(testUser) {
            Test.startTest();
            List<Regression_Test_Run__c> runs =
                RegressionDashboardController.getRecentRuns(null);
            Test.stopTest();

            System.assert(runs.size() <= 10, 'Default limit should be 10');
        }
    }

    @IsTest
    static void testRunSuite() {
        Regression_Test_Suite__c suite = [
            SELECT Id FROM Regression_Test_Suite__c
            WHERE Product_Name__c = 'Product Alpha' LIMIT 1
        ];

        // Run in admin context - runSuite delegates to system-level RegressionTestRunner
        Test.startTest();
        Id jobId = RegressionDashboardController.runSuite(suite.Id);
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Should return a batch job ID');
    }

    @IsTest
    static void testRunSuiteNullId() {
        // Run in admin context - runSuite delegates to system-level RegressionTestRunner
        Test.startTest();
        try {
            RegressionDashboardController.runSuite(null);
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().length() > 0, 'Error message should not be empty');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetBatchJobStatus() {
        User testUser = ForceGuardTestDataFactory.createTestUser();
        System.runAs(testUser) {
            Test.startTest();
            // Test with null job ID
            Map<String, Object> nullResult =
                RegressionDashboardController.getBatchJobStatus(null);
            System.assertEquals('Unknown', nullResult.get('status'), 'Null job should return Unknown');

            // Test with a non-existent job ID (use a fake ID)
            // AsyncApexJob IDs are 18-char. Use a valid format but non-existent record
            Map<String, Object> notFoundResult =
                RegressionDashboardController.getBatchJobStatus(
                    '707000000000000AAA'
                );
            System.assertEquals('Not Found', notFoundResult.get('status'),
                'Non-existent job should return Not Found');
            Test.stopTest();
        }
    }

    @IsTest
    static void testGetBatchJobStatusWithRealJob() {
        Regression_Test_Suite__c suite = [
            SELECT Id FROM Regression_Test_Suite__c
            WHERE Product_Name__c = 'Product Alpha' LIMIT 1
        ];

        // Run in admin context - runSuite delegates to system-level RegressionTestRunner
        Test.startTest();
        Id jobId = RegressionDashboardController.runSuite(suite.Id);
        Test.stopTest();

        // After Test.stopTest(), the batch has completed
        Map<String, Object> result =
            RegressionDashboardController.getBatchJobStatus(jobId);
        System.assertNotEquals(null, result.get('status'), 'Status should be set');
        System.assertNotEquals(null, result.get('progress'), 'Progress should be set');
    }

    @IsTest
    static void testScheduleRunDaily() {
        // Run in admin context - scheduling is an admin operation
        Test.startTest();
        RegressionDashboardController.scheduleRun('daily', null);
        Test.stopTest();

        List<CronTrigger> jobs = [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'ForceGuard%'
        ];
        System.assert(!jobs.isEmpty(), 'Should have scheduled a ForceGuard job');
    }

    @IsTest
    static void testScheduleRunWeekly() {
        // Run in admin context - scheduling is an admin operation
        Test.startTest();
        RegressionDashboardController.scheduleRun('weekly', null);
        Test.stopTest();

        List<CronTrigger> jobs = [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'ForceGuard%'
        ];
        System.assert(!jobs.isEmpty(), 'Should have scheduled a ForceGuard weekly job');
    }

    @IsTest
    static void testScheduleRunMonthly() {
        // Run in admin context - scheduling is an admin operation
        Test.startTest();
        RegressionDashboardController.scheduleRun('monthly', null);
        Test.stopTest();

        List<CronTrigger> jobs = [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'ForceGuard%'
        ];
        System.assert(!jobs.isEmpty(), 'Should have scheduled a ForceGuard monthly job');
    }

    @IsTest
    static void testScheduleRunInvalidFrequency() {
        // Run in admin context - testing error handling
        Test.startTest();
        try {
            RegressionDashboardController.scheduleRun('hourly', null);
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid frequency'),
                'Error should mention invalid frequency');
        }
        Test.stopTest();
    }

    @IsTest
    static void testScheduleRunBlankFrequency() {
        // Run in admin context - testing error handling
        Test.startTest();
        try {
            RegressionDashboardController.scheduleRun('', null);
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().length() > 0,
                'Error message should not be empty');
        }
        Test.stopTest();
    }
}
