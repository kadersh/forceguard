/**
 * ForceGuardTestDataFactory - Shared test data factory for all ForceGuard test classes.
 * Creates Regression_Test_Suite__c, Regression_Test_Case__c, Regression_Test_Run__c,
 * and Regression_Test_Result__c records for use in unit tests.
 */
@IsTest
public class ForceGuardTestDataFactory {

    /**
     * Creates a test user with Standard User profile for runAs() usage.
     * @return User record (inserted)
     */
    public static User createTestUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User testUser = new User(
            Alias = 'fgtest',
            Email = 'forceguard.test@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'ForceGuardTest',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/New_York',
            UserName = 'forceguard.test' + DateTime.now().getTime() + '@test.com'
        );
        insert testUser;

        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'ForceGuard_User' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = testUser.Id, PermissionSetId = ps.Id);

        return testUser;
    }

    /**
     * Creates a test suite with basic fields.
     * @param productName The product name for the suite
     * @return Regression_Test_Suite__c (NOT inserted)
     */
    public static Regression_Test_Suite__c createSuite(String productName) {
        return new Regression_Test_Suite__c(
            Name = 'Test Suite - ' + productName,
            Product_Name__c = productName,
            Version__c = '1.0',
            Target_Org__c = 'test-org',
            Is_Active__c = true,
            Source_Path__c = 'force-app/main/default'
        );
    }

    /**
     * Creates test cases for a suite - cycles through all 4 layers.
     * @param suiteId The parent suite Id
     * @param count Number of test cases to create
     * @return List of Regression_Test_Case__c (NOT inserted)
     */
    public static List<Regression_Test_Case__c> createTestCases(Id suiteId, Integer count) {
        List<Regression_Test_Case__c> cases = new List<Regression_Test_Case__c>();
        String[] layers = new String[]{'Deployment', 'Apex Test', 'Data Scenario', 'Static Analysis'};
        for (Integer i = 0; i < count; i++) {
            cases.add(new Regression_Test_Case__c(
                Test_Suite__c = suiteId,
                Title__c = 'Test Case ' + (i + 1),
                Test_Layer__c = layers[Math.mod(i, 4)],
                Category__c = 'Functional',
                Perspective__c = 'Developer',
                Priority__c = 'P1',
                Steps__c = 'Test steps for case ' + (i + 1),
                Expected_Result__c = 'Expected result ' + (i + 1),
                Assertion_Type__c = 'No Error',
                Is_Active__c = true,
                Execution_Order__c = i + 1
            ));
        }
        return cases;
    }

    /**
     * Creates a test run for a suite.
     * @param suiteId The parent suite Id
     * @param status The run status (Running, Completed, Failed)
     * @return Regression_Test_Run__c (NOT inserted)
     */
    public static Regression_Test_Run__c createRun(Id suiteId, String status) {
        return new Regression_Test_Run__c(
            Test_Suite__c = suiteId,
            Run_Date__c = DateTime.now(),
            Status__c = status,
            Triggered_By__c = 'Manual',
            Run_By__c = UserInfo.getUserId()
        );
    }

    /**
     * Creates test results for a run, one per test case.
     * @param runId The parent run Id
     * @param testCases The test cases to create results for
     * @param status The result status (Passed, Failed, Skipped, Error)
     * @return List of Regression_Test_Result__c (NOT inserted)
     */
    public static List<Regression_Test_Result__c> createResults(
            Id runId, List<Regression_Test_Case__c> testCases, String status) {
        List<Regression_Test_Result__c> results = new List<Regression_Test_Result__c>();
        for (Regression_Test_Case__c tc : testCases) {
            Regression_Test_Result__c result = new Regression_Test_Result__c(
                Test_Run__c = runId,
                Test_Case__c = tc.Id,
                Status__c = status,
                Layer__c = tc.Test_Layer__c,
                Duration_Ms__c = 100,
                Is_Regression__c = false
            );
            if (status == 'Failed') {
                result.Error_Message__c = 'Test failure for ' + tc.Title__c;
            }
            results.add(result);
        }
        return results;
    }

    /**
     * Creates bulk test cases for governor limit testing.
     * @param suiteId The parent suite Id
     * @param count Number of test cases to create
     * @param layer The test layer for all cases
     * @return List of Regression_Test_Case__c (NOT inserted)
     */
    public static List<Regression_Test_Case__c> createBulkTestCases(Id suiteId, Integer count, String layer) {
        List<Regression_Test_Case__c> cases = new List<Regression_Test_Case__c>();
        for (Integer i = 0; i < count; i++) {
            cases.add(new Regression_Test_Case__c(
                Test_Suite__c = suiteId,
                Title__c = 'Bulk Case ' + (i + 1),
                Test_Layer__c = layer,
                Category__c = 'Bulk Performance',
                Perspective__c = 'Developer',
                Priority__c = 'P1',
                Steps__c = 'CustomObject:Account',
                Expected_Result__c = 'Pass',
                Assertion_Type__c = 'No Error',
                Is_Active__c = true,
                Execution_Order__c = i + 1
            ));
        }
        return cases;
    }
}
