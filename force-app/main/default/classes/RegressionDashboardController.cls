/**
 * RegressionDashboardController - Apex controller for the regressionTestDashboard LWC.
 * Provides summary statistics, suite overviews, recent runs, and delegates to
 * RegressionTestRunner and RegressionTestScheduler for execution and scheduling.
 */
public with sharing class RegressionDashboardController {

    /**
     * Summary data for the dashboard header cards.
     */
    public class DashboardSummary {
        @AuraEnabled public Integer totalSuites;
        @AuraEnabled public Integer totalTestCases;
        @AuraEnabled public Decimal overallPassRate;
        @AuraEnabled public Integer totalFailures;
        @AuraEnabled public DateTime lastRunDate;
    }

    /**
     * Overview data for each active suite displayed in the suite list.
     */
    public class SuiteOverview {
        @AuraEnabled public Id suiteId;
        @AuraEnabled public String suiteName;
        @AuraEnabled public String productName;
        @AuraEnabled public String version;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public DateTime lastRunDate;
        @AuraEnabled public String lastRunStatus;
        @AuraEnabled public Integer testCaseCount;
        @AuraEnabled public Decimal passRate;
    }

    /**
     * Aggregates dashboard summary across all active suites.
     * Counts suites, test cases, computes overall pass rate from latest runs.
     */
    @AuraEnabled(cacheable=true)
    public static DashboardSummary getDashboardSummary() {
        try {
            DashboardSummary summary = new DashboardSummary();

            // Count active suites
            List<Regression_Test_Suite__c> activeSuites = [
                SELECT Id, Last_Run_Date__c
                FROM Regression_Test_Suite__c
                WHERE Is_Active__c = true
                WITH USER_MODE
            ];
            summary.totalSuites = activeSuites.size();

            // Collect suite IDs and find latest run date
            Set<Id> suiteIds = new Set<Id>();
            DateTime latestRunDate = null;
            for (Regression_Test_Suite__c suite : activeSuites) {
                suiteIds.add(suite.Id);
                if (suite.Last_Run_Date__c != null &&
                    (latestRunDate == null || suite.Last_Run_Date__c > latestRunDate)) {
                    latestRunDate = suite.Last_Run_Date__c;
                }
            }
            summary.lastRunDate = latestRunDate;

            // Count total test cases across active suites
            summary.totalTestCases = suiteIds.isEmpty() ? 0 : [
                SELECT COUNT()
                FROM Regression_Test_Case__c
                WHERE Test_Suite__c IN :suiteIds
                  AND Is_Active__c = true
                WITH USER_MODE
            ];

            // Get the latest completed run per suite using a single query
            // Order by Suite + Date DESC, then pick the first per suite in Apex
            Decimal totalPassed = 0;
            Decimal totalTests = 0;
            Integer totalFailures = 0;
            Set<Id> processedSuites = new Set<Id>();

            if (!suiteIds.isEmpty()) {
                for (Regression_Test_Run__c run : [
                    SELECT Test_Suite__c, Passed__c, Total_Tests__c, Failed__c
                    FROM Regression_Test_Run__c
                    WHERE Test_Suite__c IN :suiteIds
                      AND Status__c IN ('Completed', 'Failed')
                    WITH USER_MODE
                    ORDER BY Test_Suite__c, Run_Date__c DESC
                ]) {
                    // Only take the first (most recent) run per suite
                    if (processedSuites.contains(run.Test_Suite__c)) {
                        continue;
                    }
                    processedSuites.add(run.Test_Suite__c);

                    if (run.Total_Tests__c != null && run.Total_Tests__c > 0) {
                        totalPassed += run.Passed__c != null ? run.Passed__c : 0;
                        totalTests += run.Total_Tests__c;
                    }
                    totalFailures += run.Failed__c != null ? run.Failed__c.intValue() : 0;
                }
            }

            summary.overallPassRate = totalTests > 0
                ? (totalPassed / totalTests * 100).setScale(2)
                : 0;
            summary.totalFailures = totalFailures;

            return summary;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Returns overview data for each active suite including latest run stats.
     */
    @AuraEnabled(cacheable=true)
    public static List<SuiteOverview> getSuiteOverviews() {
        try {
            List<SuiteOverview> overviews = new List<SuiteOverview>();

            List<Regression_Test_Suite__c> suites = [
                SELECT Id, Name, Product_Name__c, Version__c, Is_Active__c,
                       Last_Run_Date__c, Last_Run_Status__c
                FROM Regression_Test_Suite__c
                WHERE Is_Active__c = true
                WITH USER_MODE
                ORDER BY Product_Name__c
            ];

            // Collect suite IDs
            Set<Id> suiteIds = new Set<Id>();
            for (Regression_Test_Suite__c suite : suites) {
                suiteIds.add(suite.Id);
            }

            if (suiteIds.isEmpty()) {
                return overviews;
            }

            // Count test cases per suite in a single aggregate query
            Map<Id, Integer> caseCountBySuite = new Map<Id, Integer>();
            for (AggregateResult ar : [
                SELECT Test_Suite__c suiteId, COUNT(Id) cnt
                FROM Regression_Test_Case__c
                WHERE Test_Suite__c IN :suiteIds
                  AND Is_Active__c = true
                WITH USER_MODE
                GROUP BY Test_Suite__c
            ]) {
                caseCountBySuite.put(
                    (Id) ar.get('suiteId'),
                    (Integer) ar.get('cnt')
                );
            }

            // Get latest pass rate per suite in a single query (no SOQL in loop)
            Map<Id, Decimal> passRateBySuite = new Map<Id, Decimal>();
            Set<Id> processedSuites = new Set<Id>();
            for (Regression_Test_Run__c run : [
                SELECT Test_Suite__c, Pass_Rate__c
                FROM Regression_Test_Run__c
                WHERE Test_Suite__c IN :suiteIds
                  AND Status__c IN ('Completed', 'Failed')
                WITH USER_MODE
                ORDER BY Test_Suite__c, Run_Date__c DESC
            ]) {
                if (processedSuites.contains(run.Test_Suite__c)) {
                    continue;
                }
                processedSuites.add(run.Test_Suite__c);
                if (run.Pass_Rate__c != null) {
                    passRateBySuite.put(run.Test_Suite__c, run.Pass_Rate__c * 100);
                }
            }

            for (Regression_Test_Suite__c suite : suites) {
                SuiteOverview ov = new SuiteOverview();
                ov.suiteId = suite.Id;
                ov.suiteName = suite.Name;
                ov.productName = suite.Product_Name__c;
                ov.version = suite.Version__c;
                ov.isActive = suite.Is_Active__c;
                ov.lastRunDate = suite.Last_Run_Date__c;
                ov.lastRunStatus = suite.Last_Run_Status__c;
                ov.testCaseCount = caseCountBySuite.containsKey(suite.Id)
                    ? caseCountBySuite.get(suite.Id) : 0;
                ov.passRate = passRateBySuite.containsKey(suite.Id)
                    ? passRateBySuite.get(suite.Id) : null;
                overviews.add(ov);
            }

            return overviews;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Returns recent test runs across all suites, ordered by date descending.
     * @param runLimit Max number of runs to return (default 10)
     */
    @AuraEnabled(cacheable=true)
    public static List<Regression_Test_Run__c> getRecentRuns(Integer runLimit) {
        try {
            if (runLimit == null || runLimit <= 0) {
                runLimit = 10;
            }
            return [
                SELECT Id, Name, Run_Date__c, Status__c, Total_Tests__c,
                       Passed__c, Failed__c, Pass_Rate__c, Duration_Seconds__c,
                       Test_Suite__r.Name, Test_Suite__r.Product_Name__c,
                       Layer_1_Status__c, Layer_2_Status__c,
                       Layer_3_Status__c, Layer_4_Status__c
                FROM Regression_Test_Run__c
                WHERE Status__c IN ('Completed', 'Failed', 'Running')
                WITH USER_MODE
                ORDER BY Run_Date__c DESC
                LIMIT :runLimit
            ];
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Starts a regression test run for the specified suite.
     * Delegates to RegressionTestRunner.runSuite().
     * @param suiteId The suite to run
     * @return AsyncApexJob Id for polling
     */
    @AuraEnabled
    public static Id runSuite(Id suiteId) {
        try {
            return RegressionTestRunner.runSuite(suiteId);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Returns the status of a batch job for polling from LWC.
     * @param jobId The AsyncApexJob Id
     * @return Map with status, progress, errors
     */
    @AuraEnabled
    public static Map<String, Object> getBatchJobStatus(Id jobId) {
        try {
            Map<String, Object> result = new Map<String, Object>();
            if (jobId == null) {
                result.put('status', 'Unknown');
                result.put('progress', 0);
                result.put('errors', 0);
                return result;
            }

            List<AsyncApexJob> jobs = [
                SELECT Status, JobItemsProcessed, TotalJobItems, NumberOfErrors
                FROM AsyncApexJob
                WHERE Id = :jobId
                WITH USER_MODE
                LIMIT 1
            ];

            if (jobs.isEmpty()) {
                result.put('status', 'Not Found');
                result.put('progress', 0);
                result.put('errors', 0);
            } else {
                AsyncApexJob job = jobs[0];
                result.put('status', job.Status);
                Integer total = job.TotalJobItems != null ? job.TotalJobItems : 0;
                Integer processed = job.JobItemsProcessed != null ? job.JobItemsProcessed : 0;
                Integer progress = total > 0
                    ? (Integer) Math.floor((Decimal) processed / total * 100)
                    : 0;
                result.put('progress', progress);
                result.put('errors', job.NumberOfErrors != null ? job.NumberOfErrors : 0);
            }

            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Schedules automated test runs at the specified frequency.
     * @param frequency One of: daily, weekly, monthly
     * @param suiteId Reserved for future per-suite scheduling (currently unused)
     */
    @AuraEnabled
    public static void scheduleRun(String frequency, Id suiteId) {
        try {
            if (String.isBlank(frequency)) {
                throw new AuraHandledException('Frequency is required.');
            }

            // Unschedule existing jobs first to prevent duplicates
            RegressionTestScheduler.unschedule();

            switch on frequency.toLowerCase() {
                when 'daily' {
                    RegressionTestScheduler.scheduleDaily();
                }
                when 'weekly' {
                    RegressionTestScheduler.scheduleWeekly();
                }
                when 'monthly' {
                    RegressionTestScheduler.scheduleMonthly();
                }
                when else {
                    throw new AuraHandledException('Invalid frequency: ' + frequency +
                        '. Use daily, weekly, or monthly.');
                }
            }
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}
