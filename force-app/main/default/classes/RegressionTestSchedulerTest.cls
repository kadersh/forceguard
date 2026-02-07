/**
 * RegressionTestSchedulerTest - Tests for the RegressionTestScheduler class.
 * Covers: execute(), scheduleDaily(), scheduleWeekly(), scheduleMonthly(),
 * scheduleCustom(), unschedule(), isScheduled(), and no active suites scenario.
 */
@IsTest
private class RegressionTestSchedulerTest {

    @TestSetup
    static void setup() {
        User testUser = ForceGuardTestDataFactory.createTestUser();

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = ForceGuardTestDataFactory.createSuite('Scheduler Test Product');
            insert suite;

            // Create a few test cases so the batch has something to process
            List<Regression_Test_Case__c> cases = ForceGuardTestDataFactory.createTestCases(suite.Id, 4);
            for (Regression_Test_Case__c tc : cases) {
                if (tc.Test_Layer__c == 'Deployment') {
                    tc.Steps__c = 'CustomObject:Account';
                }
            }
            insert cases;
        }
    }

    @IsTest
    static void testExecuteScheduler() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Test.startTest();
            RegressionTestScheduler scheduler = new RegressionTestScheduler();
            scheduler.execute(null);
            Test.stopTest();

            // Verify at least one run was created by the scheduler
            List<Regression_Test_Run__c> runs = [
                SELECT Id, Triggered_By__c
                FROM Regression_Test_Run__c
                WHERE Triggered_By__c = 'Scheduled'
            ];
            System.assert(!runs.isEmpty(),
                'Scheduler execute should create at least one run for active suites');
        }
    }

    @IsTest
    static void testScheduleDaily() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Test.startTest();
            Id jobId = RegressionTestScheduler.scheduleDaily();
            Test.stopTest();

            System.assertNotEquals(null, jobId,
                'scheduleDaily should return a non-null job ID');

            // Verify the job is scheduled
            List<CronTrigger> jobs = [
                SELECT Id, CronJobDetail.Name
                FROM CronTrigger
                WHERE Id = :jobId
            ];
            System.assertEquals(1, jobs.size(),
                'Should find exactly 1 scheduled job');
            System.assert(jobs[0].CronJobDetail.Name.contains('Daily'),
                'Job name should contain Daily, got: ' + jobs[0].CronJobDetail.Name);

            // Cleanup: abort the scheduled job
            System.abortJob(jobId);
        }
    }

    @IsTest
    static void testScheduleWeekly() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Test.startTest();
            Id jobId = RegressionTestScheduler.scheduleWeekly();
            Test.stopTest();

            System.assertNotEquals(null, jobId,
                'scheduleWeekly should return a non-null job ID');

            List<CronTrigger> jobs = [
                SELECT CronJobDetail.Name
                FROM CronTrigger
                WHERE Id = :jobId
            ];
            System.assert(jobs[0].CronJobDetail.Name.contains('Weekly'),
                'Job name should contain Weekly, got: ' + jobs[0].CronJobDetail.Name);

            System.abortJob(jobId);
        }
    }

    @IsTest
    static void testScheduleMonthly() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Test.startTest();
            Id jobId = RegressionTestScheduler.scheduleMonthly();
            Test.stopTest();

            System.assertNotEquals(null, jobId,
                'scheduleMonthly should return a non-null job ID');

            List<CronTrigger> jobs = [
                SELECT CronJobDetail.Name
                FROM CronTrigger
                WHERE Id = :jobId
            ];
            System.assert(jobs[0].CronJobDetail.Name.contains('Monthly'),
                'Job name should contain Monthly, got: ' + jobs[0].CronJobDetail.Name);

            System.abortJob(jobId);
        }
    }

    @IsTest
    static void testScheduleCustom() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Test.startTest();
            Id jobId = RegressionTestScheduler.scheduleCustom('0 0 6 * * ?');
            Test.stopTest();

            System.assertNotEquals(null, jobId,
                'scheduleCustom should return a non-null job ID');

            List<CronTrigger> jobs = [
                SELECT CronJobDetail.Name
                FROM CronTrigger
                WHERE Id = :jobId
            ];
            System.assert(jobs[0].CronJobDetail.Name.contains('Custom'),
                'Job name should contain Custom, got: ' + jobs[0].CronJobDetail.Name);

            System.abortJob(jobId);
        }
    }

    @IsTest
    static void testScheduleCustomBlankCron() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Test.startTest();
            try {
                RegressionTestScheduler.scheduleCustom('');
                System.assert(false, 'Expected IllegalArgumentException for blank cron');
            } catch (IllegalArgumentException e) {
                System.assert(e.getMessage().contains('blank'),
                    'Exception should mention blank cron, got: ' + e.getMessage());
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void testUnschedule() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            // Schedule a job first
            Id jobId = RegressionTestScheduler.scheduleDaily();
            System.assertNotEquals(null, jobId, 'Should have a scheduled job to unschedule');

            Test.startTest();
            RegressionTestScheduler.unschedule();
            Test.stopTest();

            // Verify ForceGuard jobs are removed
            Integer remainingJobs = [
                SELECT COUNT()
                FROM CronTrigger
                WHERE CronJobDetail.Name LIKE 'ForceGuard%'
            ];
            System.assertEquals(0, remainingJobs,
                'All ForceGuard jobs should be removed after unschedule');
        }
    }

    @IsTest
    static void testIsScheduled() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            // Before scheduling
            System.assertEquals(false, RegressionTestScheduler.isScheduled(),
                'Should return false when no jobs are scheduled');

            // Schedule a job
            Id jobId = RegressionTestScheduler.scheduleDaily();

            Test.startTest();
            Boolean scheduled = RegressionTestScheduler.isScheduled();
            Test.stopTest();

            System.assertEquals(true, scheduled,
                'Should return true when a ForceGuard job is scheduled');

            // Cleanup
            System.abortJob(jobId);
        }
    }

    @IsTest
    static void testNoActiveSuites() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            // Deactivate all suites
            List<Regression_Test_Suite__c> suites = [
                SELECT Id, Is_Active__c FROM Regression_Test_Suite__c
            ];
            for (Regression_Test_Suite__c s : suites) {
                s.Is_Active__c = false;
            }
            update suites;

            Test.startTest();
            RegressionTestScheduler scheduler = new RegressionTestScheduler();
            scheduler.execute(null);
            Test.stopTest();

            // Verify no new runs were created with Scheduled trigger
            List<Regression_Test_Run__c> runs = [
                SELECT Id
                FROM Regression_Test_Run__c
                WHERE Triggered_By__c = 'Scheduled'
            ];
            System.assertEquals(0, runs.size(),
                'No runs should be created when no active suites exist');
        }
    }
}
