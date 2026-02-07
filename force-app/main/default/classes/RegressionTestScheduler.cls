/**
 * RegressionTestScheduler - Schedulable class for automated ForceGuard regression test runs.
 * Queries all active test suites and enqueues a RegressionTestRunner batch for each.
 *
 * Usage:
 *   RegressionTestScheduler.scheduleDaily();   // Every day at 2 AM
 *   RegressionTestScheduler.scheduleWeekly();  // Every Monday at 2 AM
 *   RegressionTestScheduler.scheduleMonthly(); // First of month at 2 AM
 *   RegressionTestScheduler.scheduleCustom('0 0 6 * * ?'); // Custom cron
 *   RegressionTestScheduler.unschedule();      // Remove all ForceGuard jobs
 */
public with sharing class RegressionTestScheduler implements Schedulable {

    private static final String JOB_PREFIX = 'ForceGuard';

    /**
     * Schedulable execute - enqueues a batch run for each active suite.
     */
    public void execute(SchedulableContext sc) {
        List<Regression_Test_Suite__c> suites = [
            SELECT Id, Product_Name__c
            FROM Regression_Test_Suite__c
            WHERE Is_Active__c = true
        ];

        if (suites.isEmpty()) {
            return;
        }

        for (Regression_Test_Suite__c suite : suites) {
            try {
                RegressionTestRunner runner = new RegressionTestRunner(suite.Id, 'Scheduled');
                Database.executeBatch(runner, 50);
            } catch (Exception e) {
                // Log error but continue processing remaining suites
                System.debug(LoggingLevel.ERROR,
                    'Failed to start batch for suite ' + suite.Product_Name__c +
                    ' (' + suite.Id + '): ' + e.getMessage()
                );
            }
        }
    }

    /**
     * Schedules daily execution at 2:00 AM.
     * @return The scheduled CronTrigger Id
     */
    public static Id scheduleDaily() {
        return System.schedule(
            JOB_PREFIX + ' Daily',
            '0 0 2 * * ?',
            new RegressionTestScheduler()
        );
    }

    /**
     * Schedules weekly execution on Monday at 2:00 AM.
     * @return The scheduled CronTrigger Id
     */
    public static Id scheduleWeekly() {
        return System.schedule(
            JOB_PREFIX + ' Weekly',
            '0 0 2 ? * MON',
            new RegressionTestScheduler()
        );
    }

    /**
     * Schedules monthly execution on the 1st at 2:00 AM.
     * @return The scheduled CronTrigger Id
     */
    public static Id scheduleMonthly() {
        return System.schedule(
            JOB_PREFIX + ' Monthly',
            '0 0 2 1 * ?',
            new RegressionTestScheduler()
        );
    }

    /**
     * Schedules with a custom cron expression.
     * @param cronExpression Valid Salesforce cron expression
     * @return The scheduled CronTrigger Id
     */
    public static Id scheduleCustom(String cronExpression) {
        if (String.isBlank(cronExpression)) {
            throw new IllegalArgumentException('Cron expression cannot be blank.');
        }
        return System.schedule(
            JOB_PREFIX + ' Custom',
            cronExpression,
            new RegressionTestScheduler()
        );
    }

    /**
     * Removes all scheduled ForceGuard jobs.
     */
    public static void unschedule() {
        List<CronTrigger> jobs = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :JOB_PREFIX + '%'
        ];
        for (CronTrigger job : jobs) {
            System.abortJob(job.Id);
        }
    }

    /**
     * Checks if any ForceGuard scheduled job exists.
     * @return true if at least one ForceGuard job is scheduled
     */
    public static Boolean isScheduled() {
        Integer jobCount = [
            SELECT COUNT()
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :JOB_PREFIX + '%'
        ];
        return jobCount > 0;
    }
}
