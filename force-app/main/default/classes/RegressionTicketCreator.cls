/**
 * RegressionTicketCreator - Creates tickets in an external project management system
 * for regression test failures detected by ForceGuard.
 * Uses Named Credentials for authentication and Regression_Config__mdt for configuration.
 */
public with sharing class RegressionTicketCreator {

    // Allow tests to override CMT config since CMT records cannot be inserted in tests
    @TestVisible
    private static Boolean testAutoTicketEnabled;
    @TestVisible
    private static String testNamedCredential;
    @TestVisible
    private static String testProjectId;

    /**
     * Inner class for InvocableMethod input.
     */
    public class RegressionTicketRequest {
        @InvocableVariable(required=true)
        public String testCaseTitle;
        @InvocableVariable(required=true)
        public String errorMessage;
        @InvocableVariable(required=true)
        public String suiteName;
        @InvocableVariable(required=true)
        public Id runId;
        @InvocableVariable(required=true)
        public Id resultId;
        @InvocableVariable
        public String priority;
    }

    /**
     * Creates tickets in an external system for regression failures.
     * Reads configuration from Regression_Config__mdt to determine whether
     * ticket creation is enabled, which Named Credential to use, and the project ID.
     * If a result already has an External_Ticket_Id__c, adds a comment instead.
     * @param requests List of RegressionTicketRequest records
     * @return List of external ticket IDs (or 'ERROR: {message}' for failures)
     */
    @InvocableMethod(label='Create Regression Ticket' description='Creates tickets in external system for regression failures')
    public static List<String> createTickets(List<RegressionTicketRequest> requests) {
        List<String> ticketIds = new List<String>();

        // Read configuration from Custom Metadata
        Boolean autoTicketEnabled = false;
        String namedCredential = '';
        String projectId = '';

        if (testAutoTicketEnabled != null) {
            autoTicketEnabled = testAutoTicketEnabled;
            namedCredential = testNamedCredential;
            projectId = testProjectId;
        } else {
            List<Regression_Config__mdt> configs = [
                SELECT Auto_Ticket_Enabled__c, Ticket_System_Named_Credential__c,
                       Ticket_Project_Id__c
                FROM Regression_Config__mdt
                WHERE DeveloperName = 'Default'
                WITH SYSTEM_MODE
                LIMIT 1
            ];

            if (!configs.isEmpty()) {
                autoTicketEnabled = configs[0].Auto_Ticket_Enabled__c;
                namedCredential = configs[0].Ticket_System_Named_Credential__c;
                projectId = configs[0].Ticket_Project_Id__c;
            }
        }

        if (!autoTicketEnabled) {
            for (Integer i = 0; i < requests.size(); i++) {
                ticketIds.add('');
            }
            return ticketIds;
        }

        // Collect result IDs to check for existing tickets
        Set<Id> resultIds = new Set<Id>();
        for (RegressionTicketRequest req : requests) {
            resultIds.add(req.resultId);
        }

        Map<Id, Regression_Test_Result__c> existingResults = new Map<Id, Regression_Test_Result__c>([
            SELECT Id, External_Ticket_Id__c
            FROM Regression_Test_Result__c
            WHERE Id IN :resultIds
            WITH SYSTEM_MODE
        ]);

        List<Regression_Test_Result__c> resultsToUpdate = new List<Regression_Test_Result__c>();

        for (RegressionTicketRequest req : requests) {
            Regression_Test_Result__c existingResult = existingResults.get(req.resultId);
            String existingTicketId = existingResult != null ? existingResult.External_Ticket_Id__c : null;

            if (String.isNotBlank(existingTicketId)) {
                // Add comment to existing ticket instead of creating new one
                String comment = '## Re-occurrence\n\n'
                    + '**Suite:** ' + req.suiteName + '\n'
                    + '**Run ID:** ' + req.runId + '\n\n'
                    + '### Error Message\n```\n' + req.errorMessage + '\n```';
                addComment(namedCredential, existingTicketId, comment);
                ticketIds.add(existingTicketId);
            } else {
                // Create new ticket
                String ticketId = createTicket(namedCredential, projectId, req);
                ticketIds.add(ticketId);

                if (!ticketId.startsWith('ERROR:')) {
                    resultsToUpdate.add(new Regression_Test_Result__c(
                        Id = req.resultId,
                        External_Ticket_Id__c = ticketId
                    ));
                }
            }
        }

        if (!resultsToUpdate.isEmpty()) {
            update resultsToUpdate;
        }

        return ticketIds;
    }

    /**
     * Creates a single ticket in the external system.
     * @param namedCredential The Named Credential developer name
     * @param projectId The project ID in the external system
     * @param req The ticket request details
     * @return The external ticket ID or 'ERROR: {message}'
     */
    private static String createTicket(String namedCredential, String projectId,
            RegressionTicketRequest req) {
        String priorityHref = mapPriority(req.priority);

        String description = '## Regression Failure\n\n'
            + '**Suite:** ' + req.suiteName + '\n'
            + '**Test Case:** ' + req.testCaseTitle + '\n'
            + '**Priority:** ' + (req.priority != null ? req.priority : 'Medium') + '\n'
            + '**Run ID:** ' + req.runId + '\n\n'
            + '### Error Message\n```\n' + req.errorMessage + '\n```\n\n'
            + '---\n*Created by ForceGuard Regression Testing*';

        Map<String, Object> payload = new Map<String, Object>{
            'subject' => '[ForceGuard Regression] ' + req.testCaseTitle,
            '_links' => new Map<String, Object>{
                'type' => new Map<String, String>{ 'href' => '/api/v3/types/1' },
                'priority' => new Map<String, String>{ 'href' => priorityHref }
            },
            'description' => new Map<String, String>{
                'format' => 'markdown',
                'raw' => description
            }
        };

        String endpoint = 'callout:' + namedCredential
            + '/api/v3/projects/' + projectId + '/work_packages';

        try {
            HttpRequest httpReq = new HttpRequest();
            httpReq.setEndpoint(endpoint);
            httpReq.setMethod('POST');
            httpReq.setHeader('Content-Type', 'application/json');
            httpReq.setBody(JSON.serialize(payload));
            httpReq.setTimeout(30000);

            Http http = new Http();
            HttpResponse res = http.send(httpReq);

            Integer statusCode = res.getStatusCode();

            if (statusCode == 201 || statusCode == 200) {
                Map<String, Object> responseBody =
                    (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                Object idValue = responseBody.get('id');
                return idValue != null ? String.valueOf(idValue) : 'ERROR: No ID in response';
            } else if (statusCode == 401) {
                return 'ERROR: Authentication failed for ticket system';
            } else if (statusCode == 429) {
                return 'ERROR: Rate limited by ticket system';
            } else {
                return 'ERROR: HTTP ' + statusCode + ' - ' + res.getBody();
            }
        } catch (Exception e) {
            return 'ERROR: ' + e.getMessage();
        }
    }

    /**
     * Adds a comment to an existing ticket in the external system.
     * @param namedCredential The Named Credential developer name
     * @param ticketId The external ticket ID
     * @param comment The comment text in markdown format
     */
    private static void addComment(String namedCredential, String ticketId, String comment) {
        String endpoint = 'callout:' + namedCredential
            + '/api/v3/work_packages/' + ticketId + '/activities';

        Map<String, Object> payload = new Map<String, Object>{
            'comment' => new Map<String, String>{
                'format' => 'markdown',
                'raw' => comment
            }
        };

        try {
            HttpRequest httpReq = new HttpRequest();
            httpReq.setEndpoint(endpoint);
            httpReq.setMethod('POST');
            httpReq.setHeader('Content-Type', 'application/json');
            httpReq.setBody(JSON.serialize(payload));
            httpReq.setTimeout(30000);

            Http http = new Http();
            http.send(httpReq);
        } catch (Exception e) {
            // Log but do not throw - comment failure should not break the flow
        }
    }

    /**
     * Maps ForceGuard priority to external system priority href.
     * @param priority The ForceGuard priority string
     * @return The priority href for the external API
     */
    @TestVisible
    private static String mapPriority(String priority) {
        if (priority == null) {
            return '/api/v3/priorities/6';
        }
        switch on priority.toLowerCase() {
            when 'critical' {
                return '/api/v3/priorities/8';
            }
            when 'high' {
                return '/api/v3/priorities/7';
            }
            when 'medium' {
                return '/api/v3/priorities/6';
            }
            when 'low' {
                return '/api/v3/priorities/5';
            }
            when else {
                return '/api/v3/priorities/6';
            }
        }
    }
}
