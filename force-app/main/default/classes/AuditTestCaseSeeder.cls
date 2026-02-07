/**
 * @description Seeds all regression test cases for the User Access Audit product.
 * Creates 1 test suite and 63 test cases covering all 4 testing layers.
 * Idempotent - safe to re-run without creating duplicates.
 *
 * Usage: Execute via Anonymous Apex
 *   AuditTestCaseSeeder.seed();
 *
 * @author ForceGuard
 * @date 2026-02-07
 */
public with sharing class AuditTestCaseSeeder {

    private static final String SUITE_NAME = 'User Access Audit Test Suite';
    private static final String PRODUCT_NAME = 'User Access Audit';

    /**
     * @description Main entry point - seeds all test data
     */
    public static void seed() {
        // Check for existing suite and clean up
        List<Regression_Test_Suite__c> existingSuites = [
            SELECT Id
            FROM Regression_Test_Suite__c
            WHERE Product_Name__c = :PRODUCT_NAME
            LIMIT 1
        ];

        if (!existingSuites.isEmpty()) {
            // Delete existing test cases first (cascade)
            List<Regression_Test_Case__c> existingCases = [
                SELECT Id
                FROM Regression_Test_Case__c
                WHERE Test_Suite__c = :existingSuites[0].Id
            ];

            if (!existingCases.isEmpty()) {
                delete existingCases;
            }

            delete existingSuites;
        }

        // Create new suite
        Regression_Test_Suite__c suite = createSuite();
        insert suite;

        // Create all test cases
        List<Regression_Test_Case__c> allCases = new List<Regression_Test_Case__c>();
        allCases.addAll(createLayer1DeploymentTests(suite.Id));
        allCases.addAll(createLayer2ApexTests(suite.Id));
        allCases.addAll(createLayer3DataScenarioTests(suite.Id));
        allCases.addAll(createLayer4StaticAnalysisTests(suite.Id));
        allCases.addAll(createEdgeCaseTests(suite.Id));
        allCases.addAll(createBulkTests(suite.Id));
        allCases.addAll(createSecurityTests(suite.Id));

        insert allCases;

        System.debug('Seeded ' + allCases.size() + ' test cases for suite: ' + suite.Name);
    }

    /**
     * @description Creates the test suite record
     */
    private static Regression_Test_Suite__c createSuite() {
        return new Regression_Test_Suite__c(
            Name = SUITE_NAME,
            Product_Name__c = PRODUCT_NAME,
            Version__c = '1.0',
            Description__c = 'Comprehensive regression test suite for the User Access Audit (SOX/IPE) product. Tests all 4 layers: deployment validation, Apex test execution, data scenario testing, and static analysis.',
            Is_Active__c = true,
            Source_Path__c = 'change-requests/Audit',
            Product_Namespace__c = ''
        );
    }

    /**
     * @description LAYER 1 - Deployment Validation Tests (6 tests)
     */
    private static List<Regression_Test_Case__c> createLayer1DeploymentTests(Id suiteId) {
        List<Regression_Test_Case__c> cases = new List<Regression_Test_Case__c>();

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Deploy All Audit Apex Classes',
            Description__c = 'Validates all 35 non-test Apex classes compile and deploy without errors.',
            Test_Layer__c = 'Deployment',
            Category__c = 'Deployment',
            Perspective__c = 'Developer',
            Priority__c = 'P0',
            Target_Object__c = 'ApexClass',
            Execution_Order__c = 100,
            Is_Active__c = true,
            Assertion_Type__c = 'No Error',
            Steps__c = 'Deploy the following 35 classes:\n' +
                '1. UserAuditSnapshotBatch\n2. AuditController\n3. AuditControlCenterController\n' +
                '4. AuditFeatureService\n5. BaselineSnapshotService\n6. TerminationCrossCheckService\n' +
                '7. ProfileChangeDetector\n8. LoginHistoryService\n9. SegregationOfDutiesService\n' +
                '10. SetupAuditTrailService\n11. AuditReportService\n12. AuditSummaryPdfGenerator\n' +
                '13. AuditSummaryEmailService\n14. QuarterlySignOffService\n15. FindingAssignmentService\n' +
                '16. OverdueRemediationService\n17. SnapshotDuplicateDetectionService\n18. AccessReviewService\n' +
                '19. CMTicketValidationService\n20. DeploymentAuthorizationService\n21. UserDeactivationHandler\n' +
                '22. UserDeactivationQueueable\n23. TerminationCrossCheckQueueable\n24. ProfileChangeDetectorQueueable\n' +
                '25. BaselineComparisonController\n26. QuarterlyReviewController\n27. PermissionSetViewerController\n' +
                '28. AuditSummaryScheduler\n29. SlaStatusCalculatorService\n30. RemediationDueDateService\n' +
                '31. AuditFindingCounter\n32. AuditSchedulerService\n33. ComplianceReportService\n' +
                '34. ExportService\n35. NotificationService',
            Expected_Result__c = 'All 35 classes compile and deploy without errors. No deployment failures.',
            Related_Metadata__c = 'All audit Apex classes',
            Tags__c = 'deployment,apex,compilation'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Deploy All Audit Test Classes',
            Description__c = 'Validates all 35 test classes plus test data factory compile and deploy.',
            Test_Layer__c = 'Deployment',
            Category__c = 'Deployment',
            Perspective__c = 'Developer',
            Priority__c = 'P0',
            Target_Object__c = 'ApexClass',
            Execution_Order__c = 101,
            Is_Active__c = true,
            Assertion_Type__c = 'No Error',
            Steps__c = 'Deploy all 36 test classes (35 tests + UserAuditTestDataFactory):\n' +
                'UserAuditSnapshotBatchTest, AuditControllerTest, AuditControlCenterControllerTest, ' +
                'AuditFeatureServiceTest, BaselineSnapshotServiceTest, TerminationCrossCheckServiceTest, ' +
                'ProfileChangeDetectorTest, LoginHistoryServiceTest, SegregationOfDutiesServiceTest, ' +
                'SetupAuditTrailServiceTest, AuditReportServiceTest, AuditSummaryPdfGeneratorTest, ' +
                'AuditSummaryEmailServiceTest, QuarterlySignOffServiceTest, FindingAssignmentServiceTest, ' +
                'OverdueRemediationServiceTest, SnapshotDuplicateDetectionServiceTest, AccessReviewServiceTest, ' +
                'CMTicketValidationServiceTest, DeploymentAuthorizationServiceTest, UserDeactivationHandlerTest, ' +
                'UserDeactivationQueueableTest, TerminationCrossCheckQueueableTest, ProfileChangeDetectorQueueableTest, ' +
                'BaselineComparisonControllerTest, QuarterlyReviewControllerTest, PermissionSetViewerControllerTest, ' +
                'AuditSummarySchedulerTest, SlaStatusCalculatorServiceTest, RemediationDueDateServiceTest, ' +
                'AuditFindingCounterTest, AuditSchedulerServiceTest, ComplianceReportServiceTest, ' +
                'ExportServiceTest, NotificationServiceTest, UserAuditTestDataFactory',
            Expected_Result__c = 'All test classes compile and deploy successfully.',
            Related_Metadata__c = 'All audit test classes',
            Tags__c = 'deployment,test,compilation'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Deploy All Audit Custom Objects',
            Description__c = 'Validates all 7 custom objects deploy with fields, relationships, and validation rules.',
            Test_Layer__c = 'Deployment',
            Category__c = 'Deployment',
            Perspective__c = 'Admin',
            Priority__c = 'P0',
            Target_Object__c = 'CustomObject',
            Execution_Order__c = 102,
            Is_Active__c = true,
            Assertion_Type__c = 'No Error',
            Steps__c = 'Deploy the following custom objects with all metadata:\n' +
                '1. Audit_Run__c (fields, validation rules, page layouts)\n' +
                '2. User_Audit_Snapshot__c (fields, M-D relationship to Audit_Run__c)\n' +
                '3. Audit_Finding__c (fields, M-D to Audit_Run__c)\n' +
                '4. Termination_Record__c (fields, validation rules)\n' +
                '5. Change_Request__c (fields, lookup to Audit_Finding__c)\n' +
                '6. Login_Anomaly__c (fields, lookup to User_Audit_Snapshot__c)\n' +
                '7. Setup_Change_Log__c (fields, audit trail)',
            Expected_Result__c = 'All 7 objects deploy successfully with all fields, relationships, and validation rules intact.',
            Related_Metadata__c = 'Audit_Run__c,User_Audit_Snapshot__c,Audit_Finding__c,Termination_Record__c,Change_Request__c,Login_Anomaly__c,Setup_Change_Log__c',
            Tags__c = 'deployment,objects,schema'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Deploy All Audit Flows',
            Description__c = 'Validates all 8 Record-Triggered Flows deploy and activate successfully.',
            Test_Layer__c = 'Deployment',
            Category__c = 'Deployment',
            Perspective__c = 'Admin',
            Priority__c = 'P0',
            Target_Object__c = 'Flow',
            Execution_Order__c = 103,
            Is_Active__c = true,
            Assertion_Type__c = 'No Error',
            Steps__c = 'Deploy and activate the following Flows:\n' +
                '1. Set_Latest_Flag_On_New_Audit_Run (Audit_Run__c, before-save)\n' +
                '2. Set_Latest_Audit_Run (Audit_Run__c, after-save)\n' +
                '3. Audit_Run_Status_Update (Audit_Run__c, after-save)\n' +
                '4. Notify_Audit_Team (Audit_Run__c, after-save)\n' +
                '5. Set_Assignment_Date (Audit_Finding__c, before-save)\n' +
                '6. Set_Remediation_Due_Date (Audit_Finding__c, before-save)\n' +
                '7. Update_SLA_Status (Audit_Finding__c, scheduled)\n' +
                '8. Access_Review_Attestation (Audit_Finding__c, screen flow)',
            Expected_Result__c = 'All 8 Flows deploy and activate without errors. No flow interview errors on activation.',
            Related_Metadata__c = 'Set_Latest_Flag_On_New_Audit_Run,Set_Latest_Audit_Run,Audit_Run_Status_Update,Notify_Audit_Team,Set_Assignment_Date,Set_Remediation_Due_Date,Update_SLA_Status,Access_Review_Attestation',
            Tags__c = 'deployment,flow,automation'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Deploy All Audit LWC Components',
            Description__c = 'Validates all 7 Lightning Web Components deploy without JavaScript errors.',
            Test_Layer__c = 'Deployment',
            Category__c = 'Deployment',
            Perspective__c = 'Developer',
            Priority__c = 'P1',
            Target_Object__c = 'LightningComponentBundle',
            Execution_Order__c = 104,
            Is_Active__c = true,
            Assertion_Type__c = 'No Error',
            Steps__c = 'Deploy the following LWC components:\n' +
                '1. auditControlCenter (main dashboard)\n' +
                '2. auditDashboard (metrics and charts)\n' +
                '3. baselineComparison (baseline vs current)\n' +
                '4. findingsReview (finding triage UI)\n' +
                '5. permissionSetViewer (permission set details)\n' +
                '6. quarterlyReview (quarterly sign-off UI)\n' +
                '7. terminationImporter (CSV import UI)',
            Expected_Result__c = 'All 7 LWC deploy successfully. No JavaScript compilation errors. All components render without console errors.',
            Related_Metadata__c = 'auditControlCenter,auditDashboard,baselineComparison,findingsReview,permissionSetViewer,quarterlyReview,terminationImporter',
            Tags__c = 'deployment,lwc,javascript'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Deploy Audit Permission Sets and CMTs',
            Description__c = 'Validates all permission sets and Custom Metadata Types deploy successfully.',
            Test_Layer__c = 'Deployment',
            Category__c = 'Deployment',
            Perspective__c = 'Admin',
            Priority__c = 'P1',
            Target_Object__c = 'PermissionSet',
            Execution_Order__c = 105,
            Is_Active__c = true,
            Assertion_Type__c = 'No Error',
            Steps__c = 'Deploy the following metadata:\n' +
                'Permission Sets:\n  - Audit_Administrator (full access + bypass)\n  - Audit_Full_Access (CRUD all objects)\n  - Audit_Viewer (read-only)\n\n' +
                'Custom Metadata Types:\n  - Audit_Feature_Setting__mdt (17 records)\n  - Segregation_Rule__mdt (10 records)\n  - Approved_Deployer__mdt\n  - Audit_Summary_Recipient__mdt (3 records)',
            Expected_Result__c = 'All permission sets deploy with correct object/field permissions. All CMT records deploy successfully.',
            Related_Metadata__c = 'Audit_Administrator,Audit_Full_Access,Audit_Viewer,Audit_Feature_Setting__mdt,Segregation_Rule__mdt,Approved_Deployer__mdt,Audit_Summary_Recipient__mdt',
            Tags__c = 'deployment,permissions,metadata'
        ));

        return cases;
    }

    /**
     * @description LAYER 2 - Apex Test Execution (10 tests)
     */
    private static List<Regression_Test_Case__c> createLayer2ApexTests(Id suiteId) {
        List<Regression_Test_Case__c> cases = new List<Regression_Test_Case__c>();

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Core Batch and Snapshot Tests',
            Description__c = 'Executes tests for batch job and snapshot duplicate detection.',
            Test_Layer__c = 'Apex Test',
            Category__c = 'Functional',
            Perspective__c = 'Developer',
            Priority__c = 'P0',
            Target_Object__c = 'ApexClass',
            Execution_Order__c = 200,
            Is_Active__c = true,
            Assertion_Type__c = 'Coverage Threshold',
            Steps__c = 'Run the following test classes:\n  - UserAuditSnapshotBatchTest\n  - SnapshotDuplicateDetectionServiceTest\n\n' +
                'Verify:\n  - All test methods pass\n  - Coverage >= 85% on UserAuditSnapshotBatch\n  - Coverage >= 85% on SnapshotDuplicateDetectionService',
            Expected_Result__c = 'All tests pass. Coverage >= 85% on batch and snapshot classes.',
            Related_Metadata__c = 'UserAuditSnapshotBatch,SnapshotDuplicateDetectionService',
            Tags__c = 'apex-test,batch,snapshot,core'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Detection Service Tests',
            Description__c = 'Executes tests for all detection services (profile, termination, login, SoD).',
            Test_Layer__c = 'Apex Test',
            Category__c = 'Functional',
            Perspective__c = 'Developer',
            Priority__c = 'P0',
            Target_Object__c = 'ApexClass',
            Execution_Order__c = 201,
            Is_Active__c = true,
            Assertion_Type__c = 'Coverage Threshold',
            Steps__c = 'Run the following test classes:\n  - ProfileChangeDetectorTest\n  - TerminationCrossCheckServiceTest\n  - LoginHistoryServiceTest\n  - SegregationOfDutiesServiceTest\n\n' +
                'Verify coverage >= 85% on all detection service classes.',
            Expected_Result__c = 'All tests pass. Coverage >= 85% on all detection classes.',
            Related_Metadata__c = 'ProfileChangeDetector,TerminationCrossCheckService,LoginHistoryService,SegregationOfDutiesService',
            Tags__c = 'apex-test,detection,services'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Queueable Chain Tests',
            Description__c = 'Executes tests for all queueable chain classes.',
            Test_Layer__c = 'Apex Test',
            Category__c = 'Functional',
            Perspective__c = 'Developer',
            Priority__c = 'P0',
            Target_Object__c = 'ApexClass',
            Execution_Order__c = 202,
            Is_Active__c = true,
            Assertion_Type__c = 'Coverage Threshold',
            Steps__c = 'Run the following test classes:\n  - TerminationCrossCheckQueueableTest\n  - ProfileChangeDetectorQueueableTest\n  - UserDeactivationQueueableTest\n\n' +
                'Verify queueable chain executes without errors and coverage >= 85%.',
            Expected_Result__c = 'All tests pass. Queueable chain executes successfully. Coverage >= 85%.',
            Related_Metadata__c = 'TerminationCrossCheckQueueable,ProfileChangeDetectorQueueable,UserDeactivationQueueable',
            Tags__c = 'apex-test,queueable,async'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Reporting and PDF Tests',
            Description__c = 'Executes tests for report generation, PDF generation, and email services.',
            Test_Layer__c = 'Apex Test',
            Category__c = 'Functional',
            Perspective__c = 'Developer',
            Priority__c = 'P1',
            Target_Object__c = 'ApexClass',
            Execution_Order__c = 203,
            Is_Active__c = true,
            Assertion_Type__c = 'Coverage Threshold',
            Steps__c = 'Run the following test classes:\n  - AuditReportServiceTest\n  - AuditSummaryPdfGeneratorTest\n  - AuditSummaryEmailServiceTest\n\n' +
                'Verify PDF generation and email sending logic covered.',
            Expected_Result__c = 'All tests pass. PDF and email generation verified. Coverage >= 85%.',
            Related_Metadata__c = 'AuditReportService,AuditSummaryPdfGenerator,AuditSummaryEmailService',
            Tags__c = 'apex-test,reporting,pdf,email'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Controller Tests',
            Description__c = 'Executes tests for all @AuraEnabled controller methods.',
            Test_Layer__c = 'Apex Test',
            Category__c = 'Functional',
            Perspective__c = 'Developer',
            Priority__c = 'P0',
            Target_Object__c = 'ApexClass',
            Execution_Order__c = 204,
            Is_Active__c = true,
            Assertion_Type__c = 'Coverage Threshold',
            Steps__c = 'Run the following test classes:\n  - AuditControllerTest\n  - AuditControlCenterControllerTest\n\n' +
                'Verify all @AuraEnabled methods are tested with positive and negative scenarios.',
            Expected_Result__c = 'All tests pass. All @AuraEnabled methods covered. Coverage >= 85%.',
            Related_Metadata__c = 'AuditController,AuditControlCenterController',
            Tags__c = 'apex-test,controller,lwc-backend'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Review and Compliance Tests',
            Description__c = 'Executes tests for quarterly review, baseline comparison, and sign-off workflows.',
            Test_Layer__c = 'Apex Test',
            Category__c = 'Functional',
            Perspective__c = 'Admin',
            Priority__c = 'P1',
            Target_Object__c = 'ApexClass',
            Execution_Order__c = 205,
            Is_Active__c = true,
            Assertion_Type__c = 'Coverage Threshold',
            Steps__c = 'Run the following test classes:\n  - QuarterlyReviewControllerTest\n  - BaselineComparisonControllerTest\n  - QuarterlySignOffServiceTest\n\n' +
                'Verify review workflow and baseline comparison logic.',
            Expected_Result__c = 'All tests pass. Review workflow verified. Coverage >= 85%.',
            Related_Metadata__c = 'QuarterlyReviewController,BaselineComparisonController,QuarterlySignOffService',
            Tags__c = 'apex-test,review,compliance'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Feature and Config Service Tests',
            Description__c = 'Executes tests for feature toggles and configuration services.',
            Test_Layer__c = 'Apex Test',
            Category__c = 'Functional',
            Perspective__c = 'Developer',
            Priority__c = 'P1',
            Target_Object__c = 'ApexClass',
            Execution_Order__c = 206,
            Is_Active__c = true,
            Assertion_Type__c = 'Coverage Threshold',
            Steps__c = 'Run the following test classes:\n  - AuditFeatureServiceTest\n  - FindingAssignmentServiceTest\n  - CMTicketValidationServiceTest\n\n' +
                'Verify feature toggle logic and configuration services.',
            Expected_Result__c = 'All tests pass. Feature toggles verified. Coverage >= 85%.',
            Related_Metadata__c = 'AuditFeatureService,FindingAssignmentService,CMTicketValidationService',
            Tags__c = 'apex-test,features,config'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Deactivation Handler Tests',
            Description__c = 'Executes tests for the User deactivation trigger handler.',
            Test_Layer__c = 'Apex Test',
            Category__c = 'Functional',
            Perspective__c = 'Developer',
            Priority__c = 'P0',
            Target_Object__c = 'ApexClass',
            Execution_Order__c = 207,
            Is_Active__c = true,
            Assertion_Type__c = 'Coverage Threshold',
            Steps__c = 'Run UserDeactivationHandlerTest.\n\n' +
                'Verify:\n  - Trigger fires on User.IsActive = false\n  - On-demand audit run created\n  - Snapshot created for deactivated user\n  - Coverage >= 85%',
            Expected_Result__c = 'All tests pass. Trigger handler verified. Coverage >= 85%.',
            Related_Metadata__c = 'UserDeactivationHandler',
            Tags__c = 'apex-test,trigger,handler'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Test Data Factory Compilation',
            Description__c = 'Verifies test data factory compiles and all methods are callable.',
            Test_Layer__c = 'Apex Test',
            Category__c = 'Deployment',
            Perspective__c = 'Developer',
            Priority__c = 'P0',
            Target_Object__c = 'ApexClass',
            Execution_Order__c = 208,
            Is_Active__c = true,
            Assertion_Type__c = 'No Error',
            Steps__c = 'Verify UserAuditTestDataFactory compiles.\n\n' +
                'Execute in Anonymous Apex:\n  UserAuditTestDataFactory.createAuditRun();\n  UserAuditTestDataFactory.createSnapshots(5);\n  UserAuditTestDataFactory.createFindings(3);\n\n' +
                'Confirm all factory methods execute without errors.',
            Expected_Result__c = 'Factory class compiles. All methods callable and return valid test data.',
            Related_Metadata__c = 'UserAuditTestDataFactory',
            Tags__c = 'apex-test,factory,test-data'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Full Test Suite Execution',
            Description__c = 'Executes ALL 35 test classes together to verify overall coverage.',
            Test_Layer__c = 'Apex Test',
            Category__c = 'Regression',
            Perspective__c = 'Product Manager',
            Priority__c = 'P0',
            Target_Object__c = 'ApexClass',
            Execution_Order__c = 209,
            Is_Active__c = true,
            Assertion_Type__c = 'Coverage Threshold',
            Steps__c = 'Run ALL 35 test classes in a single test run:\n  sf apex run test --tests UserAuditSnapshotBatchTest,AuditControllerTest,...\n\n' +
                'OR use Test Suite in Setup:\n  - Create Test Suite "User Access Audit Full Suite"\n  - Add all 35 test classes\n  - Run suite\n\n' +
                'Verify:\n  - 0 test failures\n  - Overall code coverage >= 85%\n  - No governor limit exceptions',
            Expected_Result__c = 'All 35 test classes pass with 0 failures. Overall coverage >= 85%. No governor limit issues.',
            Related_Metadata__c = 'All audit test classes',
            Tags__c = 'apex-test,regression,full-suite'
        ));

        return cases;
    }

    /**
     * @description LAYER 3 - Data Scenario Tests (20 tests)
     */
    private static List<Regression_Test_Case__c> createLayer3DataScenarioTests(Id suiteId) {
        List<Regression_Test_Case__c> cases = new List<Regression_Test_Case__c>();

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Full Audit Run Lifecycle',
            Description__c = 'End-to-end test of complete audit run from creation to finalization.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Functional',
            Perspective__c = 'Admin',
            Priority__c = 'P0',
            Target_Object__c = 'Audit_Run__c',
            Execution_Order__c = 300,
            Is_Active__c = true,
            Assertion_Type__c = 'Record Exists',
            Steps__c = '// Create audit run\nAudit_Run__c run = new Audit_Run__c(Name = \'Test Run\', Status__c = \'Queued\');\ninsert run;\n\n' +
                '// Execute batch to snapshot 50 users\nDatabase.executeBatch(new UserAuditSnapshotBatch(run.Id), 200);\n\n' +
                '// Verify completion\nrun = [SELECT Status__c, Snapshot_Count__c FROM Audit_Run__c WHERE Id = :run.Id];\nSystem.assertEquals(\'Completed\', run.Status__c);\nSystem.assertEquals(50, run.Snapshot_Count__c);',
            Expected_Result__c = 'Audit run status = Completed. 50 snapshots created. Findings generated for any detected changes.',
            Related_Metadata__c = 'Audit_Run__c,User_Audit_Snapshot__c,Audit_Finding__c,UserAuditSnapshotBatch',
            Tags__c = 'data-scenario,lifecycle,e2e'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Terminated User Detection',
            Description__c = 'Tests termination cross-check creates Critical findings for matched terminated users.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Functional',
            Perspective__c = 'Admin',
            Priority__c = 'P0',
            Target_Object__c = 'Audit_Finding__c',
            Execution_Order__c = 301,
            Is_Active__c = true,
            Assertion_Type__c = 'Record Count',
            Steps__c = '// Import termination CSV with 3 records\nList<Termination_Record__c> terms = AuditController.importTerminationCsv(csvContent);\ninsert terms;\n\n' +
                '// Run cross-check\nTerminationCrossCheckService.execute(runId);\n\n' +
                '// Assert findings created\nList<Audit_Finding__c> findings = [SELECT Severity__c FROM Audit_Finding__c WHERE Category__c = \'Terminated User Active\'];\nSystem.assertEquals(3, findings.size());\nSystem.assertEquals(\'Critical\', findings[0].Severity__c);',
            Expected_Result__c = 'Critical findings created for all 3 matched terminated users still active in Salesforce.',
            Related_Metadata__c = 'Termination_Record__c,Audit_Finding__c,TerminationCrossCheckService',
            Tags__c = 'data-scenario,termination,critical'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Profile Change Detection',
            Description__c = 'Tests profile change detection between two audit runs.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Functional',
            Perspective__c = 'Developer',
            Priority__c = 'P0',
            Target_Object__c = 'Audit_Finding__c',
            Execution_Order__c = 302,
            Is_Active__c = true,
            Assertion_Type__c = 'Record Exists',
            Steps__c = '// Run audit 1\nAudit_Run__c run1 = UserAuditTestDataFactory.createAuditRun();\ninsert run1;\nDatabase.executeBatch(new UserAuditSnapshotBatch(run1.Id));\n\n' +
                '// Change user profiles\nUser u = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];\nu.ProfileId = [SELECT Id FROM Profile WHERE Name = \'System Administrator\' LIMIT 1].Id;\nupdate u;\n\n' +
                '// Run audit 2\nAudit_Run__c run2 = UserAuditTestDataFactory.createAuditRun();\ninsert run2;\nDatabase.executeBatch(new UserAuditSnapshotBatch(run2.Id));\n\n' +
                '// Assert profile change finding\nList<Audit_Finding__c> findings = [SELECT Category__c FROM Audit_Finding__c WHERE Category__c = \'Profile Changed\'];\nSystem.assert(!findings.isEmpty());',
            Expected_Result__c = 'Profile Changed findings created for users with profile changes between runs.',
            Related_Metadata__c = 'Audit_Finding__c,ProfileChangeDetector,User_Audit_Snapshot__c',
            Tags__c = 'data-scenario,profile,change-detection'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Role Change Detection',
            Description__c = 'Tests role change detection between audit runs.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Functional',
            Perspective__c = 'Developer',
            Priority__c = 'P1',
            Target_Object__c = 'Audit_Finding__c',
            Execution_Order__c = 303,
            Is_Active__c = true,
            Assertion_Type__c = 'Record Exists',
            Steps__c = '// Similar pattern to profile change test\n// Change user roles between two audit runs\n// Assert Role Changed findings created',
            Expected_Result__c = 'Role Changed findings created for users with role changes.',
            Related_Metadata__c = 'Audit_Finding__c,ProfileChangeDetector',
            Tags__c = 'data-scenario,role,change-detection'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Permission Set Change Detection',
            Description__c = 'Tests permission set assignment change detection.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Functional',
            Perspective__c = 'Developer',
            Priority__c = 'P1',
            Target_Object__c = 'Audit_Finding__c',
            Execution_Order__c = 304,
            Is_Active__c = true,
            Assertion_Type__c = 'Record Exists',
            Steps__c = '// Run audit 1\n// Add/remove permission set assignments\nPermissionSetAssignment psa = new PermissionSetAssignment(PermissionSetId = psId, AssigneeId = userId);\ninsert psa;\n\n' +
                '// Run audit 2\n// Assert Permission Set Changed findings',
            Expected_Result__c = 'Permission Set Changed findings created for assignment changes.',
            Related_Metadata__c = 'Audit_Finding__c,User_Audit_Snapshot__c',
            Tags__c = 'data-scenario,permset,change-detection'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'New User Detection',
            Description__c = 'Tests new user detection creates Info-level findings.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Functional',
            Perspective__c = 'Admin',
            Priority__c = 'P1',
            Target_Object__c = 'Audit_Finding__c',
            Execution_Order__c = 305,
            Is_Active__c = true,
            Assertion_Type__c = 'Field Value',
            Steps__c = '// Run audit 1 with 50 users\n// Create 5 new users\n// Run audit 2\n// Assert 5 New User findings with Severity = Info',
            Expected_Result__c = '5 New User findings created with Severity = Info.',
            Related_Metadata__c = 'Audit_Finding__c,ProfileChangeDetector',
            Tags__c = 'data-scenario,new-user,info'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Segregation of Duties Violation',
            Description__c = 'Tests SoD detection creates Critical findings for toxic permission combinations.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Functional',
            Perspective__c = 'Admin',
            Priority__c = 'P0',
            Target_Object__c = 'Audit_Finding__c',
            Execution_Order__c = 306,
            Is_Active__c = true,
            Assertion_Type__c = 'Field Value',
            Steps__c = '// Create user with 2 permission sets: Author Apex + Deploy to Production\n// Run audit with SoD feature enabled\nSegregationOfDutiesService.execute(runId);\n\n' +
                '// Assert Critical SoD finding\nList<Audit_Finding__c> findings = [SELECT Severity__c FROM Audit_Finding__c WHERE Category__c = \'SoD Violation\'];\nSystem.assertEquals(\'Critical\', findings[0].Severity__c);',
            Expected_Result__c = 'Critical SoD Violation findings created for users with toxic permission combinations.',
            Related_Metadata__c = 'Audit_Finding__c,SegregationOfDutiesService,Segregation_Rule__mdt',
            Tags__c = 'data-scenario,sod,critical,security'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Login Anomaly Detection',
            Description__c = 'Tests login anomaly detection creates Login_Anomaly__c records.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Functional',
            Perspective__c = 'Admin',
            Priority__c = 'P1',
            Target_Object__c = 'Login_Anomaly__c',
            Execution_Order__c = 307,
            Is_Active__c = true,
            Assertion_Type__c = 'Record Count',
            Steps__c = '// Create login history records with anomalies\n// - Multiple failed logins\n// - Unusual login times (3 AM)\n// Run LoginHistoryService\n\n' +
                '// Assert Login_Anomaly__c records created\nList<Login_Anomaly__c> anomalies = [SELECT Id FROM Login_Anomaly__c];\nSystem.assert(!anomalies.isEmpty());',
            Expected_Result__c = 'Login_Anomaly__c records created for failed logins and unusual times.',
            Related_Metadata__c = 'Login_Anomaly__c,LoginHistoryService',
            Tags__c = 'data-scenario,login,anomaly'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'SLA Status Transitions',
            Description__c = 'Tests SLA status transitions: On Track → At Risk → Breached.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Functional',
            Perspective__c = 'Product Manager',
            Priority__c = 'P0',
            Target_Object__c = 'Audit_Finding__c',
            Execution_Order__c = 308,
            Is_Active__c = true,
            Assertion_Type__c = 'Field Value',
            Steps__c = '// Create finding with due date 10 days out → assert On Track\n// Update due date to tomorrow → assert At Risk\n// Update due date to yesterday → assert Breached\n\n' +
                'SlaStatusCalculatorService.updateSlaStatus(findingIds);',
            Expected_Result__c = 'SLA_Status__c transitions correctly: On Track → At Risk → Breached based on due date proximity.',
            Related_Metadata__c = 'Audit_Finding__c,SlaStatusCalculatorService',
            Tags__c = 'data-scenario,sla,status'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Remediation Due Date by Severity',
            Description__c = 'Tests due date calculation: Critical = 7 days, Warning = 30 days, Info = 90 days.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Functional',
            Perspective__c = 'Admin',
            Priority__c = 'P0',
            Target_Object__c = 'Audit_Finding__c',
            Execution_Order__c = 309,
            Is_Active__c = true,
            Assertion_Type__c = 'Field Value',
            Steps__c = '// Create 3 findings: Critical, Warning, Info\n// Assert Remediation_Due_Date__c:\n//   Critical: today + 7 days\n//   Warning: today + 30 days\n//   Info: today + 90 days',
            Expected_Result__c = 'Due dates calculated correctly: Critical (7d), Warning (30d), Info (90d).',
            Related_Metadata__c = 'Audit_Finding__c,RemediationDueDateService,Set_Remediation_Due_Date',
            Tags__c = 'data-scenario,due-date,severity'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Quarterly Sign-Off Enforcement',
            Description__c = 'Tests quarterly sign-off requirement blocks new runs when not signed off.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Functional',
            Perspective__c = 'Client',
            Priority__c = 'P0',
            Target_Object__c = 'Audit_Run__c',
            Execution_Order__c = 310,
            Is_Active__c = true,
            Assertion_Type__c = 'Custom Script',
            Steps__c = '// Enable quarterly sign-off feature\n// Attempt to create audit run → assert blocked\n// Sign off previous quarter\n// Attempt to create audit run → assert allowed',
            Expected_Result__c = 'New runs blocked without sign-off. Allowed after quarterly sign-off.',
            Related_Metadata__c = 'Audit_Run__c,QuarterlySignOffService',
            Tags__c = 'data-scenario,sign-off,compliance'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Baseline Comparison - Drift Detection',
            Description__c = 'Tests baseline comparison detects users added/removed/modified.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Functional',
            Perspective__c = 'Admin',
            Priority__c = 'P1',
            Target_Object__c = 'Audit_Run__c',
            Execution_Order__c = 311,
            Is_Active__c = true,
            Assertion_Type__c = 'Record Count',
            Steps__c = '// Set baseline audit run\n// Add 2 users, remove 1 user, modify 3 users\n// Run baseline comparison\n\n' +
                '// Assert comparison results:\n//   2 users added\n//   1 user removed\n//   3 users modified',
            Expected_Result__c = 'Baseline comparison correctly detects: 2 added, 1 removed, 3 modified.',
            Related_Metadata__c = 'Audit_Run__c,BaselineComparisonController,BaselineSnapshotService',
            Tags__c = 'data-scenario,baseline,drift'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Feature Toggle - Disable Checks',
            Description__c = 'Tests disabling features skips corresponding checks.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Functional',
            Perspective__c = 'Developer',
            Priority__c = 'P0',
            Target_Object__c = 'Audit_Feature_Setting__mdt',
            Execution_Order__c = 312,
            Is_Active__c = true,
            Assertion_Type__c = 'Record Count',
            Steps__c = '// Disable Profile_Change_Detection__c\n// Change user profiles\n// Run audit\n// Assert 0 Profile Change findings\n\n' +
                '// Re-enable feature\n// Run audit\n// Assert Profile Change findings created',
            Expected_Result__c = 'Disabled features skip checks. Re-enabling restores checks.',
            Related_Metadata__c = 'Audit_Feature_Setting__mdt,AuditFeatureService',
            Tags__c = 'data-scenario,feature-toggle,config'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'PDF Report Generation',
            Description__c = 'Tests PDF report generation creates ContentVersion.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Integration',
            Perspective__c = 'Admin',
            Priority__c = 'P1',
            Target_Object__c = 'ContentVersion',
            Execution_Order__c = 313,
            Is_Active__c = true,
            Assertion_Type__c = 'Record Exists',
            Steps__c = '// Generate PDF report\nAuditSummaryPdfGenerator.generatePdf(runId);\n\n' +
                '// Assert ContentVersion created\nList<ContentVersion> cvs = [SELECT Id, Title FROM ContentVersion WHERE Title LIKE \'%Audit Summary%\'];\nSystem.assert(!cvs.isEmpty());',
            Expected_Result__c = 'ContentVersion created with PDF audit summary.',
            Related_Metadata__c = 'ContentVersion,AuditSummaryPdfGenerator',
            Tags__c = 'data-scenario,pdf,content'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Email Report Distribution',
            Description__c = 'Tests email report distribution sends successfully.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Integration',
            Perspective__c = 'Admin',
            Priority__c = 'P1',
            Target_Object__c = 'Messaging.SendEmailResult',
            Execution_Order__c = 313,
            Is_Active__c = true,
            Assertion_Type__c = 'No Error',
            Steps__c = '// Send audit summary email\nMessaging.SendEmailResult[] results = AuditSummaryEmailService.sendSummary(runId);\n\n' +
                '// Assert success\nSystem.assertEquals(true, results[0].isSuccess());',
            Expected_Result__c = 'Email sent successfully to configured recipients.',
            Related_Metadata__c = 'AuditSummaryEmailService,Audit_Summary_Recipient__mdt',
            Tags__c = 'data-scenario,email,integration'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'CSV Export',
            Description__c = 'Tests CSV export generates correct format and content.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Functional',
            Perspective__c = 'Product Manager',
            Priority__c = 'P1',
            Target_Object__c = 'Audit_Finding__c',
            Execution_Order__c = 315,
            Is_Active__c = true,
            Assertion_Type__c = 'Custom Script',
            Steps__c = '// Export findings to CSV\nString csv = ExportService.exportFindings(runId);\n\n' +
                '// Assert CSV contains headers and data\nSystem.assert(csv.contains(\'Category,Severity,User,Status\'));\nSystem.assert(csv.split(\'\\n\').size() > 1);',
            Expected_Result__c = 'CSV export contains headers and all finding records.',
            Related_Metadata__c = 'Audit_Finding__c,ExportService',
            Tags__c = 'data-scenario,csv,export'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'CSV Import with Duplicates',
            Description__c = 'Tests CSV import handles duplicates gracefully.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Edge Case',
            Perspective__c = 'Admin',
            Priority__c = 'P1',
            Target_Object__c = 'Termination_Record__c',
            Execution_Order__c = 316,
            Is_Active__c = true,
            Assertion_Type__c = 'Record Count',
            Steps__c = '// Import CSV with 5 records\nAuditController.importTerminationCsv(csvContent);\n\n' +
                '// Import same CSV again\nAuditController.importTerminationCsv(csvContent);\n\n' +
                '// Assert only 5 Termination_Record__c exist (no duplicates)\nInteger count = [SELECT COUNT() FROM Termination_Record__c];\nSystem.assertEquals(5, count);',
            Expected_Result__c = 'Duplicate records not created. Count remains 5.',
            Related_Metadata__c = 'Termination_Record__c,AuditController',
            Tags__c = 'data-scenario,csv,dedup'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Batch → Queueable Full Chain',
            Description__c = 'Tests complete async chain: Batch → Termination Queueable → Profile Queueable → Finalize.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Functional',
            Perspective__c = 'Developer',
            Priority__c = 'P0',
            Target_Object__c = 'Audit_Run__c',
            Execution_Order__c = 317,
            Is_Active__c = true,
            Assertion_Type__c = 'Field Value',
            Steps__c = '// Execute full chain\nDatabase.executeBatch(new UserAuditSnapshotBatch(runId));\n// Wait for finish() to chain queueables\n\n' +
                '// Assert final status = Completed (not Processing)\nAudit_Run__c run = [SELECT Status__c FROM Audit_Run__c WHERE Id = :runId];\nSystem.assertEquals(\'Completed\', run.Status__c);',
            Expected_Result__c = 'Full chain completes. Status = Completed (not Processing).',
            Related_Metadata__c = 'UserAuditSnapshotBatch,TerminationCrossCheckQueueable,ProfileChangeDetectorQueueable',
            Tags__c = 'data-scenario,async,chain'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Real-Time User Deactivation',
            Description__c = 'Tests UserDeactivationHandler creates on-demand audit run on User.IsActive = false.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Functional',
            Perspective__c = 'Admin',
            Priority__c = 'P0',
            Target_Object__c = 'Audit_Run__c',
            Execution_Order__c = 318,
            Is_Active__c = true,
            Assertion_Type__c = 'Record Exists',
            Steps__c = '// Deactivate user\nUser u = [SELECT Id, IsActive FROM User WHERE Id = :testUserId];\nu.IsActive = false;\nupdate u;\n\n' +
                '// Assert on-demand audit run created\nList<Audit_Run__c> runs = [SELECT Type__c FROM Audit_Run__c WHERE Type__c = \'On-Demand\' ORDER BY CreatedDate DESC LIMIT 1];\nSystem.assert(!runs.isEmpty());\n\n' +
                '// Assert snapshot created for deactivated user\nList<User_Audit_Snapshot__c> snapshots = [SELECT User_Id__c FROM User_Audit_Snapshot__c WHERE User_Id__c = :testUserId];\nSystem.assert(!snapshots.isEmpty());',
            Expected_Result__c = 'On-demand audit run created. Snapshot created for deactivated user. Finding created.',
            Related_Metadata__c = 'UserDeactivationHandler,UserDeactivationQueueable,Audit_Run__c',
            Tags__c = 'data-scenario,trigger,deactivation'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Finding Resolution Workflow',
            Description__c = 'Tests finding resolution workflow updates status and timestamps.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Functional',
            Perspective__c = 'Product Manager',
            Priority__c = 'P1',
            Target_Object__c = 'Audit_Finding__c',
            Execution_Order__c = 319,
            Is_Active__c = true,
            Assertion_Type__c = 'Field Value',
            Steps__c = '// Create finding (status = Open)\nAudit_Finding__c finding = UserAuditTestDataFactory.createFinding();\ninsert finding;\n\n' +
                '// Resolve finding\nfinding.Status__c = \'Resolved\';\nfinding.Resolution_Notes__c = \'User access revoked\';\nupdate finding;\n\n' +
                '// Assert resolution fields populated\nfinding = [SELECT Status__c, Resolved_By__c, Resolved_Date__c FROM Audit_Finding__c WHERE Id = :finding.Id];\nSystem.assertEquals(\'Resolved\', finding.Status__c);\nSystem.assertNotEquals(null, finding.Resolved_By__c);\nSystem.assertNotEquals(null, finding.Resolved_Date__c);',
            Expected_Result__c = 'Status = Resolved. Resolved_By and Resolved_Date populated.',
            Related_Metadata__c = 'Audit_Finding__c,AuditController',
            Tags__c = 'data-scenario,resolution,workflow'
        ));

        return cases;
    }

    /**
     * @description LAYER 4 - Static Analysis Tests (5 tests)
     */
    private static List<Regression_Test_Case__c> createLayer4StaticAnalysisTests(Id suiteId) {
        List<Regression_Test_Case__c> cases = new List<Regression_Test_Case__c>();

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'No SOQL in Loops',
            Description__c = 'Static analysis to detect SOQL queries inside loops.',
            Test_Layer__c = 'Static Analysis',
            Category__c = 'Regression',
            Perspective__c = 'Developer',
            Priority__c = 'P0',
            Target_Object__c = 'ApexClass',
            Execution_Order__c = 400,
            Is_Active__c = true,
            Assertion_Type__c = 'Custom Script',
            Steps__c = 'Scan all 35 Apex classes for pattern:\n  for/while/do {\n    [SELECT ... FROM ...]\n  }\n\n' +
                'Tools:\n  - sf code-analyzer run --target force-app --rule-selector "pmd:AvoidSoqlInLoops"\n  - Manual code review\n\n' +
                'Expected: 0 violations',
            Expected_Result__c = '0 SOQL queries found inside loops across all 35 Apex classes.',
            Related_Metadata__c = 'All audit Apex classes',
            Tags__c = 'static-analysis,soql,governor-limits'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'No DML in Loops',
            Description__c = 'Static analysis to detect DML statements inside loops.',
            Test_Layer__c = 'Static Analysis',
            Category__c = 'Regression',
            Perspective__c = 'Developer',
            Priority__c = 'P0',
            Target_Object__c = 'ApexClass',
            Execution_Order__c = 401,
            Is_Active__c = true,
            Assertion_Type__c = 'Custom Script',
            Steps__c = 'Scan all 35 Apex classes for pattern:\n  for/while/do {\n    insert/update/delete/upsert ...\n  }\n\n' +
                'Tools:\n  - sf code-analyzer run --target force-app --rule-selector "pmd:AvoidDmlStatementsInLoops"\n  - Manual code review\n\n' +
                'Expected: 0 violations',
            Expected_Result__c = '0 DML statements found inside loops across all 35 Apex classes.',
            Related_Metadata__c = 'All audit Apex classes',
            Tags__c = 'static-analysis,dml,governor-limits'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'No Hardcoded Salesforce IDs',
            Description__c = 'Static analysis to detect hardcoded 15/18-char Salesforce IDs.',
            Test_Layer__c = 'Static Analysis',
            Category__c = 'Regression',
            Perspective__c = 'Developer',
            Priority__c = 'P1',
            Target_Object__c = 'ApexClass',
            Execution_Order__c = 402,
            Is_Active__c = true,
            Assertion_Type__c = 'Custom Script',
            Steps__c = 'Scan all classes for regex pattern:\n  \'(005|00D|00e|003|001|006)[a-zA-Z0-9]{12,15}\'\n\n' +
                'Whitelist: Test classes with @IsTest may have sample IDs\n\n' +
                'Expected: 0 violations in production classes',
            Expected_Result__c = '0 hardcoded Salesforce IDs in production Apex classes.',
            Related_Metadata__c = 'All audit Apex classes',
            Tags__c = 'static-analysis,hardcoded-ids,portability'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'CRUD/FLS Enforcement',
            Description__c = 'Verifies controller classes enforce CRUD/FLS with WITH USER_MODE or Security.stripInaccessible().',
            Test_Layer__c = 'Static Analysis',
            Category__c = 'Security Permission',
            Perspective__c = 'Developer',
            Priority__c = 'P0',
            Target_Object__c = 'ApexClass',
            Execution_Order__c = 403,
            Is_Active__c = true,
            Assertion_Type__c = 'Custom Script',
            Steps__c = 'Scan controller classes:\n  - AuditController\n  - AuditControlCenterController\n  - BaselineComparisonController\n  - QuarterlyReviewController\n  - PermissionSetViewerController\n\n' +
                'Verify all SOQL queries use:\n  WITH USER_MODE\n\n' +
                'OR all DML uses:\n  Security.stripInaccessible(AccessType.READABLE/CREATABLE/UPDATABLE, records)\n\n' +
                'Tools:\n  - sf code-analyzer run --rule-selector "pmd:ApexCRUDViolation"',
            Expected_Result__c = 'All controller classes enforce CRUD/FLS. 0 violations.',
            Related_Metadata__c = 'AuditController,AuditControlCenterController,BaselineComparisonController,QuarterlyReviewController,PermissionSetViewerController',
            Tags__c = 'static-analysis,security,crud,fls'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'AuraHandledException Pattern',
            Description__c = 'Verifies all @AuraEnabled methods use try/catch with AuraHandledException.',
            Test_Layer__c = 'Static Analysis',
            Category__c = 'Security Permission',
            Perspective__c = 'Developer',
            Priority__c = 'P1',
            Target_Object__c = 'ApexClass',
            Execution_Order__c = 404,
            Is_Active__c = true,
            Assertion_Type__c = 'Custom Script',
            Steps__c = 'Scan all controller classes for @AuraEnabled methods.\n\n' +
                'Verify pattern:\n  @AuraEnabled\n  public static ReturnType methodName(...) {\n    try {\n      // logic\n    } catch (Exception e) {\n      throw new AuraHandledException(e.getMessage());\n    }\n  }\n\n' +
                'Expected: All @AuraEnabled methods follow this pattern.',
            Expected_Result__c = 'All @AuraEnabled methods have try/catch with AuraHandledException. User-friendly error messages.',
            Related_Metadata__c = 'AuditController,AuditControlCenterController,BaselineComparisonController,QuarterlyReviewController,PermissionSetViewerController',
            Tags__c = 'static-analysis,error-handling,lwc'
        ));

        return cases;
    }

    /**
     * @description Edge Case Tests (12 tests)
     */
    private static List<Regression_Test_Case__c> createEdgeCaseTests(Id suiteId) {
        List<Regression_Test_Case__c> cases = new List<Regression_Test_Case__c>();

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Empty Org - Zero Users',
            Description__c = 'Tests audit run with 0 active users completes gracefully.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Edge Case',
            Perspective__c = 'Developer',
            Priority__c = 'P1',
            Target_Object__c = 'Audit_Run__c',
            Execution_Order__c = 500,
            Is_Active__c = true,
            Assertion_Type__c = 'Field Value',
            Steps__c = '// In test environment with 0 active users\nDatabase.executeBatch(new UserAuditSnapshotBatch(runId));\n\n' +
                '// Assert run completes\nAudit_Run__c run = [SELECT Status__c, Snapshot_Count__c FROM Audit_Run__c WHERE Id = :runId];\nSystem.assertEquals(\'Completed\', run.Status__c);\nSystem.assertEquals(0, run.Snapshot_Count__c);',
            Expected_Result__c = 'Audit run completes with Status = Completed, Snapshot_Count = 0, 0 findings.',
            Related_Metadata__c = 'UserAuditSnapshotBatch,Audit_Run__c',
            Tags__c = 'edge-case,empty,zero-users'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'User with No Profile',
            Description__c = 'Tests handling of user with null profile.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Edge Case',
            Perspective__c = 'Developer',
            Priority__c = 'P1',
            Target_Object__c = 'User_Audit_Snapshot__c',
            Execution_Order__c = 501,
            Is_Active__c = true,
            Assertion_Type__c = 'No Error',
            Steps__c = '// Note: In practice, users always have profiles (system enforced)\n// Test defensive coding handles null gracefully\n\n' +
                'Mock scenario or test null check:\n  if (user.ProfileId != null) {\n    snapshot.Profile_Name__c = user.Profile.Name;\n  }',
            Expected_Result__c = 'No NullPointerException. Snapshot created with Profile_Name__c = null or \'N/A\'.',
            Related_Metadata__c = 'UserAuditSnapshotBatch,User_Audit_Snapshot__c',
            Tags__c = 'edge-case,null,profile'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'User with No Role',
            Description__c = 'Tests handling of user with null role (valid scenario).',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Edge Case',
            Perspective__c = 'Developer',
            Priority__c = 'P1',
            Target_Object__c = 'User_Audit_Snapshot__c',
            Execution_Order__c = 502,
            Is_Active__c = true,
            Assertion_Type__c = 'No Error',
            Steps__c = '// Create user with UserRoleId = null\n// Run audit\n// Assert snapshot created with Role_Name__c = null or \'No Role\'',
            Expected_Result__c = 'Snapshot created successfully with Role_Name__c = null or \'No Role\'. No errors.',
            Related_Metadata__c = 'UserAuditSnapshotBatch,User_Audit_Snapshot__c',
            Tags__c = 'edge-case,null,role'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Duplicate Termination Records',
            Description__c = 'Tests import of CSV with duplicate emails handles gracefully.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Edge Case',
            Perspective__c = 'Admin',
            Priority__c = 'P1',
            Target_Object__c = 'Termination_Record__c',
            Execution_Order__c = 503,
            Is_Active__c = true,
            Assertion_Type__c = 'Custom Script',
            Steps__c = '// Import CSV with duplicate email:\n//   user@example.com, 2026-01-01\n//   user@example.com, 2026-01-02\n\n' +
                'AuditController.importTerminationCsv(csvContent);\n\n' +
                '// Assert either:\n//   1. Only 1 record created (latest date)\n//   2. Error message returned listing duplicates',
            Expected_Result__c = 'Duplicates handled gracefully. Either merged or error message with duplicate list.',
            Related_Metadata__c = 'Termination_Record__c,AuditController',
            Tags__c = 'edge-case,duplicate,csv'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Concurrent Batch Execution',
            Description__c = 'Tests attempting to run 2 audit batches simultaneously.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Edge Case',
            Perspective__c = 'Developer',
            Priority__c = 'P0',
            Target_Object__c = 'Audit_Run__c',
            Execution_Order__c = 504,
            Is_Active__c = true,
            Assertion_Type__c = 'Custom Script',
            Steps__c = '// Attempt to execute 2 batches for different runs\nDatabase.executeBatch(new UserAuditSnapshotBatch(runId1));\nDatabase.executeBatch(new UserAuditSnapshotBatch(runId2));\n\n' +
                '// Assert either:\n//   1. Both execute in sequence (Salesforce queues automatically)\n//   2. Second batch throws error with friendly message',
            Expected_Result__c = 'Concurrent execution handled gracefully. No data corruption.',
            Related_Metadata__c = 'UserAuditSnapshotBatch,Audit_Run__c',
            Tags__c = 'edge-case,concurrent,batch'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'All Features Disabled',
            Description__c = 'Tests audit run with all 17 features disabled completes gracefully.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Edge Case',
            Perspective__c = 'Admin',
            Priority__c = 'P1',
            Target_Object__c = 'Audit_Feature_Setting__mdt',
            Execution_Order__c = 505,
            Is_Active__c = true,
            Assertion_Type__c = 'Record Count',
            Steps__c = '// Disable all 17 feature toggles\n// Run audit\n\n' +
                '// Assert:\n//   - Snapshots created (always happens)\n//   - 0 findings created (all checks skipped)\n//   - Run status = Completed',
            Expected_Result__c = 'Audit completes. Snapshots created. 0 findings (all checks disabled).',
            Related_Metadata__c = 'Audit_Feature_Setting__mdt,AuditFeatureService',
            Tags__c = 'edge-case,features,disabled'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'CSV with Malformed Data',
            Description__c = 'Tests CSV import with missing columns and special characters.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Edge Case',
            Perspective__c = 'Admin',
            Priority__c = 'P1',
            Target_Object__c = 'Termination_Record__c',
            Execution_Order__c = 506,
            Is_Active__c = true,
            Assertion_Type__c = 'Custom Script',
            Steps__c = '// Import CSV with issues:\n//   - Missing required column\n//   - Special characters: O\'Brien, José\n//   - Invalid date format\n\n' +
                'String result = AuditController.importTerminationCsv(malformedCsv);\n\n' +
                '// Assert error message returned with details',
            Expected_Result__c = 'Error message returned listing issues. No crash. No partial data.',
            Related_Metadata__c = 'AuditController,Termination_Record__c',
            Tags__c = 'edge-case,csv,malformed'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Resolve Already-Resolved Finding',
            Description__c = 'Tests resolving a finding that is already Resolved.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Edge Case',
            Perspective__c = 'Admin',
            Priority__c = 'P2',
            Target_Object__c = 'Audit_Finding__c',
            Execution_Order__c = 507,
            Is_Active__c = true,
            Assertion_Type__c = 'No Error',
            Steps__c = '// Create and resolve finding\nAudit_Finding__c f = ...\nf.Status__c = \'Resolved\';\nupdate f;\n\n' +
                '// Attempt to resolve again\nAuditController.resolveFindings(new List<Id>{f.Id}, \'Duplicate resolution\');\n\n' +
                '// Assert no error, no change to Resolved_Date__c',
            Expected_Result__c = 'No error. Finding remains Resolved. Resolved_Date unchanged.',
            Related_Metadata__c = 'Audit_Finding__c,AuditController',
            Tags__c = 'edge-case,resolution,idempotent'
        ));

        return cases;
    }

    /**
     * @description Bulk Performance Tests (4 tests)
     */
    private static List<Regression_Test_Case__c> createBulkTests(Id suiteId) {
        List<Regression_Test_Case__c> cases = new List<Regression_Test_Case__c>();

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Bulk Snapshot 2000+ Users',
            Description__c = 'Tests audit run with 2000+ users completes without governor limits.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Bulk Performance',
            Perspective__c = 'Developer',
            Priority__c = 'P0',
            Target_Object__c = 'User_Audit_Snapshot__c',
            Execution_Order__c = 508,
            Is_Active__c = true,
            Assertion_Type__c = 'No Error',
            Steps__c = '// In test environment, create 2000+ active users (or use production org)\n' +
                'Database.executeBatch(new UserAuditSnapshotBatch(runId), 200);\n\n' +
                '// Assert:\n//   - Batch completes without governor limit exceptions\n//   - All users snapshotted\n//   - SOQL queries < 100 per transaction\n//   - DML statements < 150 per transaction',
            Expected_Result__c = 'Batch completes successfully. 2000+ snapshots created. No governor limits hit.',
            Related_Metadata__c = 'UserAuditSnapshotBatch,User_Audit_Snapshot__c',
            Tags__c = 'bulk,performance,governor-limits'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Bulk Import 1000+ Terminations',
            Description__c = 'Tests CSV import with 1000+ rows processes without limits.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Bulk Performance',
            Perspective__c = 'Admin',
            Priority__c = 'P1',
            Target_Object__c = 'Termination_Record__c',
            Execution_Order__c = 509,
            Is_Active__c = true,
            Assertion_Type__c = 'Record Count',
            Steps__c = '// Create CSV with 1000+ rows\n// Import via AuditController.importTerminationCsv(csvContent)\n\n' +
                '// Assert all 1000+ records created\nInteger count = [SELECT COUNT() FROM Termination_Record__c];\nSystem.assert(count >= 1000);',
            Expected_Result__c = 'All 1000+ termination records imported successfully. No governor limit errors.',
            Related_Metadata__c = 'Termination_Record__c,AuditController',
            Tags__c = 'bulk,performance,csv'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Bulk Resolve 200 Findings',
            Description__c = 'Tests resolving 200 findings at once.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Bulk Performance',
            Perspective__c = 'Admin',
            Priority__c = 'P1',
            Target_Object__c = 'Audit_Finding__c',
            Execution_Order__c = 510,
            Is_Active__c = true,
            Assertion_Type__c = 'Record Count',
            Steps__c = '// Create 200 findings\nList<Audit_Finding__c> findings = UserAuditTestDataFactory.createFindings(200);\ninsert findings;\n\n' +
                '// Resolve all 200\nList<Id> ids = new List<Id>();\nfor (Audit_Finding__c f : findings) { ids.add(f.Id); }\nAuditController.resolveFindings(ids, \'Bulk resolution\');\n\n' +
                '// Assert all 200 resolved\nInteger count = [SELECT COUNT() FROM Audit_Finding__c WHERE Status__c = \'Resolved\'];\nSystem.assertEquals(200, count);',
            Expected_Result__c = 'All 200 findings resolved successfully. No governor limit errors.',
            Related_Metadata__c = 'Audit_Finding__c,AuditController',
            Tags__c = 'bulk,performance,resolution'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Baseline with No Baseline Set',
            Description__c = 'Tests baseline comparison when no baseline audit exists.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Edge Case',
            Perspective__c = 'Admin',
            Priority__c = 'P2',
            Target_Object__c = 'Audit_Run__c',
            Execution_Order__c = 511,
            Is_Active__c = true,
            Assertion_Type__c = 'Custom Script',
            Steps__c = '// Ensure no baseline audit exists\n// Attempt baseline comparison\nBaselineComparisonController.compareToBaseline(currentRunId);\n\n' +
                '// Assert user-friendly error message:\n//   "No baseline audit found. Please set a baseline first."',
            Expected_Result__c = 'User-friendly error message returned. No crash.',
            Related_Metadata__c = 'BaselineComparisonController,Audit_Run__c',
            Tags__c = 'edge-case,baseline,error-handling'
        ));

        return cases;
    }

    /**
     * @description Security and Permission Tests (10 tests)
     */
    private static List<Regression_Test_Case__c> createSecurityTests(Id suiteId) {
        List<Regression_Test_Case__c> cases = new List<Regression_Test_Case__c>();

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Admin Full CRUD - All Objects',
            Description__c = 'Tests Audit_Administrator permission set grants full CRUD on all 7 objects.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Security Permission',
            Perspective__c = 'Admin',
            Priority__c = 'P0',
            Target_Object__c = 'PermissionSet',
            Execution_Order__c = 600,
            Is_Active__c = true,
            Assertion_Type__c = 'No Error',
            Steps__c = 'System.runAs(adminUser) {\n  // Create records in all 7 objects\n  // Update records\n  // Delete records\n  // Assert all operations succeed\n}',
            Expected_Result__c = 'Admin user can create, read, update, delete all 7 audit objects.',
            Related_Metadata__c = 'Audit_Administrator,All audit objects',
            Tags__c = 'security,permission,admin,crud'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Admin Has Bypass_All_Flows',
            Description__c = 'Verifies Audit_Administrator has Bypass_All_Flows custom permission.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Security Permission',
            Perspective__c = 'Admin',
            Priority__c = 'P0',
            Target_Object__c = 'PermissionSet',
            Execution_Order__c = 601,
            Is_Active__c = true,
            Assertion_Type__c = 'Custom Script',
            Steps__c = 'System.runAs(adminUser) {\n  Boolean hasBypass = FeatureManagement.checkPermission(\'Bypass_All_Flows\');\n  System.assertEquals(true, hasBypass);\n}',
            Expected_Result__c = 'Audit_Administrator has Bypass_All_Flows custom permission.',
            Related_Metadata__c = 'Audit_Administrator,Bypass_All_Flows',
            Tags__c = 'security,permission,bypass'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Full Access CRUD - All Objects',
            Description__c = 'Tests Audit_Full_Access permission set grants CRUD on all objects.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Security Permission',
            Perspective__c = 'Admin',
            Priority__c = 'P0',
            Target_Object__c = 'PermissionSet',
            Execution_Order__c = 602,
            Is_Active__c = true,
            Assertion_Type__c = 'No Error',
            Steps__c = 'System.runAs(fullAccessUser) {\n  // CRUD all 7 objects\n  // Assert all operations succeed\n}',
            Expected_Result__c = 'Full Access user can create, read, update, delete all audit objects.',
            Related_Metadata__c = 'Audit_Full_Access,All audit objects',
            Tags__c = 'security,permission,full-access,crud'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Full Access No Bypass',
            Description__c = 'Verifies Audit_Full_Access does NOT have Bypass_All_Flows.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Security Permission',
            Perspective__c = 'Admin',
            Priority__c = 'P0',
            Target_Object__c = 'PermissionSet',
            Execution_Order__c = 603,
            Is_Active__c = true,
            Assertion_Type__c = 'Custom Script',
            Steps__c = 'System.runAs(fullAccessUser) {\n  Boolean hasBypass = FeatureManagement.checkPermission(\'Bypass_All_Flows\');\n  System.assertEquals(false, hasBypass);\n}',
            Expected_Result__c = 'Audit_Full_Access does NOT have Bypass_All_Flows custom permission.',
            Related_Metadata__c = 'Audit_Full_Access,Bypass_All_Flows',
            Tags__c = 'security,permission,no-bypass'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Viewer Read Only',
            Description__c = 'Tests Audit_Viewer permission set grants read-only access.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Security Permission',
            Perspective__c = 'Client',
            Priority__c = 'P0',
            Target_Object__c = 'PermissionSet',
            Execution_Order__c = 604,
            Is_Active__c = true,
            Assertion_Type__c = 'Custom Script',
            Steps__c = 'System.runAs(viewerUser) {\n  // Read all objects → succeeds\n  List<Audit_Run__c> runs = [SELECT Id FROM Audit_Run__c];\n  System.assert(!runs.isEmpty());\n\n' +
                '  // Attempt create → fails\n  try {\n    insert new Audit_Run__c(Name = \'Test\');\n    System.assert(false, \'Should have failed\');\n  } catch (DmlException e) {\n    System.assert(e.getMessage().contains(\'insufficient access\'));\n  }\n}',
            Expected_Result__c = 'Viewer can read all objects. Create/Update/Delete operations fail with insufficient access.',
            Related_Metadata__c = 'Audit_Viewer,All audit objects',
            Tags__c = 'security,permission,viewer,read-only'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'No Permission Set - Blocked',
            Description__c = 'Tests user without any audit permission set cannot access audit objects.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Security Permission',
            Perspective__c = 'Client',
            Priority__c = 'P0',
            Target_Object__c = 'PermissionSet',
            Execution_Order__c = 605,
            Is_Active__c = true,
            Assertion_Type__c = 'Custom Script',
            Steps__c = 'System.runAs(noPermUser) {\n  // Attempt to query audit objects\n  try {\n    List<Audit_Run__c> runs = [SELECT Id FROM Audit_Run__c];\n    System.assert(false, \'Should have failed\');\n  } catch (QueryException e) {\n    System.assert(e.getMessage().contains(\'insufficient privileges\'));\n  }\n}',
            Expected_Result__c = 'User without audit permission set cannot query or access any audit objects.',
            Related_Metadata__c = 'All audit objects',
            Tags__c = 'security,permission,blocked,no-access'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Viewer Cannot Run Audit',
            Description__c = 'Tests Viewer user cannot execute runAuditNow controller method.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Security Permission',
            Perspective__c = 'Client',
            Priority__c = 'P1',
            Target_Object__c = 'ApexClass',
            Execution_Order__c = 606,
            Is_Active__c = true,
            Assertion_Type__c = 'Custom Script',
            Steps__c = 'System.runAs(viewerUser) {\n  try {\n    AuditControlCenterController.runAuditNow();\n    System.assert(false, \'Should have failed\');\n  } catch (AuraHandledException e) {\n    System.assert(e.getMessage().contains(\'Insufficient access\'));\n  }\n}',
            Expected_Result__c = 'Viewer user receives AuraHandledException: "Insufficient access to run audit."',
            Related_Metadata__c = 'AuditControlCenterController,Audit_Viewer',
            Tags__c = 'security,permission,viewer,method-access'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Viewer Cannot Resolve Findings',
            Description__c = 'Tests Viewer user cannot resolve findings.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Security Permission',
            Perspective__c = 'Client',
            Priority__c = 'P1',
            Target_Object__c = 'ApexClass',
            Execution_Order__c = 607,
            Is_Active__c = true,
            Assertion_Type__c = 'Custom Script',
            Steps__c = 'System.runAs(viewerUser) {\n  try {\n    AuditController.resolveFindings(findingIds, \'Test resolution\');\n    System.assert(false, \'Should have failed\');\n  } catch (AuraHandledException e) {\n    System.assert(e.getMessage().contains(\'Insufficient access\'));\n  }\n}',
            Expected_Result__c = 'Viewer user receives AuraHandledException: "Insufficient access to resolve findings."',
            Related_Metadata__c = 'AuditController,Audit_Viewer',
            Tags__c = 'security,permission,viewer,method-access'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'FLS Enforcement via User Mode',
            Description__c = 'Tests WITH USER_MODE enforces field-level security.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Security Permission',
            Perspective__c = 'Developer',
            Priority__c = 'P0',
            Target_Object__c = 'ApexClass',
            Execution_Order__c = 608,
            Is_Active__c = true,
            Assertion_Type__c = 'Custom Script',
            Steps__c = '// Remove FLS on a field for viewer profile\n// Query with WITH USER_MODE\nSystem.runAs(viewerUser) {\n  List<Audit_Finding__c> findings = [SELECT Id, Resolution_Notes__c FROM Audit_Finding__c WITH USER_MODE];\n  // Assert Resolution_Notes__c is null or inaccessible\n}',
            Expected_Result__c = 'WITH USER_MODE enforces FLS. Fields without access are not returned or throw exception.',
            Related_Metadata__c = 'All controller classes',
            Tags__c = 'security,fls,user-mode'
        ));

        cases.add(new Regression_Test_Case__c(
            Test_Suite__c = suiteId,
            Title__c = 'Graceful Error on Insufficient Access',
            Description__c = 'Tests all @AuraEnabled methods return user-friendly errors, not raw DML exceptions.',
            Test_Layer__c = 'Data Scenario',
            Category__c = 'Security Permission',
            Perspective__c = 'Client',
            Priority__c = 'P1',
            Target_Object__c = 'ApexClass',
            Execution_Order__c = 609,
            Is_Active__c = true,
            Assertion_Type__c = 'Custom Script',
            Steps__c = 'System.runAs(viewerUser) {\n  // Call all @AuraEnabled methods that require write access\n  // Assert each throws AuraHandledException with message like:\n  //   "You do not have permission to perform this action."\n  // NOT raw DML exceptions\n}',
            Expected_Result__c = 'All insufficient access errors return user-friendly AuraHandledException messages.',
            Related_Metadata__c = 'All controller classes',
            Tags__c = 'security,error-handling,ux'
        ));

        return cases;
    }
}
