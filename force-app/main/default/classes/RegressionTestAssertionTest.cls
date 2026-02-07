/**
 * RegressionTestAssertionTest - Tests for all 7 RegressionTestAssertion methods.
 * Covers: assertEquals, assertNotNull, assertRecordExists, assertRecordCount,
 * assertFieldValue, assertCoverage, and assertNoGovernorViolation.
 */
@IsTest
private class RegressionTestAssertionTest {

    @TestSetup
    static void setup() {
        User testUser = ForceGuardTestDataFactory.createTestUser();
    }

    @IsTest
    static void testAssertEqualsMatch() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Test.startTest();
            RegressionTestAssertion.AssertionResult result =
                RegressionTestAssertion.assertEquals('Hello', 'Hello', 'String equality');
            Test.stopTest();

            System.assertEquals(true, result.passed, 'Equal strings should pass');
            System.assert(result.message.contains('PASSED'),
                'Message should contain PASSED, got: ' + result.message);
            System.assertEquals('Hello', result.expected, 'Expected should be Hello');
            System.assertEquals('Hello', result.actual, 'Actual should be Hello');
        }
    }

    @IsTest
    static void testAssertEqualsMismatch() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Test.startTest();
            RegressionTestAssertion.AssertionResult result =
                RegressionTestAssertion.assertEquals('Expected', 'Actual', 'Mismatch test');
            Test.stopTest();

            System.assertEquals(false, result.passed, 'Different strings should fail');
            System.assert(result.message.contains('Expected'),
                'Message should contain Expected value, got: ' + result.message);
            System.assertEquals('Expected', result.expected, 'Expected field should be Expected');
            System.assertEquals('Actual', result.actual, 'Actual field should be Actual');
        }
    }

    @IsTest
    static void testAssertEqualsNullHandling() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Test.startTest();
            // null vs null should pass
            RegressionTestAssertion.AssertionResult resultBothNull =
                RegressionTestAssertion.assertEquals(null, null, 'Both null');
            // null vs value should fail
            RegressionTestAssertion.AssertionResult resultNullVsValue =
                RegressionTestAssertion.assertEquals(null, 'value', 'Null vs value');
            // value vs null should fail
            RegressionTestAssertion.AssertionResult resultValueVsNull =
                RegressionTestAssertion.assertEquals('value', null, 'Value vs null');
            Test.stopTest();

            System.assertEquals(true, resultBothNull.passed, 'null == null should pass');
            System.assertEquals(false, resultNullVsValue.passed, 'null vs value should fail');
            System.assertEquals(false, resultValueVsNull.passed, 'value vs null should fail');
        }
    }

    @IsTest
    static void testAssertNotNullPass() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Test.startTest();
            RegressionTestAssertion.AssertionResult result =
                RegressionTestAssertion.assertNotNull('some value', 'Not null check');
            Test.stopTest();

            System.assertEquals(true, result.passed, 'Non-null value should pass');
            System.assert(result.message.contains('PASSED'),
                'Message should contain PASSED, got: ' + result.message);
        }
    }

    @IsTest
    static void testAssertNotNullFail() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Test.startTest();
            RegressionTestAssertion.AssertionResult result =
                RegressionTestAssertion.assertNotNull(null, 'Null check');
            Test.stopTest();

            System.assertEquals(false, result.passed, 'Null value should fail');
            System.assert(result.message.contains('null'),
                'Message should mention null, got: ' + result.message);
            System.assertEquals('null', result.actual, 'Actual should be null');
        }
    }

    @IsTest
    static void testAssertRecordExists() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Account acc = new Account(Name = 'Assertion Test Account');
            insert acc;

            Test.startTest();
            RegressionTestAssertion.AssertionResult result =
                RegressionTestAssertion.assertRecordExists('Account', 'Name = \'Assertion Test Account\'');
            Test.stopTest();

            System.assertEquals(true, result.passed,
                'Record exists assertion should pass for inserted account');
            System.assert(result.message.contains('PASSED'),
                'Message should contain PASSED, got: ' + result.message);
        }
    }

    @IsTest
    static void testAssertRecordExistsNoRecords() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Test.startTest();
            RegressionTestAssertion.AssertionResult result =
                RegressionTestAssertion.assertRecordExists('Account', 'Name = \'NonExistentAccount12345\'');
            Test.stopTest();

            System.assertEquals(false, result.passed,
                'Record exists assertion should fail when no records match');
            System.assert(result.message.contains('No'),
                'Message should indicate no records found, got: ' + result.message);
        }
    }

    @IsTest
    static void testAssertRecordExistsBlankObjectType() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Test.startTest();
            RegressionTestAssertion.AssertionResult result =
                RegressionTestAssertion.assertRecordExists('', '');
            Test.stopTest();

            System.assertEquals(false, result.passed,
                'Blank sObjectType should fail gracefully');
            System.assert(result.message.contains('required'),
                'Message should indicate sObjectType is required, got: ' + result.message);
        }
    }

    @IsTest
    static void testAssertRecordCount() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            List<Account> accounts = new List<Account>();
            for (Integer i = 0; i < 5; i++) {
                accounts.add(new Account(Name = 'Count Test ' + i));
            }
            insert accounts;

            Test.startTest();
            RegressionTestAssertion.AssertionResult result =
                RegressionTestAssertion.assertRecordCount('Account', 'Name LIKE \'Count Test%\'', 5);
            Test.stopTest();

            System.assertEquals(true, result.passed,
                'Record count should match expected value of 5');
            System.assertEquals('5', result.expected, 'Expected should be 5');
            System.assertEquals('5', result.actual, 'Actual should be 5');
        }
    }

    @IsTest
    static void testAssertRecordCountMismatch() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Account acc = new Account(Name = 'CountMismatch Test');
            insert acc;

            Test.startTest();
            RegressionTestAssertion.AssertionResult result =
                RegressionTestAssertion.assertRecordCount('Account', 'Name = \'CountMismatch Test\'', 99);
            Test.stopTest();

            System.assertEquals(false, result.passed,
                'Record count mismatch should fail');
            System.assertEquals('99', result.expected, 'Expected should be 99');
            System.assertEquals('1', result.actual, 'Actual should be 1');
        }
    }

    @IsTest
    static void testAssertFieldValue() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Account acc = new Account(Name = 'FieldValue Test', Industry = 'Technology');
            insert acc;

            Test.startTest();
            RegressionTestAssertion.AssertionResult result =
                RegressionTestAssertion.assertFieldValue(acc.Id, 'Account', 'Industry', 'Technology');
            Test.stopTest();

            System.assertEquals(true, result.passed,
                'Field value should match Technology');
            System.assertEquals('Technology', result.expected, 'Expected should be Technology');
            System.assertEquals('Technology', result.actual, 'Actual should be Technology');
        }
    }

    @IsTest
    static void testAssertFieldValueRecordNotFound() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            // Use a valid-looking but non-existent Account Id
            // Create and delete an account to get a valid but non-existent Id
            Account acc = new Account(Name = 'ToDelete');
            insert acc;
            Id deletedId = acc.Id;
            delete acc;

            Test.startTest();
            RegressionTestAssertion.AssertionResult result =
                RegressionTestAssertion.assertFieldValue(deletedId, 'Account', 'Name', 'Anything');
            Test.stopTest();

            System.assertEquals(false, result.passed,
                'Non-existent record should fail assertion');
            System.assert(result.message.contains('not found'),
                'Message should indicate record not found, got: ' + result.message);
        }
    }

    @IsTest
    static void testAssertFieldValueNullId() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Test.startTest();
            RegressionTestAssertion.AssertionResult result =
                RegressionTestAssertion.assertFieldValue(null, 'Account', 'Name', 'Test');
            Test.stopTest();

            System.assertEquals(false, result.passed,
                'Null record ID should fail gracefully');
            System.assert(result.message.contains('required'),
                'Message should indicate ID is required, got: ' + result.message);
        }
    }

    @IsTest
    static void testAssertCoverage() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Test.startTest();
            // Use a class name that likely has no coverage data in test context
            RegressionTestAssertion.AssertionResult result =
                RegressionTestAssertion.assertCoverage('FakeNonExistentClass123', 75);
            Test.stopTest();

            System.assertEquals(false, result.passed,
                'Coverage assertion should fail for non-existent class');
            System.assert(result.message.contains('No coverage data'),
                'Message should indicate no coverage data, got: ' + result.message);
        }
    }

    @IsTest
    static void testAssertCoverageBlankClassName() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Test.startTest();
            RegressionTestAssertion.AssertionResult result =
                RegressionTestAssertion.assertCoverage('', 75);
            Test.stopTest();

            System.assertEquals(false, result.passed,
                'Blank class name should fail');
            System.assert(result.message.contains('required'),
                'Message should indicate className is required, got: ' + result.message);
        }
    }

    @IsTest
    static void testAssertNoGovernorViolation() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Test.startTest();
            // Use a class name that should have no governor violation records
            RegressionTestAssertion.AssertionResult result =
                RegressionTestAssertion.assertNoGovernorViolation('ForceGuardTestDataFactory');
            Test.stopTest();

            System.assertEquals(true, result.passed,
                'No governor violations expected for test data factory');
            System.assert(result.message.contains('PASSED'),
                'Message should contain PASSED, got: ' + result.message);
        }
    }

    @IsTest
    static void testAssertNoGovernorViolationBlankClass() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Test.startTest();
            RegressionTestAssertion.AssertionResult result =
                RegressionTestAssertion.assertNoGovernorViolation('');
            Test.stopTest();

            System.assertEquals(false, result.passed,
                'Blank test class name should fail');
            System.assert(result.message.contains('required'),
                'Message should indicate testClassName is required, got: ' + result.message);
        }
    }

    @IsTest
    static void testAssertRecordExistsNoWhereClause() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            // User records always exist in test context
            Test.startTest();
            RegressionTestAssertion.AssertionResult result =
                RegressionTestAssertion.assertRecordExists('User', '');
            Test.stopTest();

            System.assertEquals(true, result.passed,
                'User records should exist in any org');
        }
    }

    @IsTest
    static void testAssertRecordCountBlankObjectType() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Test.startTest();
            RegressionTestAssertion.AssertionResult result =
                RegressionTestAssertion.assertRecordCount('', '', 0);
            Test.stopTest();

            System.assertEquals(false, result.passed,
                'Blank sObjectType should fail');
            System.assert(result.message.contains('required'),
                'Message should indicate sObjectType is required, got: ' + result.message);
        }
    }

    @IsTest
    static void testAssertFieldValueMissingParameters() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Account acc = new Account(Name = 'ParamTest');
            insert acc;

            Test.startTest();
            RegressionTestAssertion.AssertionResult result =
                RegressionTestAssertion.assertFieldValue(acc.Id, '', '', 'Test');
            Test.stopTest();

            System.assertEquals(false, result.passed,
                'Missing objectType and fieldName should fail');
            System.assert(result.message.contains('required'),
                'Message should indicate required params, got: ' + result.message);
        }
    }

    @IsTest
    static void testAssertCoverageNullMinPercent() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Test.startTest();
            // Null minPercent should default to 75
            RegressionTestAssertion.AssertionResult result =
                RegressionTestAssertion.assertCoverage('SomeNonExistentClass', null);
            Test.stopTest();

            System.assertEquals(false, result.passed,
                'No coverage data should fail even with null minPercent');
        }
    }

    @IsTest
    static void testAssertEqualsNumericValues() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Test.startTest();
            RegressionTestAssertion.AssertionResult result =
                RegressionTestAssertion.assertEquals(42, 42, 'Integer equality');
            Test.stopTest();

            System.assertEquals(true, result.passed, 'Equal integers should pass');
        }
    }
}
