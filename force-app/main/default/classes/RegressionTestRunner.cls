/**
 * RegressionTestRunner - Central orchestrator for ForceGuard regression test execution.
 * Implements Database.Batchable to process test cases in ordered layers:
 *   Layer 1 (Deployment) - blocking
 *   Layer 2 (Apex Test) - blocking
 *   Layer 3 (Data Scenario) - non-blocking
 *   Layer 4 (Static Analysis) - non-blocking
 *
 * If Layer 1 or 2 fails, all subsequent layers are skipped.
 */
public with sharing class RegressionTestRunner implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {

    private static final String STATUS_RUNNING = 'Running';
    private static final String STATUS_COMPLETED = 'Completed';
    private static final String STATUS_FAILED = 'Failed';
    private static final String STATUS_PASSED = 'Passed';
    private static final String STATUS_SKIPPED = 'Skipped';

    private static final String LAYER_DEPLOYMENT = 'Deployment';
    private static final String LAYER_APEX_TEST = 'Apex Test';
    private static final String LAYER_DATA_SCENARIO = 'Data Scenario';
    private static final String LAYER_STATIC_ANALYSIS = 'Static Analysis';

    private static final Map<String, Integer> LAYER_ORDER = new Map<String, Integer>{
        LAYER_DEPLOYMENT => 1,
        LAYER_APEX_TEST => 2,
        LAYER_DATA_SCENARIO => 3,
        LAYER_STATIC_ANALYSIS => 4
    };

    @TestVisible
    private Id suiteId;
    @TestVisible
    private Id runId;
    private Long startTime;

    private Integer totalPassed = 0;
    private Integer totalFailed = 0;
    private Integer totalSkipped = 0;

    private Boolean blockingLayerFailed = false;
    private Map<String, String> layerStatuses = new Map<String, String>();
    private List<String> errorMessages = new List<String>();

    /**
     * Constructor - creates a Run record with Manual trigger type.
     * @param suiteId The Regression_Test_Suite__c Id to run
     */
    public RegressionTestRunner(Id suiteId) {
        this(suiteId, 'Manual');
    }

    /**
     * Overloaded constructor accepting a trigger source.
     * @param suiteId The Regression_Test_Suite__c Id to run
     * @param triggeredBy How the run was triggered (Manual, Scheduled, CI CD, Pre-Deployment)
     */
    public RegressionTestRunner(Id suiteId, String triggeredBy) {
        this.suiteId = suiteId;
        this.startTime = System.currentTimeMillis();

        Regression_Test_Run__c run = new Regression_Test_Run__c(
            Test_Suite__c = suiteId,
            Run_Date__c = DateTime.now(),
            Status__c = STATUS_RUNNING,
            Triggered_By__c = triggeredBy,
            Run_By__c = UserInfo.getUserId()
        );
        insert run;
        this.runId = run.Id;

        // Mark suite as Running
        update new Regression_Test_Suite__c(
            Id = suiteId,
            Last_Run_Status__c = STATUS_RUNNING,
            Last_Run_Date__c = DateTime.now()
        );
    }

    /**
     * Queries active test cases for the suite, ordered by layer then execution order.
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Store the batch job ID on the Run record for LWC polling
        update new Regression_Test_Run__c(
            Id = runId,
            Batch_Job_Id__c = bc.getJobId()
        );

        return Database.getQueryLocator([
            SELECT Id, Title__c, Test_Layer__c, Category__c, Steps__c,
                   Expected_Result__c, Assertion_Type__c, Execution_Order__c,
                   Target_Object__c, Related_Metadata__c, Tags__c, Last_Result_Status__c
            FROM Regression_Test_Case__c
            WHERE Test_Suite__c = :suiteId
              AND Is_Active__c = true
            WITH SYSTEM_MODE
            ORDER BY Test_Layer__c, Execution_Order__c
        ]);
    }

    /**
     * Processes a batch of test cases. Groups by layer and executes each group.
     * If a blocking layer (1 or 2) fails, remaining cases in subsequent layers are skipped.
     */
    public void execute(Database.BatchableContext bc, List<Regression_Test_Case__c> scope) {
        // Group test cases by layer
        Map<String, List<Regression_Test_Case__c>> casesByLayer = new Map<String, List<Regression_Test_Case__c>>();
        for (Regression_Test_Case__c tc : scope) {
            String layer = tc.Test_Layer__c;
            if (!casesByLayer.containsKey(layer)) {
                casesByLayer.put(layer, new List<Regression_Test_Case__c>());
            }
            casesByLayer.get(layer).add(tc);
        }

        // Process layers in order (Deployment -> Apex Test -> Data Scenario -> Static Analysis)
        List<String> sortedLayers = sortLayerKeys(casesByLayer.keySet());

        List<Regression_Test_Result__c> allResults = new List<Regression_Test_Result__c>();

        for (String layer : sortedLayers) {
            List<Regression_Test_Case__c> layerCases = casesByLayer.get(layer);
            Integer layerNum = LAYER_ORDER.get(layer);
            Boolean isBlockingLayer = (layerNum != null && layerNum <= 2);

            if (blockingLayerFailed) {
                // Skip all cases in this layer
                for (Regression_Test_Case__c tc : layerCases) {
                    allResults.add(createSkippedResult(tc, layer));
                    totalSkipped++;
                }
                if (!layerStatuses.containsKey(layer)) {
                    layerStatuses.put(layer, STATUS_SKIPPED);
                }
                continue;
            }

            // Execute the layer via RegressionTestExecutor
            List<Regression_Test_Result__c> layerResults =
                RegressionTestExecutor.executeLayer(runId, layerCases, layerNum);

            // Analyze results for this layer
            Boolean layerHasFailure = false;
            for (Regression_Test_Result__c result : layerResults) {
                allResults.add(result);

                if (result.Status__c == STATUS_PASSED) {
                    totalPassed++;
                } else if (result.Status__c == STATUS_FAILED || result.Status__c == 'Error') {
                    totalFailed++;
                    layerHasFailure = true;
                    if (String.isNotBlank(result.Error_Message__c)) {
                        errorMessages.add(layer + ': ' + result.Error_Message__c);
                    }
                } else if (result.Status__c == STATUS_SKIPPED) {
                    totalSkipped++;
                }
            }

            // Determine layer status
            String layerStatus = layerHasFailure ? STATUS_FAILED : STATUS_PASSED;
            layerStatuses.put(layer, layerStatus);

            // If blocking layer failed, flag so subsequent layers are skipped
            if (isBlockingLayer && layerHasFailure) {
                blockingLayerFailed = true;
            }
        }

        // Bulk insert all results
        if (!allResults.isEmpty()) {
            insert allResults;
        }
    }

    /**
     * Finalizes the Run record with totals, duration, and overall status.
     * Updates the Suite's last run fields and triggers regression detection.
     */
    public void finish(Database.BatchableContext bc) {
        Decimal durationSeconds = (System.currentTimeMillis() - startTime) / 1000.0;
        Integer totalTests = totalPassed + totalFailed + totalSkipped;

        // Determine overall run status
        String overallStatus = (totalFailed > 0) ? STATUS_FAILED : STATUS_COMPLETED;

        // Build error summary (truncate to fit LongTextArea)
        String errorSummary = null;
        if (!errorMessages.isEmpty()) {
            errorSummary = String.join(errorMessages, '\n');
            if (errorSummary.length() > 32000) {
                errorSummary = errorSummary.substring(0, 31997) + '...';
            }
        }

        // Update Run record with final results
        Regression_Test_Run__c run = new Regression_Test_Run__c(
            Id = runId,
            Status__c = overallStatus,
            Completed_Date__c = DateTime.now(),
            Total_Tests__c = totalTests,
            Passed__c = totalPassed,
            Failed__c = totalFailed,
            Skipped__c = totalSkipped,
            Duration_Seconds__c = durationSeconds,
            Layer_1_Status__c = layerStatuses.get(LAYER_DEPLOYMENT),
            Layer_2_Status__c = layerStatuses.get(LAYER_APEX_TEST),
            Layer_3_Status__c = layerStatuses.get(LAYER_DATA_SCENARIO),
            Layer_4_Status__c = layerStatuses.get(LAYER_STATIC_ANALYSIS),
            Error_Summary__c = errorSummary
        );
        update run;

        // Update Suite with last run info
        String suiteStatus = (totalFailed > 0) ? STATUS_FAILED : STATUS_PASSED;
        update new Regression_Test_Suite__c(
            Id = suiteId,
            Last_Run_Date__c = DateTime.now(),
            Last_Run_Status__c = suiteStatus
        );

        // Detect regressions (call Reporter if it exists)
        try {
            RegressionTestReporter.detectRegressions(runId);
        } catch (Exception e) {
            // Reporter may not be deployed yet; log but do not fail the run
            System.debug(LoggingLevel.WARN, 'RegressionTestReporter not available: ' + e.getMessage());
        }

        // Publish platform event for LWC auto-refresh
        try {
            String suiteName = '';
            List<Regression_Test_Suite__c> suiteInfo = [
                SELECT Product_Name__c FROM Regression_Test_Suite__c
                WHERE Id = :suiteId LIMIT 1
            ];
            if (!suiteInfo.isEmpty()) {
                suiteName = suiteInfo[0].Product_Name__c;
            }

            ForceGuard_Test_Complete__e evt = new ForceGuard_Test_Complete__e(
                Test_Run_Id__c = runId,
                Suite_Name__c = suiteName,
                Status__c = overallStatus,
                Pass_Rate__c = totalTests > 0
                    ? (Decimal) totalPassed / totalTests : 0,
                Message__c = overallStatus + ': ' + totalPassed + '/' + totalTests + ' passed'
            );
            EventBus.publish(evt);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Platform event publish failed: ' + e.getMessage());
        }

        // Enqueue email notification
        try {
            System.enqueueJob(new RegressionTestNotifier(runId));
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Notification enqueue failed: ' + e.getMessage());
        }
    }

    /**
     * Static method for LWC invocation - starts a batch run for the given suite.
     * @param suiteId The suite to run
     * @return The batch AsyncApexJob Id
     */
    @AuraEnabled
    public static Id runSuite(Id suiteId) {
        if (suiteId == null) {
            AuraHandledException nullErr = new AuraHandledException('Suite ID is required.');
            nullErr.setMessage('Suite ID is required.');
            throw nullErr;
        }
        RegressionTestRunner runner = new RegressionTestRunner(suiteId);
        return Database.executeBatch(runner, 50);
    }

    /**
     * Creates a Skipped result record for a test case that was blocked.
     */
    private Regression_Test_Result__c createSkippedResult(Regression_Test_Case__c tc, String layer) {
        return new Regression_Test_Result__c(
            Test_Run__c = runId,
            Test_Case__c = tc.Id,
            Status__c = STATUS_SKIPPED,
            Layer__c = layer,
            Error_Message__c = 'Skipped: blocking layer failed',
            Duration_Ms__c = 0
        );
    }

    /**
     * Sorts layer keys by their defined execution order.
     */
    private List<String> sortLayerKeys(Set<String> layerKeys) {
        List<LayerSortWrapper> wrappers = new List<LayerSortWrapper>();
        for (String key : layerKeys) {
            Integer ord = LAYER_ORDER.get(key);
            wrappers.add(new LayerSortWrapper(key, ord != null ? ord : 99));
        }
        wrappers.sort();

        List<String> sorted = new List<String>();
        for (LayerSortWrapper w : wrappers) {
            sorted.add(w.layerName);
        }
        return sorted;
    }

    /**
     * Comparable wrapper to sort layers by their numeric order.
     */
    private class LayerSortWrapper implements Comparable {
        public String layerName;
        public Integer sortOrder;

        public LayerSortWrapper(String layerName, Integer sortOrder) {
            this.layerName = layerName;
            this.sortOrder = sortOrder;
        }

        public Integer compareTo(Object other) {
            LayerSortWrapper otherWrapper = (LayerSortWrapper) other;
            return this.sortOrder - otherWrapper.sortOrder;
        }
    }
}
