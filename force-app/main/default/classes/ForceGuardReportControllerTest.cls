/**
 * ForceGuardReportControllerTest - Tests for ForceGuardReportController.
 * Covers: constructor initialization, layer breakdown, PDF generation,
 * AuraEnabled method, and empty run handling.
 */
@IsTest
private class ForceGuardReportControllerTest {

    @TestSetup
    static void setup() {
        // Wrap user creation in runAs to avoid MIXED_DML with custom objects
        User testUser;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            testUser = ForceGuardTestDataFactory.createTestUser();
        }

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = ForceGuardTestDataFactory.createSuite('Report Test Product');
            insert suite;

            List<Regression_Test_Case__c> cases = ForceGuardTestDataFactory.createTestCases(suite.Id, 8);
            insert cases;

            // Create a completed run with mixed results
            Regression_Test_Run__c run = new Regression_Test_Run__c(
                Test_Suite__c = suite.Id,
                Run_Date__c = DateTime.now(),
                Status__c = 'Completed',
                Triggered_By__c = 'Manual',
                Run_By__c = UserInfo.getUserId(),
                Total_Tests__c = 8,
                Passed__c = 5,
                Failed__c = 2,
                Skipped__c = 1,
                Duration_Seconds__c = 12.3
            );
            insert run;

            // Create mixed results: 5 passed, 2 failed, 1 skipped
            List<Regression_Test_Result__c> results = new List<Regression_Test_Result__c>();
            for (Integer i = 0; i < cases.size(); i++) {
                String status;
                if (i < 5) {
                    status = 'Passed';
                } else if (i < 7) {
                    status = 'Failed';
                } else {
                    status = 'Skipped';
                }

                Regression_Test_Result__c result = new Regression_Test_Result__c(
                    Test_Run__c = run.Id,
                    Test_Case__c = cases[i].Id,
                    Status__c = status,
                    Layer__c = cases[i].Test_Layer__c,
                    Duration_Ms__c = 100 + i,
                    Is_Regression__c = (i == 5)
                );
                if (status == 'Failed') {
                    result.Error_Message__c = 'Failure in case ' + (i + 1);
                }
                results.add(result);
            }
            insert results;
        }
    }

    @IsTest
    static void testControllerInitialization() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];

            // Set page parameters
            PageReference pageRef = new PageReference('/apex/ForceGuardTestReport');
            pageRef.getParameters().put('runId', run.Id);
            Test.setCurrentPage(pageRef);

            Test.startTest();
            ForceGuardReportController controller = new ForceGuardReportController();
            Test.stopTest();

            System.assertNotEquals(null, controller.run, 'Run should be populated');
            System.assertEquals(run.Id, controller.run.Id, 'Run Id should match');
            System.assertEquals('Report Test Product', controller.run.Test_Suite__r.Product_Name__c,
                'Suite product name should match');
            System.assertNotEquals(null, controller.results, 'Results should be populated');
            System.assertEquals(8, controller.results.size(), 'Should have 8 results');
            System.assertNotEquals(null, controller.generatedAt, 'Generated date should be set');
        }
    }

    @IsTest
    static void testLayerBreakdown() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];

            PageReference pageRef = new PageReference('/apex/ForceGuardTestReport');
            pageRef.getParameters().put('runId', run.Id);
            Test.setCurrentPage(pageRef);

            Test.startTest();
            ForceGuardReportController controller = new ForceGuardReportController();
            Test.stopTest();

            System.assert(!controller.layerBreakdown.isEmpty(),
                'Layer breakdown should have entries');

            // Verify each layer has valid stats
            Integer totalAcrossLayers = 0;
            for (String layerName : controller.layerBreakdown.keySet()) {
                ForceGuardReportController.LayerStats stats = controller.layerBreakdown.get(layerName);
                System.assert(stats.total > 0,
                    'Layer ' + layerName + ' should have at least 1 test');
                System.assertEquals(stats.passed + stats.failed + stats.skipped, stats.total,
                    'Layer ' + layerName + ' counts should sum to total');
                totalAcrossLayers += stats.total;
            }
            System.assertEquals(8, totalAcrossLayers,
                'All layers combined should equal 8 total tests');

            // Verify regression count
            System.assertEquals(1, controller.regressionCount,
                'Should detect 1 regression');
        }
    }

    @IsTest
    static void testGeneratePdf() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];

            Test.startTest();
            Id contentVersionId = ForceGuardReportController.generatePdf(run.Id);
            Test.stopTest();

            System.assertNotEquals(null, contentVersionId,
                'Should return a ContentVersion Id');

            // Verify ContentVersion was created
            ContentVersion cv = [
                SELECT Id, Title, PathOnClient, ContentDocumentId
                FROM ContentVersion
                WHERE Id = :contentVersionId
            ];
            System.assert(cv.Title.startsWith('ForceGuard Test Report'),
                'Title should start with ForceGuard Test Report');
            System.assertEquals('ForceGuardReport.pdf', cv.PathOnClient,
                'Path should be ForceGuardReport.pdf');

            // Verify ContentDocumentLink was created to the run
            List<ContentDocumentLink> links = [
                SELECT Id, LinkedEntityId, ShareType
                FROM ContentDocumentLink
                WHERE ContentDocumentId = :cv.ContentDocumentId
                  AND LinkedEntityId = :run.Id
            ];
            System.assertEquals(1, links.size(),
                'Should have 1 link to the test run record');
            System.assertEquals('V', links[0].ShareType,
                'Share type should be Viewer');
        }
    }

    @IsTest
    static void testGenerateAndGetReportId() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];

            Test.startTest();
            Id reportId = ForceGuardReportController.generateAndGetReportId(run.Id);
            Test.stopTest();

            System.assertNotEquals(null, reportId,
                'AuraEnabled method should return a ContentVersion Id');

            // Verify it is a valid ContentVersion
            List<ContentVersion> cvs = [
                SELECT Id FROM ContentVersion WHERE Id = :reportId
            ];
            System.assertEquals(1, cvs.size(),
                'Returned Id should reference a valid ContentVersion');
        }
    }

    @IsTest
    static void testEmptyRun() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            // Create a run with no results
            Regression_Test_Suite__c suite = [SELECT Id FROM Regression_Test_Suite__c LIMIT 1];
            Regression_Test_Run__c emptyRun = new Regression_Test_Run__c(
                Test_Suite__c = suite.Id,
                Run_Date__c = DateTime.now(),
                Status__c = 'Completed',
                Triggered_By__c = 'Manual',
                Run_By__c = UserInfo.getUserId(),
                Total_Tests__c = 0,
                Passed__c = 0,
                Failed__c = 0,
                Skipped__c = 0,
                Duration_Seconds__c = 0
            );
            insert emptyRun;

            PageReference pageRef = new PageReference('/apex/ForceGuardTestReport');
            pageRef.getParameters().put('runId', emptyRun.Id);
            Test.setCurrentPage(pageRef);

            Test.startTest();
            ForceGuardReportController controller = new ForceGuardReportController();
            Test.stopTest();

            System.assertNotEquals(null, controller.run, 'Run should still be populated');
            System.assertEquals(0, controller.results.size(),
                'Results should be empty for run with no results');
            System.assert(controller.layerBreakdown.isEmpty(),
                'Layer breakdown should be empty for run with no results');
            System.assertEquals(0, controller.regressionCount,
                'Regression count should be 0');
            System.assertEquals(0, controller.passRate,
                'Pass rate should be 0 for empty run');
        }
    }

    @IsTest
    static void testControllerNoRunId() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            // No runId parameter set
            PageReference pageRef = new PageReference('/apex/ForceGuardTestReport');
            Test.setCurrentPage(pageRef);

            Test.startTest();
            ForceGuardReportController controller = new ForceGuardReportController();
            Test.stopTest();

            System.assertEquals(null, controller.run, 'Run should be null when no runId');
            System.assertEquals(0, controller.results.size(),
                'Results should be empty when no runId');
            System.assert(controller.layerBreakdown.isEmpty(),
                'Layer breakdown should be empty when no runId');
            System.assertNotEquals(null, controller.generatedAt,
                'Generated date should still be set');
        }
    }
}
