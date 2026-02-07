/**
 * RegressionTestReporterTest - Tests for the RegressionTestReporter class.
 * Covers: run summaries, regression detection, CSV export, coverage snapshots,
 * and trend data retrieval.
 */
@IsTest
private class RegressionTestReporterTest {

    @TestSetup
    static void setup() {
        User testUser = ForceGuardTestDataFactory.createTestUser();

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = ForceGuardTestDataFactory.createSuite('Reporter Test Product');
            insert suite;

            // Create test cases across all layers
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
                Passed__c = 6,
                Failed__c = 2,
                Skipped__c = 0,
                Duration_Seconds__c = 5.5,
                Layer_1_Status__c = 'Passed',
                Layer_2_Status__c = 'Passed',
                Layer_3_Status__c = 'Failed',
                Layer_4_Status__c = 'Passed'
            );
            insert run;

            // Create mixed results - some passed, some failed
            List<Regression_Test_Result__c> results = new List<Regression_Test_Result__c>();
            for (Integer i = 0; i < cases.size(); i++) {
                String status = (i < 6) ? 'Passed' : 'Failed';
                Regression_Test_Result__c result = new Regression_Test_Result__c(
                    Test_Run__c = run.Id,
                    Test_Case__c = cases[i].Id,
                    Status__c = status,
                    Layer__c = cases[i].Test_Layer__c,
                    Duration_Ms__c = 100,
                    Is_Regression__c = false
                );
                if (status == 'Failed') {
                    result.Error_Message__c = 'Test failure for case ' + (i + 1);
                }
                results.add(result);
            }
            insert results;
        }
    }

    @IsTest
    static void testGenerateRunSummary() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];

            Test.startTest();
            RegressionTestReporter.RunSummary summary =
                RegressionTestReporter.generateRunSummary(run.Id);
            Test.stopTest();

            System.assertNotEquals(null, summary, 'Summary should not be null');
            System.assertEquals(run.Id, summary.runId, 'Summary runId should match');
            System.assertEquals('Reporter Test Product', summary.suiteName,
                'Suite name should match product name');
            System.assertEquals(8, summary.totalTests, 'Total tests should be 8');
            System.assertEquals(6, summary.passed, 'Passed count should be 6');
            System.assertEquals(2, summary.failed, 'Failed count should be 2');
            System.assert(!summary.layerBreakdown.isEmpty(),
                'Layer breakdown should have entries');
            System.assert(!summary.failures.isEmpty(),
                'Failures list should have entries for failed results');
        }
    }

    @IsTest
    static void testDetectRegressionsFirstRun() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            // The setup created only 1 run, so this is the first run
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];

            Test.startTest();
            List<Regression_Test_Result__c> regressions =
                RegressionTestReporter.detectRegressions(run.Id);
            Test.stopTest();

            System.assertEquals(0, regressions.size(),
                'First run should have no regressions since there is no previous run');
        }
    }

    @IsTest
    static void testDetectRegressionsWithRegression() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = [SELECT Id FROM Regression_Test_Suite__c LIMIT 1];
            List<Regression_Test_Case__c> cases = [
                SELECT Id, Test_Layer__c FROM Regression_Test_Case__c
                WHERE Test_Suite__c = :suite.Id LIMIT 4
            ];

            // Create a previous run where all cases passed
            Regression_Test_Run__c previousRun = new Regression_Test_Run__c(
                Test_Suite__c = suite.Id,
                Run_Date__c = DateTime.now().addDays(-1),
                Status__c = 'Completed',
                Triggered_By__c = 'Manual',
                Run_By__c = UserInfo.getUserId(),
                Total_Tests__c = cases.size(),
                Passed__c = cases.size(),
                Failed__c = 0,
                Skipped__c = 0
            );
            insert previousRun;

            List<Regression_Test_Result__c> prevResults = new List<Regression_Test_Result__c>();
            for (Regression_Test_Case__c tc : cases) {
                prevResults.add(new Regression_Test_Result__c(
                    Test_Run__c = previousRun.Id,
                    Test_Case__c = tc.Id,
                    Status__c = 'Passed',
                    Layer__c = tc.Test_Layer__c,
                    Duration_Ms__c = 50
                ));
            }
            insert prevResults;

            // Create a current run where first case fails (regression)
            Regression_Test_Run__c currentRun = new Regression_Test_Run__c(
                Test_Suite__c = suite.Id,
                Run_Date__c = DateTime.now(),
                Status__c = 'Failed',
                Triggered_By__c = 'Manual',
                Run_By__c = UserInfo.getUserId(),
                Total_Tests__c = cases.size(),
                Passed__c = cases.size() - 1,
                Failed__c = 1,
                Skipped__c = 0
            );
            insert currentRun;

            List<Regression_Test_Result__c> currentResults = new List<Regression_Test_Result__c>();
            for (Integer i = 0; i < cases.size(); i++) {
                String status = (i == 0) ? 'Failed' : 'Passed';
                Regression_Test_Result__c result = new Regression_Test_Result__c(
                    Test_Run__c = currentRun.Id,
                    Test_Case__c = cases[i].Id,
                    Status__c = status,
                    Layer__c = cases[i].Test_Layer__c,
                    Duration_Ms__c = 75
                );
                if (status == 'Failed') {
                    result.Error_Message__c = 'Regression failure';
                }
                currentResults.add(result);
            }
            insert currentResults;

            Test.startTest();
            List<Regression_Test_Result__c> regressions =
                RegressionTestReporter.detectRegressions(currentRun.Id);
            Test.stopTest();

            System.assertEquals(1, regressions.size(),
                'Should detect 1 regression (previously passed, now failed)');
            System.assertEquals(true, regressions[0].Is_Regression__c,
                'Regression flag should be true');
        }
    }

    @IsTest
    static void testGenerateCsvExport() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];

            Test.startTest();
            String csv = RegressionTestReporter.generateCsvExport(run.Id);
            Test.stopTest();

            System.assert(String.isNotBlank(csv), 'CSV output should not be blank');
            System.assert(csv.startsWith('Test Case,Layer,Category,Status,Error Message,Duration (ms),Is Regression'),
                'CSV should start with header row, got: ' + csv.substring(0, Math.min(csv.length(), 100)));
            // Should have data rows (header + at least 1 result)
            List<String> lines = csv.split('\n');
            System.assert(lines.size() > 1,
                'CSV should have header plus at least 1 data row, got ' + lines.size() + ' lines');
        }
    }

    @IsTest
    static void testCreateCoverageSnapshot() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Run__c run = [SELECT Id FROM Regression_Test_Run__c LIMIT 1];

            Test.startTest();
            Test_Coverage_Snapshot__c snapshot =
                RegressionTestReporter.createCoverageSnapshot(run.Id);
            Test.stopTest();

            System.assertNotEquals(null, snapshot, 'Snapshot should not be null');
            System.assertNotEquals(null, snapshot.Id, 'Snapshot should have an Id after insert');
            System.assertEquals(Date.today(), snapshot.Snapshot_Date__c,
                'Snapshot date should be today');

            // Verify it was actually inserted
            List<Test_Coverage_Snapshot__c> savedSnapshots = [
                SELECT Id, Snapshot_Date__c, Total_Metadata_Items__c
                FROM Test_Coverage_Snapshot__c
                WHERE Id = :snapshot.Id
            ];
            System.assertEquals(1, savedSnapshots.size(),
                'Snapshot record should be persisted in the database');
        }
    }

    @IsTest
    static void testGetTrendData() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = [SELECT Id FROM Regression_Test_Suite__c LIMIT 1];

            // Create additional completed runs to have multiple data points
            List<Regression_Test_Run__c> additionalRuns = new List<Regression_Test_Run__c>();
            for (Integer i = 1; i <= 3; i++) {
                additionalRuns.add(new Regression_Test_Run__c(
                    Test_Suite__c = suite.Id,
                    Run_Date__c = DateTime.now().addDays(-i),
                    Status__c = 'Completed',
                    Triggered_By__c = 'Scheduled',
                    Run_By__c = UserInfo.getUserId(),
                    Total_Tests__c = 10,
                    Passed__c = 10 - i,
                    Failed__c = i,
                    Skipped__c = 0
                ));
            }
            insert additionalRuns;

            Test.startTest();
            List<Map<String, Object>> trendData =
                RegressionTestReporter.getTrendData(suite.Id, 10);
            Test.stopTest();

            System.assert(!trendData.isEmpty(), 'Trend data should not be empty');
            System.assert(trendData.size() >= 3,
                'Should have at least 3 trend data points, got: ' + trendData.size());

            // Verify chronological order (oldest first)
            if (trendData.size() >= 2) {
                DateTime first = (DateTime) trendData[0].get('runDate');
                DateTime last = (DateTime) trendData[trendData.size() - 1].get('runDate');
                System.assert(first <= last,
                    'Trend data should be in chronological order (oldest first)');
            }
        }
    }

    @IsTest
    static void testGetTrendDataNoRuns() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            // Create a new suite with no runs
            Regression_Test_Suite__c emptySuite = ForceGuardTestDataFactory.createSuite('No Runs Product');
            insert emptySuite;

            Test.startTest();
            List<Map<String, Object>> trendData =
                RegressionTestReporter.getTrendData(emptySuite.Id, 10);
            Test.stopTest();

            System.assertEquals(0, trendData.size(),
                'Suite with no runs should return empty trend data');
        }
    }

    @IsTest
    static void testGetTrendDataNullSuiteId() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Test.startTest();
            List<Map<String, Object>> trendData =
                RegressionTestReporter.getTrendData(null, 5);
            Test.stopTest();

            // With null suiteId, it should query across all suites
            System.assertNotEquals(null, trendData,
                'Trend data should not be null even with null suite');
        }
    }

    @IsTest
    static void testGetTrendDataDefaultCount() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = [SELECT Id FROM Regression_Test_Suite__c LIMIT 1];

            Test.startTest();
            // Null/zero runCount should default to 10
            List<Map<String, Object>> trendData =
                RegressionTestReporter.getTrendData(suite.Id, null);
            Test.stopTest();

            System.assertNotEquals(null, trendData,
                'Trend data should not be null with null runCount');
        }
    }

    @IsTest
    static void testGenerateCsvExportNoResults() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'fgtest' LIMIT 1];

        System.runAs(testUser) {
            Regression_Test_Suite__c suite = [SELECT Id FROM Regression_Test_Suite__c LIMIT 1];

            // Create a run with no results
            Regression_Test_Run__c emptyRun = new Regression_Test_Run__c(
                Test_Suite__c = suite.Id,
                Run_Date__c = DateTime.now(),
                Status__c = 'Completed',
                Triggered_By__c = 'Manual',
                Run_By__c = UserInfo.getUserId(),
                Total_Tests__c = 0,
                Passed__c = 0,
                Failed__c = 0,
                Skipped__c = 0
            );
            insert emptyRun;

            Test.startTest();
            String csv = RegressionTestReporter.generateCsvExport(emptyRun.Id);
            Test.stopTest();

            System.assert(csv.startsWith('Test Case,'),
                'CSV should still have header even with no results');
            List<String> lines = csv.split('\n');
            System.assertEquals(1, lines.size(),
                'CSV with no results should only have header row');
        }
    }
}
