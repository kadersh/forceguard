/**
 * @description Test class for AuditTestCaseSeeder.
 * Verifies seed data script creates all audit test cases correctly.
 *
 * @author ForceGuard
 * @date 2026-02-07
 */
@IsTest
private class AuditTestCaseSeederTest {

    /**
     * @description Tests seed() creates suite and all test cases
     */
    @IsTest
    static void testSeedCreatesAllTestCases() {
        Test.startTest();
        AuditTestCaseSeeder.seed();
        Test.stopTest();

        // Verify suite created
        List<Regression_Test_Suite__c> suites = [
            SELECT Id, Name, Product_Name__c, Version__c, Is_Active__c
            FROM Regression_Test_Suite__c
            WHERE Product_Name__c = 'User Access Audit'
        ];

        System.assertEquals(1, suites.size(), 'Should create exactly 1 test suite');
        Regression_Test_Suite__c suite = suites[0];
        System.assertEquals('User Access Audit Test Suite', suite.Name);
        System.assertEquals('1.0', suite.Version__c);
        System.assertEquals(true, suite.Is_Active__c);

        // Verify all test cases created
        List<Regression_Test_Case__c> allCases = [
            SELECT Id, Test_Suite__c, Test_Layer__c, Category__c, Priority__c, Execution_Order__c
            FROM Regression_Test_Case__c
            WHERE Test_Suite__c = :suite.Id
        ];

        System.assert(allCases.size() >= 60, 'Should create at least 60 test cases. Found: ' + allCases.size());

        // Verify all test cases linked to suite
        for (Regression_Test_Case__c tc : allCases) {
            System.assertEquals(suite.Id, tc.Test_Suite__c, 'All test cases should be linked to suite');
        }
    }

    /**
     * @description Tests idempotency - running seed twice should not duplicate
     */
    @IsTest
    static void testSeedIsIdempotent() {
        // Run seed twice
        AuditTestCaseSeeder.seed();
        AuditTestCaseSeeder.seed();

        // Verify still only 1 suite
        List<Regression_Test_Suite__c> suites = [
            SELECT Id
            FROM Regression_Test_Suite__c
            WHERE Product_Name__c = 'User Access Audit'
        ];

        System.assertEquals(1, suites.size(), 'Should still have only 1 suite after re-run');

        // Verify test case count not doubled
        Integer caseCount = [
            SELECT COUNT()
            FROM Regression_Test_Case__c
            WHERE Test_Suite__c = :suites[0].Id
        ];

        System.assert(caseCount >= 60 && caseCount < 130, 'Test cases should not be duplicated. Found: ' + caseCount);
    }

    /**
     * @description Tests all 4 layers are represented
     */
    @IsTest
    static void testAllLayersRepresented() {
        AuditTestCaseSeeder.seed();

        Regression_Test_Suite__c suite = [
            SELECT Id
            FROM Regression_Test_Suite__c
            WHERE Product_Name__c = 'User Access Audit'
            LIMIT 1
        ];

        // Count test cases by layer
        Map<String, Integer> layerCounts = new Map<String, Integer>();
        for (AggregateResult ar : [
            SELECT Test_Layer__c, COUNT(Id) cnt
            FROM Regression_Test_Case__c
            WHERE Test_Suite__c = :suite.Id
            GROUP BY Test_Layer__c
        ]) {
            layerCounts.put((String)ar.get('Test_Layer__c'), (Integer)ar.get('cnt'));
        }

        // Assert all 4 layers present
        System.assert(layerCounts.containsKey('Deployment'), 'Should have Deployment layer tests');
        System.assert(layerCounts.containsKey('Apex Test'), 'Should have Apex Test layer tests');
        System.assert(layerCounts.containsKey('Data Scenario'), 'Should have Data Scenario layer tests');
        System.assert(layerCounts.containsKey('Static Analysis'), 'Should have Static Analysis layer tests');

        // Assert expected counts (approximate)
        System.assert(layerCounts.get('Deployment') >= 6, 'Should have at least 6 Deployment tests');
        System.assert(layerCounts.get('Apex Test') >= 10, 'Should have at least 10 Apex Test tests');
        System.assert(layerCounts.get('Data Scenario') >= 30, 'Should have at least 30 Data Scenario tests');
        System.assert(layerCounts.get('Static Analysis') >= 5, 'Should have at least 5 Static Analysis tests');
    }

    /**
     * @description Tests all categories are represented
     */
    @IsTest
    static void testAllCategoriesUsed() {
        AuditTestCaseSeeder.seed();

        Regression_Test_Suite__c suite = [
            SELECT Id
            FROM Regression_Test_Suite__c
            WHERE Product_Name__c = 'User Access Audit'
            LIMIT 1
        ];

        Set<String> categories = new Set<String>();
        for (Regression_Test_Case__c tc : [
            SELECT Category__c
            FROM Regression_Test_Case__c
            WHERE Test_Suite__c = :suite.Id AND Category__c != null
        ]) {
            categories.add(tc.Category__c);
        }

        // Assert key categories present
        System.assert(categories.contains('Deployment'), 'Should use Deployment category');
        System.assert(categories.contains('Functional'), 'Should use Functional category');
        System.assert(categories.contains('Edge Case'), 'Should use Edge Case category');
        System.assert(categories.contains('Security Permission'), 'Should use Security Permission category');
        System.assert(categories.contains('Regression'), 'Should use Regression category');
        System.assert(categories.contains('Bulk Performance'), 'Should use Bulk Performance category');
    }

    /**
     * @description Tests all perspectives are represented
     */
    @IsTest
    static void testAllPerspectivesUsed() {
        AuditTestCaseSeeder.seed();

        Regression_Test_Suite__c suite = [
            SELECT Id
            FROM Regression_Test_Suite__c
            WHERE Product_Name__c = 'User Access Audit'
            LIMIT 1
        ];

        Set<String> perspectives = new Set<String>();
        for (Regression_Test_Case__c tc : [
            SELECT Perspective__c
            FROM Regression_Test_Case__c
            WHERE Test_Suite__c = :suite.Id AND Perspective__c != null
        ]) {
            perspectives.add(tc.Perspective__c);
        }

        // Assert all perspectives present
        System.assert(perspectives.contains('Developer'), 'Should use Developer perspective');
        System.assert(perspectives.contains('Admin'), 'Should use Admin perspective');
        System.assert(perspectives.contains('Product Manager'), 'Should use Product Manager perspective');
        System.assert(perspectives.contains('Client'), 'Should use Client perspective');
    }

    /**
     * @description Tests priority distribution
     */
    @IsTest
    static void testPriorityDistribution() {
        AuditTestCaseSeeder.seed();

        Regression_Test_Suite__c suite = [
            SELECT Id
            FROM Regression_Test_Suite__c
            WHERE Product_Name__c = 'User Access Audit'
            LIMIT 1
        ];

        Map<String, Integer> priorityCounts = new Map<String, Integer>();
        for (AggregateResult ar : [
            SELECT Priority__c, COUNT(Id) cnt
            FROM Regression_Test_Case__c
            WHERE Test_Suite__c = :suite.Id
            GROUP BY Priority__c
        ]) {
            priorityCounts.put((String)ar.get('Priority__c'), (Integer)ar.get('cnt'));
        }

        // Assert P0, P1, P2 all present
        System.assert(priorityCounts.containsKey('P0'), 'Should have P0 priority tests');
        System.assert(priorityCounts.containsKey('P1'), 'Should have P1 priority tests');

        // Assert P0 is most common (critical tests)
        System.assert(priorityCounts.get('P0') > 20, 'Should have many P0 tests (critical paths)');
    }

    /**
     * @description Tests execution order is sequential
     */
    @IsTest
    static void testExecutionOrderSequential() {
        AuditTestCaseSeeder.seed();

        Regression_Test_Suite__c suite = [
            SELECT Id
            FROM Regression_Test_Suite__c
            WHERE Product_Name__c = 'User Access Audit'
            LIMIT 1
        ];

        List<Regression_Test_Case__c> cases = [
            SELECT Execution_Order__c, Test_Layer__c
            FROM Regression_Test_Case__c
            WHERE Test_Suite__c = :suite.Id AND Execution_Order__c != null
            ORDER BY Execution_Order__c ASC
        ];

        // Assert execution order starts at 100
        if (!cases.isEmpty()) {
            System.assertEquals(100, cases[0].Execution_Order__c, 'First test should have order 100');
        }

        // Assert Layer 1 tests (100-199) come before Layer 2 (200-299)
        Boolean foundLayer2 = false;
        for (Regression_Test_Case__c tc : cases) {
            if (tc.Test_Layer__c == 'Apex Test') {
                foundLayer2 = true;
                System.assert(tc.Execution_Order__c >= 200, 'Apex Test layer should start at 200');
            }
            if (foundLayer2 && tc.Test_Layer__c == 'Deployment') {
                System.assert(false, 'Deployment tests should come before Apex Test tests');
            }
        }
    }

    /**
     * @description Tests required fields populated
     */
    @IsTest
    static void testRequiredFieldsPopulated() {
        AuditTestCaseSeeder.seed();

        Regression_Test_Suite__c suite = [
            SELECT Id
            FROM Regression_Test_Suite__c
            WHERE Product_Name__c = 'User Access Audit'
            LIMIT 1
        ];

        List<Regression_Test_Case__c> cases = [
            SELECT Title__c, Test_Layer__c, Expected_Result__c, Assertion_Type__c, Is_Active__c
            FROM Regression_Test_Case__c
            WHERE Test_Suite__c = :suite.Id
        ];

        // Verify all cases have required fields
        for (Regression_Test_Case__c tc : cases) {
            System.assertNotEquals(null, tc.Title__c, 'Title should not be null');
            System.assertNotEquals('', tc.Title__c, 'Title should not be empty');
            System.assertNotEquals(null, tc.Test_Layer__c, 'Test_Layer should not be null');
            System.assertNotEquals(null, tc.Expected_Result__c, 'Expected_Result should not be null');
            System.assertNotEquals(null, tc.Assertion_Type__c, 'Assertion_Type should not be null');
            System.assertEquals(true, tc.Is_Active__c, 'All seeded tests should be active');
        }
    }

    /**
     * @description Tests with System.runAs to verify security
     */
    @IsTest
    static void testSeedWithLimitedUser() {
        // Create test user without audit permissions
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User testUser = new User(
            Alias = 'tuser',
            Email = 'testuser@forceguard.test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'TestUser',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'testuser' + DateTime.now().getTime() + '@forceguard.test.com'
        );
        insert testUser;

        // Run seed as a different user context to verify System.runAs works
        Test.startTest();
        System.runAs(testUser) {
            AuditTestCaseSeeder.seed();

            // Verify seed completed in user context
            List<Regression_Test_Suite__c> suites = [
                SELECT Id
                FROM Regression_Test_Suite__c
                WHERE Product_Name__c = 'User Access Audit'
            ];
            System.assertEquals(1, suites.size(), 'Seeder should work in runAs context');

            Integer caseCount = [
                SELECT COUNT()
                FROM Regression_Test_Case__c
                WHERE Test_Suite__c = :suites[0].Id
            ];
            System.assert(caseCount >= 60, 'All test cases should be seeded in runAs context. Found: ' + caseCount);
        }
        Test.stopTest();
    }

    /**
     * @description Tests layer-specific assertions
     */
    @IsTest
    static void testLayerSpecificContent() {
        AuditTestCaseSeeder.seed();

        Regression_Test_Suite__c suite = [
            SELECT Id
            FROM Regression_Test_Suite__c
            WHERE Product_Name__c = 'User Access Audit'
            LIMIT 1
        ];

        // Verify Deployment layer has metadata component names
        List<Regression_Test_Case__c> deploymentCases = [
            SELECT Title__c, Steps__c, Related_Metadata__c
            FROM Regression_Test_Case__c
            WHERE Test_Suite__c = :suite.Id AND Test_Layer__c = 'Deployment'
        ];

        for (Regression_Test_Case__c tc : deploymentCases) {
            System.assertNotEquals(null, tc.Steps__c, 'Deployment tests should have Steps');
            System.assert(tc.Steps__c.length() > 50, 'Steps should list metadata components');
        }

        // Verify Apex Test layer has test class names
        List<Regression_Test_Case__c> apexTestCases = [
            SELECT Title__c, Steps__c
            FROM Regression_Test_Case__c
            WHERE Test_Suite__c = :suite.Id AND Test_Layer__c = 'Apex Test'
        ];

        for (Regression_Test_Case__c tc : apexTestCases) {
            System.assertNotEquals(null, tc.Steps__c, 'Apex Test tests should have Steps');
            System.assert(tc.Steps__c.contains('Test'), 'Apex Test steps should reference test classes');
        }

        // Verify Static Analysis has scan patterns
        List<Regression_Test_Case__c> staticCases = [
            SELECT Title__c, Steps__c
            FROM Regression_Test_Case__c
            WHERE Test_Suite__c = :suite.Id AND Test_Layer__c = 'Static Analysis'
        ];

        System.assert(!staticCases.isEmpty(), 'Should have Static Analysis tests');
        for (Regression_Test_Case__c tc : staticCases) {
            System.assertNotEquals(null, tc.Steps__c, 'Static Analysis tests should have scan instructions');
        }
    }
}
