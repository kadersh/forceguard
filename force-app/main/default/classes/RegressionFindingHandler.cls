/**
 * RegressionFindingHandler - Creates Regression_Finding__c records when
 * test results indicate a regression (Status = Failed, Is_Regression = true).
 *
 * Called from RegressionTestResultTrigger (after insert).
 * Bulkified: collects all IDs, queries related records once, deduplicates
 * against existing findings, then inserts new findings in a single DML.
 */
public with sharing class RegressionFindingHandler {

    /**
     * Processes newly inserted test results and creates findings for regressions.
     * @param newResults List of Regression_Test_Result__c from Trigger.new
     */
    public static void handleAfterInsert(List<Regression_Test_Result__c> newResults) {
        // Filter to only failed regressions
        List<Regression_Test_Result__c> regressions = new List<Regression_Test_Result__c>();
        Set<Id> testCaseIds = new Set<Id>();
        Set<Id> testRunIds = new Set<Id>();

        for (Regression_Test_Result__c result : newResults) {
            if (result.Status__c == 'Failed' && result.Is_Regression__c == true) {
                regressions.add(result);
                if (result.Test_Case__c != null) {
                    testCaseIds.add(result.Test_Case__c);
                }
                if (result.Test_Run__c != null) {
                    testRunIds.add(result.Test_Run__c);
                }
            }
        }

        if (regressions.isEmpty()) {
            return;
        }

        // Query related test cases (for Expected_Result, Category, Priority)
        Map<Id, Regression_Test_Case__c> testCaseMap = new Map<Id, Regression_Test_Case__c>(
            [SELECT Id, Expected_Result__c, Category__c, Priority__c,
                    Test_Suite__r.Name
             FROM Regression_Test_Case__c
             WHERE Id IN :testCaseIds
             WITH SYSTEM_MODE]
        );

        // Query related test runs (for dedup and suite info)
        Map<Id, Regression_Test_Run__c> testRunMap = new Map<Id, Regression_Test_Run__c>(
            [SELECT Id, Test_Suite__r.Name
             FROM Regression_Test_Run__c
             WHERE Id IN :testRunIds
             WITH SYSTEM_MODE]
        );

        // Check for existing findings to avoid duplicates (same Test_Case + Test_Run)
        Set<String> existingKeys = new Set<String>();
        for (Regression_Finding__c existing : [
            SELECT Test_Case__c, Test_Run__c
            FROM Regression_Finding__c
            WHERE Test_Case__c IN :testCaseIds
              AND Test_Run__c IN :testRunIds
            WITH SYSTEM_MODE
        ]) {
            existingKeys.add(String.valueOf(existing.Test_Case__c) + '|' + String.valueOf(existing.Test_Run__c));
        }

        // Build findings, skipping duplicates
        List<Regression_Finding__c> findings = new List<Regression_Finding__c>();
        Set<String> newKeys = new Set<String>();

        for (Regression_Test_Result__c result : regressions) {
            String dedupKey = String.valueOf(result.Test_Case__c) + '|' + String.valueOf(result.Test_Run__c);

            if (existingKeys.contains(dedupKey) || newKeys.contains(dedupKey)) {
                continue;
            }
            newKeys.add(dedupKey);

            Regression_Test_Case__c testCase = result.Test_Case__c != null
                ? testCaseMap.get(result.Test_Case__c) : null;
            Regression_Test_Run__c testRun = result.Test_Run__c != null
                ? testRunMap.get(result.Test_Run__c) : null;

            // Map test case priority (P1/P2/P3/P4) to finding priority
            String findingPriority = mapPriority(testCase != null ? testCase.Priority__c : null);

            // Determine suite name from either test case or test run
            String suiteName = '';
            if (testCase != null && testCase.Test_Suite__r != null) {
                suiteName = testCase.Test_Suite__r.Name;
            } else if (testRun != null && testRun.Test_Suite__r != null) {
                suiteName = testRun.Test_Suite__r.Name;
            }

            findings.add(new Regression_Finding__c(
                Test_Case__c = result.Test_Case__c,
                Test_Run__c = result.Test_Run__c,
                Test_Result__c = result.Id,
                Suite_Name__c = suiteName,
                Error_Message__c = result.Error_Message__c,
                Expected_Result__c = testCase != null ? testCase.Expected_Result__c : null,
                Actual_Result__c = result.Actual_Result__c,
                Layer__c = result.Layer__c,
                Category__c = testCase != null ? testCase.Category__c : null,
                Priority__c = findingPriority,
                Finding_Date__c = DateTime.now(),
                Status__c = 'Open'
            ));
        }

        if (!findings.isEmpty()) {
            insert findings;
        }
    }

    /**
     * Maps test case priority codes (P1-P4) to finding priority labels.
     * @param casePriority The Priority__c from Regression_Test_Case__c
     * @return Finding priority (Critical, High, Medium, Low)
     */
    private static String mapPriority(String casePriority) {
        if (casePriority == null) {
            return 'Medium';
        }
        switch on casePriority {
            when 'P1' { return 'Critical'; }
            when 'P2' { return 'High'; }
            when 'P3' { return 'Medium'; }
            when 'P4' { return 'Low'; }
            when else { return 'Medium'; }
        }
    }
}
