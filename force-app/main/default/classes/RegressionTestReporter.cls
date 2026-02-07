/**
 * RegressionTestReporter - Report generation engine for ForceGuard regression testing.
 * Provides run summaries, regression detection, CSV export, coverage snapshots, and trend data.
 */
public with sharing class RegressionTestReporter {

    // Inner class for structured run summary
    public class RunSummary {
        @AuraEnabled public Id runId;
        @AuraEnabled public String suiteName;
        @AuraEnabled public DateTime runDate;
        @AuraEnabled public String status;
        @AuraEnabled public Integer totalTests;
        @AuraEnabled public Integer passed;
        @AuraEnabled public Integer failed;
        @AuraEnabled public Integer skipped;
        @AuraEnabled public Decimal passRate;
        @AuraEnabled public Decimal codeCoverage;
        @AuraEnabled public Integer regressionCount;
        @AuraEnabled public Decimal durationSeconds;
        @AuraEnabled public Map<String, LayerSummary> layerBreakdown;
        @AuraEnabled public List<FailureDetail> failures;
    }

    public class LayerSummary {
        @AuraEnabled public String layerName;
        @AuraEnabled public String status;
        @AuraEnabled public Integer passed;
        @AuraEnabled public Integer failed;
        @AuraEnabled public Integer skipped;
    }

    public class FailureDetail {
        @AuraEnabled public String testCaseTitle;
        @AuraEnabled public String layerName;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public Boolean isRegression;
    }

    /**
     * Generate complete run summary with per-layer breakdown.
     * @param testRunId The Regression_Test_Run__c Id
     * @return RunSummary with layer breakdown and failure details
     */
    public static RunSummary generateRunSummary(Id testRunId) {
        RunSummary summary = new RunSummary();

        Regression_Test_Run__c run = [
            SELECT Id, Test_Suite__c, Test_Suite__r.Product_Name__c, Run_Date__c,
                   Status__c, Total_Tests__c, Passed__c, Failed__c, Skipped__c,
                   Pass_Rate__c, Code_Coverage__c, Regression_Count__c, Duration_Seconds__c,
                   Layer_1_Status__c, Layer_2_Status__c, Layer_3_Status__c, Layer_4_Status__c
            FROM Regression_Test_Run__c
            WHERE Id = :testRunId
            WITH USER_MODE
        ];

        summary.runId = run.Id;
        summary.suiteName = run.Test_Suite__r.Product_Name__c;
        summary.runDate = run.Run_Date__c;
        summary.status = run.Status__c;
        summary.totalTests = run.Total_Tests__c != null ? run.Total_Tests__c.intValue() : 0;
        summary.passed = run.Passed__c != null ? run.Passed__c.intValue() : 0;
        summary.failed = run.Failed__c != null ? run.Failed__c.intValue() : 0;
        summary.skipped = run.Skipped__c != null ? run.Skipped__c.intValue() : 0;
        summary.passRate = run.Pass_Rate__c;
        summary.codeCoverage = run.Code_Coverage__c;
        summary.regressionCount = run.Regression_Count__c != null ? run.Regression_Count__c.intValue() : 0;
        summary.durationSeconds = run.Duration_Seconds__c;

        // Build layer breakdown using AggregateResult
        summary.layerBreakdown = new Map<String, LayerSummary>();
        for (AggregateResult ar : [
            SELECT Layer__c layer, Status__c status, COUNT(Id) cnt
            FROM Regression_Test_Result__c
            WHERE Test_Run__c = :testRunId
            WITH USER_MODE
            GROUP BY Layer__c, Status__c
        ]) {
            String layerName = (String) ar.get('layer');
            String resultStatus = (String) ar.get('status');
            Integer count = (Integer) ar.get('cnt');

            if (!summary.layerBreakdown.containsKey(layerName)) {
                LayerSummary ls = new LayerSummary();
                ls.layerName = layerName;
                ls.status = 'Passed';
                ls.passed = 0;
                ls.failed = 0;
                ls.skipped = 0;
                summary.layerBreakdown.put(layerName, ls);
            }

            LayerSummary ls = summary.layerBreakdown.get(layerName);
            if (resultStatus == 'Passed') {
                ls.passed += count;
            } else if (resultStatus == 'Failed' || resultStatus == 'Error') {
                ls.failed += count;
                ls.status = 'Failed';
            } else if (resultStatus == 'Skipped') {
                ls.skipped += count;
            }
        }

        // Get failure details
        summary.failures = new List<FailureDetail>();
        for (Regression_Test_Result__c result : [
            SELECT Test_Case__r.Title__c, Layer__c, Error_Message__c, Is_Regression__c
            FROM Regression_Test_Result__c
            WHERE Test_Run__c = :testRunId AND (Status__c = 'Failed' OR Status__c = 'Error')
            WITH USER_MODE
            ORDER BY Layer__c, Test_Case__r.Title__c
        ]) {
            FailureDetail fd = new FailureDetail();
            fd.testCaseTitle = result.Test_Case__r.Title__c;
            fd.layerName = result.Layer__c;
            fd.errorMessage = result.Error_Message__c;
            fd.isRegression = result.Is_Regression__c;
            summary.failures.add(fd);
        }

        return summary;
    }

    /**
     * Detect regressions by comparing with previous run.
     * A regression = test that passed in previous run but fails in current run.
     * @param testRunId The current Regression_Test_Run__c Id
     * @return List of result records flagged as regressions
     */
    public static List<Regression_Test_Result__c> detectRegressions(Id testRunId) {
        Regression_Test_Run__c currentRun = [
            SELECT Test_Suite__c
            FROM Regression_Test_Run__c
            WHERE Id = :testRunId
            WITH USER_MODE
        ];

        // Find the previous run for this suite (most recent before current)
        List<Regression_Test_Run__c> previousRuns = [
            SELECT Id
            FROM Regression_Test_Run__c
            WHERE Test_Suite__c = :currentRun.Test_Suite__c
              AND Id != :testRunId
              AND Status__c IN ('Completed', 'Failed')
            WITH USER_MODE
            ORDER BY Run_Date__c DESC
            LIMIT 1
        ];

        if (previousRuns.isEmpty()) {
            return new List<Regression_Test_Result__c>();
        }

        Id previousRunId = previousRuns[0].Id;

        // Build map of previous results by test case ID
        Map<Id, String> previousStatusByCase = new Map<Id, String>();
        for (Regression_Test_Result__c prevResult : [
            SELECT Test_Case__c, Status__c
            FROM Regression_Test_Result__c
            WHERE Test_Run__c = :previousRunId
            WITH USER_MODE
        ]) {
            previousStatusByCase.put(prevResult.Test_Case__c, prevResult.Status__c);
        }

        // Find current failures that were previously passing
        List<Regression_Test_Result__c> regressions = new List<Regression_Test_Result__c>();
        List<Regression_Test_Result__c> toUpdate = new List<Regression_Test_Result__c>();

        for (Regression_Test_Result__c currentResult : [
            SELECT Id, Test_Case__c, Status__c
            FROM Regression_Test_Result__c
            WHERE Test_Run__c = :testRunId AND (Status__c = 'Failed' OR Status__c = 'Error')
            WITH USER_MODE
        ]) {
            String previousStatus = previousStatusByCase.get(currentResult.Test_Case__c);
            if (previousStatus == 'Passed') {
                currentResult.Is_Regression__c = true;
                currentResult.Previous_Status__c = previousStatus;
                toUpdate.add(currentResult);
                regressions.add(currentResult);
            }
        }

        if (!toUpdate.isEmpty()) {
            SObjectAccessDecision decision = Security.stripInaccessible(
                AccessType.UPDATABLE, toUpdate
            );
            update as user decision.getRecords();

            // Update regression count on the run
            List<Regression_Test_Run__c> runUpdate = new List<Regression_Test_Run__c>{
                new Regression_Test_Run__c(
                    Id = testRunId,
                    Regression_Count__c = regressions.size()
                )
            };
            SObjectAccessDecision runDecision = Security.stripInaccessible(
                AccessType.UPDATABLE, runUpdate
            );
            update as user runDecision.getRecords();
        }

        return regressions;
    }

    /**
     * Generate CSV export of all results for a run.
     * @param testRunId The Regression_Test_Run__c Id
     * @return CSV string with header row and result rows
     */
    public static String generateCsvExport(Id testRunId) {
        String csv = 'Test Case,Layer,Category,Status,Error Message,Duration (ms),Is Regression\n';

        for (Regression_Test_Result__c result : [
            SELECT Test_Case__r.Title__c, Layer__c, Test_Case__r.Category__c,
                   Status__c, Error_Message__c, Duration_Ms__c, Is_Regression__c
            FROM Regression_Test_Result__c
            WHERE Test_Run__c = :testRunId
            WITH USER_MODE
            ORDER BY Layer__c, Test_Case__r.Title__c
        ]) {
            csv += '"' + escapeCsv(result.Test_Case__r.Title__c) + '",';
            csv += '"' + escapeCsv(result.Layer__c) + '",';
            csv += '"' + escapeCsv(result.Test_Case__r.Category__c) + '",';
            csv += '"' + escapeCsv(result.Status__c) + '",';
            csv += '"' + escapeCsv(result.Error_Message__c) + '",';
            csv += String.valueOf(result.Duration_Ms__c != null ? result.Duration_Ms__c : 0) + ',';
            csv += String.valueOf(result.Is_Regression__c) + '\n';
        }

        return csv;
    }

    /**
     * Create coverage snapshot record for the suite.
     * @param testRunId The Regression_Test_Run__c Id
     * @return The newly created Test_Coverage_Snapshot__c record
     */
    public static Test_Coverage_Snapshot__c createCoverageSnapshot(Id testRunId) {
        Regression_Test_Run__c run = [
            SELECT Test_Suite__c, Code_Coverage__c
            FROM Regression_Test_Run__c
            WHERE Id = :testRunId
            WITH USER_MODE
        ];

        Integer totalCases = [
            SELECT COUNT()
            FROM Regression_Test_Case__c
            WHERE Test_Suite__c = :run.Test_Suite__c AND Is_Active__c = true
            WITH USER_MODE
        ];
        Integer testedCases = [
            SELECT COUNT()
            FROM Regression_Test_Result__c
            WHERE Test_Run__c = :testRunId AND Status__c != 'Skipped'
            WITH USER_MODE
        ];

        Test_Coverage_Snapshot__c snapshot = new Test_Coverage_Snapshot__c(
            Snapshot_Date__c = Date.today(),
            Test_Suite__c = run.Test_Suite__c,
            Apex_Coverage__c = run.Code_Coverage__c,
            Total_Metadata_Items__c = totalCases,
            Tested_Metadata_Items__c = testedCases
        );

        SObjectAccessDecision decision = Security.stripInaccessible(
            AccessType.CREATABLE, new List<Test_Coverage_Snapshot__c>{ snapshot }
        );
        insert as user decision.getRecords();

        // Return the inserted record with its Id
        snapshot.Id = decision.getRecords()[0].Id;
        return snapshot;
    }

    /**
     * Get trend data (pass rates) for sparkline chart.
     * Returns runs in chronological order (oldest first).
     * @param suiteId Optional suite filter (null = all suites)
     * @param runCount Number of recent runs to return (default 10)
     * @return List of maps with runId, runName, runDate, passRate, totalTests, failures
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getTrendData(Id suiteId, Integer runCount) {
        if (runCount == null || runCount <= 0) {
            runCount = 10;
        }

        List<Regression_Test_Run__c> runs;

        if (suiteId != null) {
            runs = [
                SELECT Id, Name, Run_Date__c, Pass_Rate__c, Total_Tests__c, Failed__c
                FROM Regression_Test_Run__c
                WHERE Status__c IN ('Completed', 'Failed')
                  AND Test_Suite__c = :suiteId
                WITH USER_MODE
                ORDER BY Run_Date__c DESC
                LIMIT :runCount
            ];
        } else {
            runs = [
                SELECT Id, Name, Run_Date__c, Pass_Rate__c, Total_Tests__c, Failed__c
                FROM Regression_Test_Run__c
                WHERE Status__c IN ('Completed', 'Failed')
                WITH USER_MODE
                ORDER BY Run_Date__c DESC
                LIMIT :runCount
            ];
        }

        // Reverse to get chronological order (oldest first)
        List<Map<String, Object>> trendData = new List<Map<String, Object>>();
        for (Integer i = runs.size() - 1; i >= 0; i--) {
            Map<String, Object> point = new Map<String, Object>();
            point.put('runId', runs[i].Id);
            point.put('runName', runs[i].Name);
            point.put('runDate', runs[i].Run_Date__c);
            point.put('passRate', runs[i].Pass_Rate__c);
            point.put('totalTests', runs[i].Total_Tests__c);
            point.put('failures', runs[i].Failed__c);
            trendData.add(point);
        }

        return trendData;
    }

    /**
     * Escape double quotes in CSV values and handle nulls.
     */
    private static String escapeCsv(String value) {
        if (value == null) {
            return '';
        }
        return value.replace('"', '""');
    }
}
