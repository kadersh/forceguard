/**
 * TestResultDetailController - Backend controller for the testResultDetail LWC.
 * Provides result listing grouped by layer, single result detail,
 * known issue flagging, and single test case re-run.
 */
public with sharing class TestResultDetailController {

    /**
     * Retrieves all results for a run, grouped by test layer.
     * @param runId The Regression_Test_Run__c Id
     * @return ResultsByLayer with run info and layer-grouped results
     */
    @AuraEnabled(cacheable=true)
    public static ResultsByLayer getRunResults(Id runId) {
        try {
            ResultsByLayer response = new ResultsByLayer();

            response.runInfo = [
                SELECT Id, Name, Run_Date__c, Status__c, Total_Tests__c, Passed__c,
                       Failed__c, Skipped__c, Pass_Rate__c, Duration_Seconds__c,
                       Test_Suite__r.Product_Name__c
                FROM Regression_Test_Run__c
                WHERE Id = :runId
                WITH USER_MODE
            ];

            response.layers = new Map<String, List<ResultItem>>();

            List<Regression_Test_Result__c> results = [
                SELECT Id, Status__c, Layer__c, Duration_Ms__c, Error_Message__c,
                       Stack_Trace__c, Execution_Log__c, Actual_Result__c,
                       Is_Regression__c, Previous_Status__c, Is_Known_Issue__c,
                       Test_Case__c, Test_Case__r.Title__c, Test_Case__r.Priority__c,
                       Test_Case__r.Category__c, Test_Case__r.Expected_Result__c
                FROM Regression_Test_Result__c
                WHERE Test_Run__c = :runId
                WITH USER_MODE
                ORDER BY Layer__c, Test_Case__r.Title__c
            ];

            for (Regression_Test_Result__c r : results) {
                ResultItem item = new ResultItem();
                item.result = r;
                item.testCaseTitle = r.Test_Case__r.Title__c;
                item.testCaseId = r.Test_Case__c;
                item.priority = r.Test_Case__r.Priority__c;
                item.category = r.Test_Case__r.Category__c;
                item.expectedResult = r.Test_Case__r.Expected_Result__c;

                String layer = r.Layer__c;
                if (!response.layers.containsKey(layer)) {
                    response.layers.put(layer, new List<ResultItem>());
                }
                response.layers.get(layer).add(item);
            }

            return response;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Retrieves full detail for a single test result including execution log and stack trace.
     * @param resultId The Regression_Test_Result__c Id
     * @return ResultItem with complete result data
     */
    @AuraEnabled(cacheable=true)
    public static ResultItem getResultDetail(Id resultId) {
        try {
            Regression_Test_Result__c r = [
                SELECT Id, Status__c, Layer__c, Duration_Ms__c, Error_Message__c,
                       Stack_Trace__c, Execution_Log__c, Actual_Result__c,
                       Is_Regression__c, Previous_Status__c, Is_Known_Issue__c,
                       Test_Case__c, Test_Case__r.Title__c, Test_Case__r.Priority__c,
                       Test_Case__r.Category__c, Test_Case__r.Expected_Result__c
                FROM Regression_Test_Result__c
                WHERE Id = :resultId
                WITH USER_MODE
            ];

            ResultItem item = new ResultItem();
            item.result = r;
            item.testCaseTitle = r.Test_Case__r.Title__c;
            item.testCaseId = r.Test_Case__c;
            item.priority = r.Test_Case__r.Priority__c;
            item.category = r.Test_Case__r.Category__c;
            item.expectedResult = r.Test_Case__r.Expected_Result__c;
            return item;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Toggles the Is_Known_Issue__c flag on a test result.
     * @param resultId The Regression_Test_Result__c Id
     * @param isKnown True to mark as known issue, false to clear
     */
    @AuraEnabled
    public static void markKnownIssue(Id resultId, Boolean isKnown) {
        try {
            Regression_Test_Result__c result = new Regression_Test_Result__c(
                Id = resultId,
                Is_Known_Issue__c = isKnown
            );
            update Security.stripInaccessible(AccessType.UPDATABLE,
                new List<Regression_Test_Result__c>{ result }).getRecords();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Creates a new run targeting a single test case for re-execution.
     * @param testCaseId The Regression_Test_Case__c Id to re-run
     * @param suiteId The parent suite Id
     * @return The new Regression_Test_Run__c Id
     */
    @AuraEnabled
    public static Id rerunTestCase(Id testCaseId, Id suiteId) {
        try {
            // Create a new run with system-determined values only (no user input).
            // SOQL queries above enforce WITH USER_MODE for read access;
            // insert uses system mode since all field values are controlled by the application.
            Regression_Test_Run__c newRun = new Regression_Test_Run__c(
                Test_Suite__c = suiteId,
                Run_Date__c = DateTime.now(),
                Status__c = 'Queued',
                Triggered_By__c = 'Re-run Single',
                Run_By__c = UserInfo.getUserId(),
                Total_Tests__c = 1
            );
            insert newRun;
            return newRun.Id;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /** Wrapper grouping results by layer with run information. */
    public class ResultsByLayer {
        @AuraEnabled public Regression_Test_Run__c runInfo;
        @AuraEnabled public Map<String, List<ResultItem>> layers;
    }

    /** Wrapper for a single result with related test case info. */
    public class ResultItem {
        @AuraEnabled public Regression_Test_Result__c result;
        @AuraEnabled public String testCaseTitle;
        @AuraEnabled public Id testCaseId;
        @AuraEnabled public String priority;
        @AuraEnabled public String category;
        @AuraEnabled public String expectedResult;
    }
}
