/**
 * TestSuiteManagerController - Apex controller for the testSuiteManager LWC.
 * Provides CRUD operations for Regression_Test_Suite__c and Regression_Test_Case__c,
 * plus aggregation stats and bulk operations.
 */
public with sharing class TestSuiteManagerController {

    /**
     * Returns all suites with aggregate test case counts.
     */
    @AuraEnabled(cacheable=true)
    public static List<SuiteWithStats> getSuites() {
        try {
            // Query suites
            List<Regression_Test_Suite__c> suites = [
                SELECT Id, Name, Description__c, Product_Name__c, Product_Namespace__c,
                       Version__c, Source_Path__c, Target_Org__c, Is_Active__c,
                       Last_Run_Date__c, Last_Run_Status__c
                FROM Regression_Test_Suite__c
                WITH USER_MODE
                ORDER BY Name ASC
                LIMIT 200
            ];

            if (suites.isEmpty()) {
                return new List<SuiteWithStats>();
            }

            // Collect suite Ids
            Set<Id> suiteIds = new Set<Id>();
            for (Regression_Test_Suite__c s : suites) {
                suiteIds.add(s.Id);
            }

            // Aggregate total and active counts per suite
            Map<Id, Integer> totalCountMap = new Map<Id, Integer>();
            Map<Id, Integer> activeCountMap = new Map<Id, Integer>();

            for (AggregateResult ar : [
                SELECT Test_Suite__c suiteId, COUNT(Id) cnt
                FROM Regression_Test_Case__c
                WHERE Test_Suite__c IN :suiteIds
                WITH USER_MODE
                GROUP BY Test_Suite__c
            ]) {
                totalCountMap.put((Id) ar.get('suiteId'), (Integer) ar.get('cnt'));
            }

            for (AggregateResult ar : [
                SELECT Test_Suite__c suiteId, COUNT(Id) cnt
                FROM Regression_Test_Case__c
                WHERE Test_Suite__c IN :suiteIds AND Is_Active__c = true
                WITH USER_MODE
                GROUP BY Test_Suite__c
            ]) {
                activeCountMap.put((Id) ar.get('suiteId'), (Integer) ar.get('cnt'));
            }

            // Build result list
            List<SuiteWithStats> result = new List<SuiteWithStats>();
            for (Regression_Test_Suite__c s : suites) {
                SuiteWithStats sws = new SuiteWithStats();
                sws.suite = s;
                sws.testCaseCount = totalCountMap.containsKey(s.Id) ? totalCountMap.get(s.Id) : 0;
                sws.activeCount = activeCountMap.containsKey(s.Id) ? activeCountMap.get(s.Id) : 0;
                result.add(sws);
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Returns test cases for a suite with optional filters.
     */
    @AuraEnabled(cacheable=true)
    public static List<Regression_Test_Case__c> getTestCases(
            Id suiteId, String layerFilter, String categoryFilter, String priorityFilter) {
        try {
            String query = 'SELECT Id, Name, Title__c, Description__c, Test_Layer__c, '
                + 'Category__c, Perspective__c, Priority__c, Assertion_Type__c, '
                + 'Steps__c, Expected_Result__c, Execution_Order__c, Is_Active__c, '
                + 'Last_Result_Status__c, Consecutive_Failures__c, Related_Metadata__c, '
                + 'Tags__c, Target_Object__c '
                + 'FROM Regression_Test_Case__c '
                + 'WHERE Test_Suite__c = :suiteId';

            if (String.isNotBlank(layerFilter)) {
                query += ' AND Test_Layer__c = :layerFilter';
            }
            if (String.isNotBlank(categoryFilter)) {
                query += ' AND Category__c = :categoryFilter';
            }
            if (String.isNotBlank(priorityFilter)) {
                query += ' AND Priority__c = :priorityFilter';
            }

            query += ' WITH USER_MODE ORDER BY Execution_Order__c ASC NULLS LAST LIMIT 2000';

            return Database.query(query);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Creates a new test suite and returns it with Id.
     */
    @AuraEnabled
    public static Regression_Test_Suite__c createSuite(Regression_Test_Suite__c suite) {
        try {
            SObjectAccessDecision decision = Security.stripInaccessible(
                AccessType.CREATABLE, new List<Regression_Test_Suite__c>{ suite }
            );
            List<Regression_Test_Suite__c> cleaned = (List<Regression_Test_Suite__c>) decision.getRecords();
            insert cleaned;
            return cleaned[0];
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Updates an existing test suite and returns it.
     */
    @AuraEnabled
    public static Regression_Test_Suite__c updateSuite(Regression_Test_Suite__c suite) {
        try {
            SObjectAccessDecision decision = Security.stripInaccessible(
                AccessType.UPDATABLE, new List<Regression_Test_Suite__c>{ suite }
            );
            List<Regression_Test_Suite__c> cleaned = (List<Regression_Test_Suite__c>) decision.getRecords();
            update cleaned;
            return cleaned[0];
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Creates a new test case and returns it with Id.
     */
    @AuraEnabled
    public static Regression_Test_Case__c createTestCase(Regression_Test_Case__c testCase) {
        try {
            SObjectAccessDecision decision = Security.stripInaccessible(
                AccessType.CREATABLE, new List<Regression_Test_Case__c>{ testCase }
            );
            List<Regression_Test_Case__c> cleaned = (List<Regression_Test_Case__c>) decision.getRecords();
            insert cleaned;
            return cleaned[0];
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Updates an existing test case and returns it.
     */
    @AuraEnabled
    public static Regression_Test_Case__c updateTestCase(Regression_Test_Case__c testCase) {
        try {
            SObjectAccessDecision decision = Security.stripInaccessible(
                AccessType.UPDATABLE, new List<Regression_Test_Case__c>{ testCase }
            );
            List<Regression_Test_Case__c> cleaned = (List<Regression_Test_Case__c>) decision.getRecords();
            update cleaned;
            return cleaned[0];
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Deletes test cases by Id list (bulk).
     */
    @AuraEnabled
    public static void deleteTestCases(List<Id> testCaseIds) {
        try {
            List<Regression_Test_Case__c> toDelete = [
                SELECT Id FROM Regression_Test_Case__c
                WHERE Id IN :testCaseIds
                WITH USER_MODE
            ];
            if (!toDelete.isEmpty()) {
                delete toDelete;
            }
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Toggles Is_Active__c for a list of test cases.
     */
    @AuraEnabled
    public static void toggleActive(List<Id> testCaseIds, Boolean isActive) {
        try {
            List<Regression_Test_Case__c> cases = [
                SELECT Id, Is_Active__c FROM Regression_Test_Case__c
                WHERE Id IN :testCaseIds
                WITH USER_MODE
            ];
            for (Regression_Test_Case__c tc : cases) {
                tc.Is_Active__c = isActive;
            }
            SObjectAccessDecision decision = Security.stripInaccessible(
                AccessType.UPDATABLE, cases
            );
            update decision.getRecords();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Inner class combining suite record with aggregate stats.
     */
    public class SuiteWithStats {
        @AuraEnabled public Regression_Test_Suite__c suite;
        @AuraEnabled public Integer testCaseCount;
        @AuraEnabled public Integer activeCount;
    }
}
