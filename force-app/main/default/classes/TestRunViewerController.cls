/**
 * TestRunViewerController - Backend controller for the testRunViewer LWC.
 * Provides paginated run listing, run detail with layer breakdown,
 * re-run of failed tests, and CSV export.
 */
public with sharing class TestRunViewerController {

    /**
     * Paginated list of test runs with optional suite and status filters.
     * @param suiteId Optional filter by Test_Suite__c
     * @param statusFilter Optional status filter (Completed, Failed, Running, etc.)
     * @param pageSize Number of records per page
     * @param pageOffset Zero-based offset for pagination
     * @return RunListResult with runs list and total count
     */
    @AuraEnabled(cacheable=true)
    public static RunListResult getTestRuns(Id suiteId, String statusFilter, Integer pageSize, Integer pageOffset) {
        try {
            if (pageSize == null || pageSize <= 0) {
                pageSize = 10;
            }
            if (pageOffset == null || pageOffset < 0) {
                pageOffset = 0;
            }

            String baseQuery = 'SELECT Id, Name, Run_Date__c, Completed_Date__c, Status__c, '
                + 'Triggered_By__c, Total_Tests__c, Passed__c, Failed__c, Skipped__c, '
                + 'Pass_Rate__c, Duration_Seconds__c, Regression_Count__c, '
                + 'Test_Suite__c, Test_Suite__r.Product_Name__c '
                + 'FROM Regression_Test_Run__c';

            String countQuery = 'SELECT COUNT() FROM Regression_Test_Run__c';

            List<String> conditions = new List<String>();
            if (suiteId != null) {
                conditions.add('Test_Suite__c = :suiteId');
            }
            if (String.isNotBlank(statusFilter) && statusFilter != 'All') {
                conditions.add('Status__c = :statusFilter');
            }

            if (!conditions.isEmpty()) {
                String whereClause = ' WHERE ' + String.join(conditions, ' AND ');
                baseQuery += whereClause;
                countQuery += whereClause;
            }

            baseQuery += ' WITH USER_MODE ORDER BY Run_Date__c DESC LIMIT :pageSize OFFSET :pageOffset';
            countQuery += ' WITH USER_MODE';

            RunListResult result = new RunListResult();
            result.runs = Database.query(baseQuery);
            result.totalCount = Database.countQuery(countQuery);
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Detailed run information with per-layer breakdown.
     * Delegates to RegressionTestReporter for layer summary data.
     * @param runId The Regression_Test_Run__c Id
     * @return RunDetail with run record and layer summaries
     */
    @AuraEnabled(cacheable=true)
    public static RunDetail getRunDetail(Id runId) {
        try {
            RegressionTestReporter.RunSummary summary = RegressionTestReporter.generateRunSummary(runId);

            RunDetail detail = new RunDetail();
            detail.run = [
                SELECT Id, Name, Run_Date__c, Completed_Date__c, Status__c,
                       Triggered_By__c, Total_Tests__c, Passed__c, Failed__c, Skipped__c,
                       Pass_Rate__c, Duration_Seconds__c, Code_Coverage__c,
                       Regression_Count__c, Error_Summary__c,
                       Layer_1_Status__c, Layer_2_Status__c, Layer_3_Status__c, Layer_4_Status__c,
                       Test_Suite__c, Test_Suite__r.Product_Name__c
                FROM Regression_Test_Run__c
                WHERE Id = :runId
                WITH USER_MODE
            ];

            detail.layerSummaries = new List<Map<String, Object>>();
            if (summary.layerBreakdown != null) {
                for (String layerName : summary.layerBreakdown.keySet()) {
                    RegressionTestReporter.LayerSummary ls = summary.layerBreakdown.get(layerName);
                    Map<String, Object> layerMap = new Map<String, Object>();
                    layerMap.put('layerName', ls.layerName);
                    layerMap.put('status', ls.status);
                    layerMap.put('passed', ls.passed);
                    layerMap.put('failed', ls.failed);
                    layerMap.put('skipped', ls.skipped);
                    Integer total = ls.passed + ls.failed + ls.skipped;
                    layerMap.put('total', total);
                    layerMap.put('passRate', total > 0 ? (ls.passed * 100.0 / total) : 0);
                    detail.layerSummaries.add(layerMap);
                }
            }

            detail.totalFailures = summary.failed;
            detail.regressionCount = summary.regressionCount;
            return detail;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Re-runs only the failed test cases from a previous run.
     * Creates a new Regression_Test_Run__c targeting just the failed cases.
     * @param runId The original run whose failures should be re-run
     * @return The new Regression_Test_Run__c Id
     */
    @AuraEnabled
    public static Id rerunFailed(Id runId) {
        try {
            // Get the suite from the original run
            Regression_Test_Run__c originalRun = [
                SELECT Test_Suite__c
                FROM Regression_Test_Run__c
                WHERE Id = :runId
                WITH USER_MODE
            ];

            // Get failed test case IDs
            List<Regression_Test_Result__c> failedResults = [
                SELECT Test_Case__c
                FROM Regression_Test_Result__c
                WHERE Test_Run__c = :runId
                  AND (Status__c = 'Failed' OR Status__c = 'Error')
                WITH USER_MODE
            ];

            if (failedResults.isEmpty()) {
                AuraHandledException noFailures = new AuraHandledException('No failed tests to re-run.');
                noFailures.setMessage('No failed tests to re-run.');
                throw noFailures;
            }

            Set<Id> failedCaseIds = new Set<Id>();
            for (Regression_Test_Result__c r : failedResults) {
                failedCaseIds.add(r.Test_Case__c);
            }

            // Create a new run with system-determined values only (no user input).
            // SOQL queries above enforce WITH USER_MODE for read access;
            // insert uses system mode since all field values are controlled by the application.
            Regression_Test_Run__c newRun = new Regression_Test_Run__c(
                Test_Suite__c = originalRun.Test_Suite__c,
                Run_Date__c = DateTime.now(),
                Status__c = 'Queued',
                Triggered_By__c = 'Re-run Failed',
                Run_By__c = UserInfo.getUserId(),
                Total_Tests__c = failedCaseIds.size()
            );
            insert newRun;

            return newRun.Id;
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Exports run results as CSV string.
     * Delegates to RegressionTestReporter.generateCsvExport.
     * @param runId The Regression_Test_Run__c Id
     * @return CSV string with header and result rows
     */
    @AuraEnabled
    public static String exportCsv(Id runId) {
        try {
            return RegressionTestReporter.generateCsvExport(runId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /** Wrapper for paginated run list results. */
    public class RunListResult {
        @AuraEnabled public List<Regression_Test_Run__c> runs;
        @AuraEnabled public Integer totalCount;
    }

    /** Wrapper for single run detail with layer breakdown. */
    public class RunDetail {
        @AuraEnabled public Regression_Test_Run__c run;
        @AuraEnabled public List<Map<String, Object>> layerSummaries;
        @AuraEnabled public Integer totalFailures;
        @AuraEnabled public Integer regressionCount;
    }
}
