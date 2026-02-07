/**
 * RegressionTicketCreatorTest - Tests for the RegressionTicketCreator class.
 * Covers: ticket creation success, disabled config, existing ticket comment,
 * authentication failure, rate limiting, and bulk processing.
 */
@IsTest
private class RegressionTicketCreatorTest {

    /**
     * Configurable HttpCalloutMock for ticket system API responses.
     */
    private class TicketCreatorMock implements HttpCalloutMock {
        private Integer statusCode;
        private String body;

        public TicketCreatorMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(statusCode);
            res.setBody(body);
            return res;
        }
    }

    @TestSetup
    static void setup() {
        User testUser = ForceGuardTestDataFactory.createTestUser();

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = ForceGuardTestDataFactory.createSuite('Ticket Test Product');
            insert suite;

            List<Regression_Test_Case__c> cases = ForceGuardTestDataFactory.createTestCases(suite.Id, 4);
            insert cases;

            Regression_Test_Run__c run = new Regression_Test_Run__c(
                Test_Suite__c = suite.Id,
                Run_Date__c = DateTime.now(),
                Status__c = 'Failed',
                Triggered_By__c = 'Manual',
                Run_By__c = UserInfo.getUserId(),
                Total_Tests__c = 4,
                Passed__c = 2,
                Failed__c = 2,
                Skipped__c = 0
            );
            insert run;

            List<Regression_Test_Result__c> results = new List<Regression_Test_Result__c>();
            for (Integer i = 0; i < cases.size(); i++) {
                String status = (i < 2) ? 'Passed' : 'Failed';
                Regression_Test_Result__c result = new Regression_Test_Result__c(
                    Test_Run__c = run.Id,
                    Test_Case__c = cases[i].Id,
                    Status__c = status,
                    Layer__c = cases[i].Test_Layer__c,
                    Duration_Ms__c = 100,
                    Is_Regression__c = false
                );
                if (status == 'Failed') {
                    result.Error_Message__c = 'Assertion failed for case ' + (i + 1);
                }
                results.add(result);
            }
            insert results;
        }
    }

    @IsTest
    static void testCreateTicketSuccess() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];
            Regression_Test_Result__c failedResult = [
                SELECT Id, Test_Case__r.Title__c, Error_Message__c, Layer__c
                FROM Regression_Test_Result__c
                WHERE Status__c = 'Failed' AND Test_Run__c = :run.Id
                LIMIT 1
            ];

            // Override CMT config for test
            RegressionTicketCreator.testAutoTicketEnabled = true;
            RegressionTicketCreator.testNamedCredential = 'ForceGuard_Ticket_System';
            RegressionTicketCreator.testProjectId = '9';

            RegressionTicketCreator.RegressionTicketRequest req =
                new RegressionTicketCreator.RegressionTicketRequest();
            req.testCaseTitle = failedResult.Test_Case__r.Title__c;
            req.errorMessage = failedResult.Error_Message__c;
            req.suiteName = 'Ticket Test Product';
            req.runId = run.Id;
            req.resultId = failedResult.Id;
            req.priority = 'High';

            // Mock 201 success response with ticket ID
            Test.setMock(HttpCalloutMock.class, new TicketCreatorMock(
                201, '{"id": 42, "subject": "[ForceGuard Regression] Test Case 3"}'
            ));

            Test.startTest();
            List<String> results = RegressionTicketCreator.createTickets(
                new List<RegressionTicketCreator.RegressionTicketRequest>{ req }
            );
            Test.stopTest();

            System.assertEquals(1, results.size(), 'Should return 1 ticket ID');
            System.assertEquals('42', results[0], 'Ticket ID should be 42');

            // Verify External_Ticket_Id__c was populated
            Regression_Test_Result__c updatedResult = [
                SELECT External_Ticket_Id__c
                FROM Regression_Test_Result__c
                WHERE Id = :failedResult.Id
            ];
            System.assertEquals('42', updatedResult.External_Ticket_Id__c,
                'External_Ticket_Id__c should be set to 42');
        }
    }

    @IsTest
    static void testCreateTicketDisabled() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];
            Regression_Test_Result__c failedResult = [
                SELECT Id, Test_Case__r.Title__c, Error_Message__c
                FROM Regression_Test_Result__c
                WHERE Status__c = 'Failed' AND Test_Run__c = :run.Id
                LIMIT 1
            ];

            // Auto ticket disabled (default behavior - no @TestVisible override)
            // CMT Default record has Auto_Ticket_Enabled__c = false

            RegressionTicketCreator.RegressionTicketRequest req =
                new RegressionTicketCreator.RegressionTicketRequest();
            req.testCaseTitle = failedResult.Test_Case__r.Title__c;
            req.errorMessage = failedResult.Error_Message__c;
            req.suiteName = 'Ticket Test Product';
            req.runId = run.Id;
            req.resultId = failedResult.Id;
            req.priority = 'Medium';

            Test.startTest();
            List<String> results = RegressionTicketCreator.createTickets(
                new List<RegressionTicketCreator.RegressionTicketRequest>{ req }
            );
            Test.stopTest();

            System.assertEquals(1, results.size(), 'Should return 1 entry');
            System.assertEquals('', results[0],
                'Should return empty string when auto-ticket is disabled');
        }
    }

    @IsTest
    static void testAddCommentWhenTicketExists() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];
            Regression_Test_Result__c failedResult = [
                SELECT Id, Test_Case__r.Title__c, Error_Message__c
                FROM Regression_Test_Result__c
                WHERE Status__c = 'Failed' AND Test_Run__c = :run.Id
                LIMIT 1
            ];

            // Set existing ticket ID on the result
            failedResult.External_Ticket_Id__c = '99';
            update failedResult;

            RegressionTicketCreator.testAutoTicketEnabled = true;
            RegressionTicketCreator.testNamedCredential = 'ForceGuard_Ticket_System';
            RegressionTicketCreator.testProjectId = '9';

            RegressionTicketCreator.RegressionTicketRequest req =
                new RegressionTicketCreator.RegressionTicketRequest();
            req.testCaseTitle = failedResult.Test_Case__r.Title__c;
            req.errorMessage = failedResult.Error_Message__c;
            req.suiteName = 'Ticket Test Product';
            req.runId = run.Id;
            req.resultId = failedResult.Id;
            req.priority = 'Critical';

            // Mock comment endpoint (200 for activity creation)
            Test.setMock(HttpCalloutMock.class, new TicketCreatorMock(
                200, '{"id": 501, "comment": {"raw": "Re-occurrence"}}'
            ));

            Test.startTest();
            List<String> results = RegressionTicketCreator.createTickets(
                new List<RegressionTicketCreator.RegressionTicketRequest>{ req }
            );
            Test.stopTest();

            System.assertEquals(1, results.size(), 'Should return 1 entry');
            System.assertEquals('99', results[0],
                'Should return existing ticket ID, not create a new one');
        }
    }

    @IsTest
    static void testAuthenticationFailure() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];
            Regression_Test_Result__c failedResult = [
                SELECT Id, Test_Case__r.Title__c, Error_Message__c
                FROM Regression_Test_Result__c
                WHERE Status__c = 'Failed' AND Test_Run__c = :run.Id
                LIMIT 1
            ];

            RegressionTicketCreator.testAutoTicketEnabled = true;
            RegressionTicketCreator.testNamedCredential = 'ForceGuard_Ticket_System';
            RegressionTicketCreator.testProjectId = '9';

            RegressionTicketCreator.RegressionTicketRequest req =
                new RegressionTicketCreator.RegressionTicketRequest();
            req.testCaseTitle = failedResult.Test_Case__r.Title__c;
            req.errorMessage = failedResult.Error_Message__c;
            req.suiteName = 'Ticket Test Product';
            req.runId = run.Id;
            req.resultId = failedResult.Id;
            req.priority = 'High';

            // Mock 401 authentication failure
            Test.setMock(HttpCalloutMock.class, new TicketCreatorMock(
                401, '{"message": "Unauthorized"}'
            ));

            Test.startTest();
            List<String> results = RegressionTicketCreator.createTickets(
                new List<RegressionTicketCreator.RegressionTicketRequest>{ req }
            );
            Test.stopTest();

            System.assertEquals(1, results.size(), 'Should return 1 entry');
            System.assert(results[0].startsWith('ERROR:'),
                'Should return error string for 401');
            System.assert(results[0].contains('Authentication failed'),
                'Error should mention authentication: ' + results[0]);

            // Verify External_Ticket_Id__c was NOT set
            Regression_Test_Result__c updatedResult = [
                SELECT External_Ticket_Id__c
                FROM Regression_Test_Result__c
                WHERE Id = :failedResult.Id
            ];
            System.assertEquals(null, updatedResult.External_Ticket_Id__c,
                'External_Ticket_Id__c should remain null on auth failure');
        }
    }

    @IsTest
    static void testRateLimitHandling() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];
            Regression_Test_Result__c failedResult = [
                SELECT Id, Test_Case__r.Title__c, Error_Message__c
                FROM Regression_Test_Result__c
                WHERE Status__c = 'Failed' AND Test_Run__c = :run.Id
                LIMIT 1
            ];

            RegressionTicketCreator.testAutoTicketEnabled = true;
            RegressionTicketCreator.testNamedCredential = 'ForceGuard_Ticket_System';
            RegressionTicketCreator.testProjectId = '9';

            RegressionTicketCreator.RegressionTicketRequest req =
                new RegressionTicketCreator.RegressionTicketRequest();
            req.testCaseTitle = failedResult.Test_Case__r.Title__c;
            req.errorMessage = failedResult.Error_Message__c;
            req.suiteName = 'Ticket Test Product';
            req.runId = run.Id;
            req.resultId = failedResult.Id;
            req.priority = 'Low';

            // Mock 429 rate limit
            Test.setMock(HttpCalloutMock.class, new TicketCreatorMock(
                429, '{"message": "Too many requests"}'
            ));

            Test.startTest();
            List<String> results = RegressionTicketCreator.createTickets(
                new List<RegressionTicketCreator.RegressionTicketRequest>{ req }
            );
            Test.stopTest();

            System.assertEquals(1, results.size(), 'Should return 1 entry');
            System.assert(results[0].startsWith('ERROR:'),
                'Should return error string for 429');
            System.assert(results[0].contains('Rate limited'),
                'Error should mention rate limiting: ' + results[0]);
        }
    }

    @IsTest
    static void testBulkRequests() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = [SELECT Id FROM Regression_Test_Suite__c LIMIT 1];
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];

            // Create additional failed results for bulk test
            List<Regression_Test_Case__c> bulkCases =
                ForceGuardTestDataFactory.createBulkTestCases(suite.Id, 5, 'Apex Test');
            insert bulkCases;

            List<Regression_Test_Result__c> bulkResults = new List<Regression_Test_Result__c>();
            for (Regression_Test_Case__c tc : bulkCases) {
                bulkResults.add(new Regression_Test_Result__c(
                    Test_Run__c = run.Id,
                    Test_Case__c = tc.Id,
                    Status__c = 'Failed',
                    Layer__c = tc.Test_Layer__c,
                    Duration_Ms__c = 50,
                    Error_Message__c = 'Bulk failure for ' + tc.Title__c
                ));
            }
            insert bulkResults;

            RegressionTicketCreator.testAutoTicketEnabled = true;
            RegressionTicketCreator.testNamedCredential = 'ForceGuard_Ticket_System';
            RegressionTicketCreator.testProjectId = '9';

            List<RegressionTicketCreator.RegressionTicketRequest> requests =
                new List<RegressionTicketCreator.RegressionTicketRequest>();
            Integer ticketCounter = 100;
            for (Integer i = 0; i < bulkResults.size(); i++) {
                RegressionTicketCreator.RegressionTicketRequest req =
                    new RegressionTicketCreator.RegressionTicketRequest();
                req.testCaseTitle = bulkCases[i].Title__c;
                req.errorMessage = bulkResults[i].Error_Message__c;
                req.suiteName = 'Ticket Test Product';
                req.runId = run.Id;
                req.resultId = bulkResults[i].Id;
                req.priority = 'Medium';
                requests.add(req);
            }

            // Mock 201 for all requests (single mock applies to all callouts)
            Test.setMock(HttpCalloutMock.class, new TicketCreatorMock(
                201, '{"id": 100, "subject": "Bulk ticket"}'
            ));

            Test.startTest();
            List<String> results = RegressionTicketCreator.createTickets(requests);
            Test.stopTest();

            System.assertEquals(5, results.size(), 'Should return 5 ticket IDs');
            for (String ticketId : results) {
                System.assertEquals('100', ticketId,
                    'Each ticket ID should be 100 (from mock)');
            }

            // Verify all results got External_Ticket_Id__c
            List<Regression_Test_Result__c> updatedResults = [
                SELECT External_Ticket_Id__c
                FROM Regression_Test_Result__c
                WHERE Id IN :bulkResults
            ];
            for (Regression_Test_Result__c r : updatedResults) {
                System.assertEquals('100', r.External_Ticket_Id__c,
                    'All bulk results should have External_Ticket_Id__c set');
            }
        }
    }

    @IsTest
    static void testPriorityMapping() {
        System.assertEquals('/api/v3/priorities/8', RegressionTicketCreator.mapPriority('Critical'),
            'Critical should map to priority 8');
        System.assertEquals('/api/v3/priorities/7', RegressionTicketCreator.mapPriority('High'),
            'High should map to priority 7');
        System.assertEquals('/api/v3/priorities/6', RegressionTicketCreator.mapPriority('Medium'),
            'Medium should map to priority 6');
        System.assertEquals('/api/v3/priorities/5', RegressionTicketCreator.mapPriority('Low'),
            'Low should map to priority 5');
        System.assertEquals('/api/v3/priorities/6', RegressionTicketCreator.mapPriority(null),
            'Null should default to priority 6');
        System.assertEquals('/api/v3/priorities/6', RegressionTicketCreator.mapPriority('Unknown'),
            'Unknown priority should default to priority 6');
    }
}
