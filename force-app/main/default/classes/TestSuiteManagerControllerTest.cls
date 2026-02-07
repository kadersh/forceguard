/**
 * TestSuiteManagerControllerTest - Unit tests for TestSuiteManagerController.
 * Covers all 8 methods with positive, filter, and bulk scenarios.
 */
@IsTest
public with sharing class TestSuiteManagerControllerTest {

    @TestSetup
    static void setupData() {
        // Create test user with ForceGuard permissions
        // Wrap in runAs to isolate setup object DML (PermissionSetAssignment)
        // from non-setup object DML (custom objects) - avoids MIXED_DML_OPERATION
        System.runAs(new User(Id = UserInfo.getUserId())) {
            ForceGuardTestDataFactory.createTestUser();
        }

        // Create 2 suites (admin context)
        Regression_Test_Suite__c suite1 = ForceGuardTestDataFactory.createSuite('Product A');
        Regression_Test_Suite__c suite2 = ForceGuardTestDataFactory.createSuite('Product B');
        suite2.Name = 'Test Suite - Product B';
        insert new List<Regression_Test_Suite__c>{ suite1, suite2 };

        // Create test cases for suite1: mix of layers, categories, priorities
        List<Regression_Test_Case__c> cases = new List<Regression_Test_Case__c>();
        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suite1.Id,
            Title__c = 'Deploy Check',
            Test_Layer__c = 'Deployment',
            Category__c = 'Deployment',
            Priority__c = 'P0',
            Is_Active__c = true,
            Execution_Order__c = 1
        ));
        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suite1.Id,
            Title__c = 'Apex Verify',
            Test_Layer__c = 'Apex Test',
            Category__c = 'Functional',
            Priority__c = 'P1',
            Is_Active__c = true,
            Execution_Order__c = 2
        ));
        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suite1.Id,
            Title__c = 'Data Scenario',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Edge Case',
            Priority__c = 'P2',
            Steps__c = 'Audit_Run__c|Id != null',
            Is_Active__c = false,
            Execution_Order__c = 3
        ));

        // Create 2 test cases for suite2
        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suite2.Id,
            Title__c = 'Suite2 Case 1',
            Test_Layer__c = 'Deployment',
            Category__c = 'Functional',
            Priority__c = 'P1',
            Is_Active__c = true,
            Execution_Order__c = 1
        ));
        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suite2.Id,
            Title__c = 'Suite2 Case 2',
            Test_Layer__c = 'Static Analysis',
            Category__c = 'Regression',
            Priority__c = 'P0',
            Is_Active__c = true,
            Execution_Order__c = 2
        ));
        insert cases;
    }

    @IsTest
    static void testGetSuites() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            List<TestSuiteManagerController.SuiteWithStats> results;
            Test.startTest();
            results = TestSuiteManagerController.getSuites();
            Test.stopTest();

            System.assertEquals(2, results.size(), 'Should return 2 suites');

            TestSuiteManagerController.SuiteWithStats suiteA = null;
            TestSuiteManagerController.SuiteWithStats suiteB = null;
            for (TestSuiteManagerController.SuiteWithStats sws : results) {
                if (sws.suite.Product_Name__c == 'Product A') {
                    suiteA = sws;
                } else if (sws.suite.Product_Name__c == 'Product B') {
                    suiteB = sws;
                }
            }

            System.assertNotEquals(null, suiteA, 'Product A suite should exist');
            System.assertEquals(3, suiteA.testCaseCount, 'Product A should have 3 test cases');
            System.assertEquals(2, suiteA.activeCount, 'Product A should have 2 active cases');

            System.assertNotEquals(null, suiteB, 'Product B suite should exist');
            System.assertEquals(2, suiteB.testCaseCount, 'Product B should have 2 test cases');
            System.assertEquals(2, suiteB.activeCount, 'Product B should have 2 active cases');
        }
    }

    @IsTest
    static void testGetTestCasesNoFilter() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];
        Regression_Test_Suite__c suite1 = [
            SELECT Id FROM Regression_Test_Suite__c WHERE Product_Name__c = 'Product A' LIMIT 1
        ];

        System.runAs(testUser) {
            Test.startTest();
            List<Regression_Test_Case__c> cases = TestSuiteManagerController.getTestCases(
                suite1.Id, null, null, null
            );
            Test.stopTest();

            System.assertEquals(3, cases.size(), 'Should return all 3 cases for suite1');
            System.assertEquals('Deploy Check', cases[0].Title__c, 'First should be Deploy Check (order 1)');
            System.assertEquals('Apex Verify', cases[1].Title__c, 'Second should be Apex Verify (order 2)');
        }
    }

    @IsTest
    static void testGetTestCasesWithFilters() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];
        Regression_Test_Suite__c suite1 = [
            SELECT Id FROM Regression_Test_Suite__c WHERE Product_Name__c = 'Product A' LIMIT 1
        ];

        System.runAs(testUser) {
            Test.startTest();
            List<Regression_Test_Case__c> layerFiltered = TestSuiteManagerController.getTestCases(
                suite1.Id, 'Deployment', null, null
            );
            System.assertEquals(1, layerFiltered.size(), 'Layer filter should return 1 Deployment case');
            System.assertEquals('Deploy Check', layerFiltered[0].Title__c);

            List<Regression_Test_Case__c> catFiltered = TestSuiteManagerController.getTestCases(
                suite1.Id, null, 'Functional', null
            );
            System.assertEquals(1, catFiltered.size(), 'Category filter should return 1 Functional case');

            List<Regression_Test_Case__c> prioFiltered = TestSuiteManagerController.getTestCases(
                suite1.Id, null, null, 'P2'
            );
            System.assertEquals(1, prioFiltered.size(), 'Priority filter should return 1 P2 case');

            List<Regression_Test_Case__c> combined = TestSuiteManagerController.getTestCases(
                suite1.Id, 'Deployment', 'Deployment', 'P0'
            );
            System.assertEquals(1, combined.size(), 'Combined filters should return 1 case');
            Test.stopTest();
        }
    }

    @IsTest
    static void testCreateSuite() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Suite__c newSuite = new Regression_Test_Suite__c(
                Name = 'New Suite',
                Product_Name__c = 'Product C',
                Version__c = '2.0',
                Is_Active__c = true
            );

            Test.startTest();
            Regression_Test_Suite__c created = TestSuiteManagerController.createSuite(newSuite);
            Test.stopTest();

            System.assertNotEquals(null, created.Id, 'Created suite should have an Id');
            Regression_Test_Suite__c queried = [
                SELECT Name, Product_Name__c, Version__c
                FROM Regression_Test_Suite__c
                WHERE Id = :created.Id
            ];
            System.assertEquals('New Suite', queried.Name);
            System.assertEquals('Product C', queried.Product_Name__c);
            System.assertEquals('2.0', queried.Version__c);
        }
    }

    @IsTest
    static void testUpdateSuite() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];
        Regression_Test_Suite__c suite1 = [
            SELECT Id, Name, Version__c FROM Regression_Test_Suite__c
            WHERE Product_Name__c = 'Product A' LIMIT 1
        ];

        System.runAs(testUser) {
            suite1.Version__c = '3.0';
            suite1.Name = 'Updated Suite Name';

            Test.startTest();
            Regression_Test_Suite__c updated = TestSuiteManagerController.updateSuite(suite1);
            Test.stopTest();

            Regression_Test_Suite__c queried = [
                SELECT Name, Version__c FROM Regression_Test_Suite__c WHERE Id = :suite1.Id
            ];
            System.assertEquals('Updated Suite Name', queried.Name);
            System.assertEquals('3.0', queried.Version__c);
        }
    }

    @IsTest
    static void testCreateTestCase() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];
        Regression_Test_Suite__c suite1 = [
            SELECT Id FROM Regression_Test_Suite__c WHERE Product_Name__c = 'Product A' LIMIT 1
        ];

        System.runAs(testUser) {
            Regression_Test_Case__c newCase = new Regression_Test_Case__c(
                Test_Suite__c = suite1.Id,
                Title__c = 'New Test Case',
                Test_Layer__c = 'Static Analysis',
                Category__c = 'Security Permission',
                Priority__c = 'P0',
                Is_Active__c = true,
                Execution_Order__c = 10
            );

            Test.startTest();
            Regression_Test_Case__c created = TestSuiteManagerController.createTestCase(newCase);
            Test.stopTest();

            System.assertNotEquals(null, created.Id, 'Created test case should have an Id');
            Regression_Test_Case__c queried = [
                SELECT Title__c, Test_Layer__c, Priority__c
                FROM Regression_Test_Case__c WHERE Id = :created.Id
            ];
            System.assertEquals('New Test Case', queried.Title__c);
            System.assertEquals('Static Analysis', queried.Test_Layer__c);
            System.assertEquals('P0', queried.Priority__c);
        }
    }

    @IsTest
    static void testUpdateTestCase() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];
        Regression_Test_Case__c existingCase = [
            SELECT Id, Title__c, Priority__c FROM Regression_Test_Case__c
            WHERE Title__c = 'Deploy Check' LIMIT 1
        ];

        System.runAs(testUser) {
            existingCase.Title__c = 'Updated Deploy Check';
            existingCase.Priority__c = 'P2';

            Test.startTest();
            Regression_Test_Case__c updated = TestSuiteManagerController.updateTestCase(existingCase);
            Test.stopTest();

            Regression_Test_Case__c queried = [
                SELECT Title__c, Priority__c FROM Regression_Test_Case__c WHERE Id = :existingCase.Id
            ];
            System.assertEquals('Updated Deploy Check', queried.Title__c);
            System.assertEquals('P2', queried.Priority__c);
        }
    }

    @IsTest
    static void testDeleteTestCases() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];
        List<Regression_Test_Case__c> suite2Cases = [
            SELECT Id FROM Regression_Test_Case__c
            WHERE Test_Suite__r.Product_Name__c = 'Product B'
        ];
        List<Id> idsToDelete = new List<Id>();
        for (Regression_Test_Case__c tc : suite2Cases) {
            idsToDelete.add(tc.Id);
        }

        System.assertEquals(2, idsToDelete.size(), 'Should have 2 cases to delete');

        System.runAs(testUser) {
            Test.startTest();
            TestSuiteManagerController.deleteTestCases(idsToDelete);
            Test.stopTest();
        }

        List<Regression_Test_Case__c> remaining = [
            SELECT Id FROM Regression_Test_Case__c
            WHERE Test_Suite__r.Product_Name__c = 'Product B'
        ];
        System.assertEquals(0, remaining.size(), 'All suite2 cases should be deleted');
    }

    @IsTest
    static void testToggleActive() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];
        List<Regression_Test_Case__c> activeCases = [
            SELECT Id FROM Regression_Test_Case__c
            WHERE Is_Active__c = true AND Test_Suite__r.Product_Name__c = 'Product A'
        ];
        List<Id> activeIds = new List<Id>();
        for (Regression_Test_Case__c tc : activeCases) {
            activeIds.add(tc.Id);
        }
        System.assertEquals(2, activeIds.size(), 'Should have 2 active cases');

        System.runAs(testUser) {
            Test.startTest();
            TestSuiteManagerController.toggleActive(activeIds, false);
            Test.stopTest();
        }

        List<Regression_Test_Case__c> afterToggle = [
            SELECT Id, Is_Active__c FROM Regression_Test_Case__c
            WHERE Id IN :activeIds
        ];
        for (Regression_Test_Case__c tc : afterToggle) {
            System.assertEquals(false, tc.Is_Active__c, 'Case should be deactivated');
        }
    }
}
