/**
 * ForceGuardReportController - VF page controller for PDF report generation.
 * Renders regression test run data as a professional PDF report and provides
 * AuraEnabled methods for LWC integration.
 */
public with sharing class ForceGuardReportController {

    public Regression_Test_Run__c run { get; set; }
    public List<Regression_Test_Result__c> results { get; set; }
    public Map<String, LayerStats> layerBreakdown { get; set; }
    public Decimal passRate { get; set; }
    public Integer regressionCount { get; set; }
    public List<Map<String, Object>> trendData { get; set; }
    public DateTime generatedAt { get; set; }

    /**
     * Inner class for per-layer statistics displayed in the PDF.
     */
    public class LayerStats {
        public Integer passed { get; set; }
        public Integer failed { get; set; }
        public Integer skipped { get; set; }
        public Integer total { get; set; }
        public Decimal passRate { get; set; }

        public LayerStats() {
            this.passed = 0;
            this.failed = 0;
            this.skipped = 0;
            this.total = 0;
            this.passRate = 0;
        }
    }

    /**
     * Constructor - loads all data for the VF page from the runId URL parameter.
     */
    public ForceGuardReportController() {
        String runId = ApexPages.currentPage().getParameters().get('runId');
        if (String.isBlank(runId)) {
            this.results = new List<Regression_Test_Result__c>();
            this.layerBreakdown = new Map<String, LayerStats>();
            this.trendData = new List<Map<String, Object>>();
            this.passRate = 0;
            this.regressionCount = 0;
            this.generatedAt = DateTime.now();
            return;
        }

        Id sanitizedRunId = Id.valueOf(runId);

        // Query run record with suite info
        this.run = [
            SELECT Id, Name, Test_Suite__c, Test_Suite__r.Product_Name__c,
                   Run_Date__c, Status__c, Total_Tests__c, Passed__c, Failed__c,
                   Skipped__c, Pass_Rate__c, Code_Coverage__c, Regression_Count__c,
                   Duration_Seconds__c
            FROM Regression_Test_Run__c
            WHERE Id = :sanitizedRunId
            WITH SYSTEM_MODE
        ];

        // Query all results ordered by layer, title
        this.results = [
            SELECT Test_Case__r.Title__c, Layer__c, Status__c,
                   Error_Message__c, Duration_Ms__c, Is_Regression__c
            FROM Regression_Test_Result__c
            WHERE Test_Run__c = :sanitizedRunId
            WITH SYSTEM_MODE
            ORDER BY Layer__c, Test_Case__r.Title__c
        ];

        // Build layer breakdown
        this.layerBreakdown = new Map<String, LayerStats>();
        for (Regression_Test_Result__c result : this.results) {
            String layer = result.Layer__c;
            if (!this.layerBreakdown.containsKey(layer)) {
                this.layerBreakdown.put(layer, new LayerStats());
            }
            LayerStats stats = this.layerBreakdown.get(layer);
            stats.total++;
            if (result.Status__c == 'Passed') {
                stats.passed++;
            } else if (result.Status__c == 'Failed' || result.Status__c == 'Error') {
                stats.failed++;
            } else if (result.Status__c == 'Skipped') {
                stats.skipped++;
            }
            stats.passRate = stats.total > 0
                ? ((Decimal) stats.passed / stats.total * 100).setScale(1)
                : 0;
        }

        // Detect regression count
        this.regressionCount = 0;
        for (Regression_Test_Result__c result : this.results) {
            if (result.Is_Regression__c == true) {
                this.regressionCount++;
            }
        }

        // Pass rate from formula field (Percent type returns value like 62.5 for 62.5%)
        this.passRate = this.run.Pass_Rate__c != null
            ? this.run.Pass_Rate__c.setScale(1)
            : 0;

        // Get trend data (last 5 runs for same suite)
        this.trendData = RegressionTestReporter.getTrendData(this.run.Test_Suite__c, 5);

        this.generatedAt = DateTime.now();
    }

    /**
     * Generate a PDF file from the VF page and attach it to the test run record.
     * @param testRunId The Regression_Test_Run__c Id
     * @return The ContentVersion Id of the created PDF
     */
    public static Id generatePdf(Id testRunId) {
        PageReference pdfPage = new PageReference('/apex/ForceGuardTestReport');
        pdfPage.getParameters().put('runId', String.valueOf(testRunId));

        Blob pdfBlob;
        if (Test.isRunningTest()) {
            pdfBlob = Blob.valueOf('ForceGuard Test Report PDF');
        } else {
            pdfBlob = pdfPage.getContentAsPDF();
        }

        String reportDate = DateTime.now().format('yyyy-MM-dd');
        ContentVersion cv = new ContentVersion(
            Title = 'ForceGuard Test Report - ' + reportDate,
            PathOnClient = 'ForceGuardReport.pdf',
            VersionData = pdfBlob
        );
        insert cv;

        // Query the ContentDocumentId from the inserted ContentVersion
        Id contentDocId = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
            WITH SYSTEM_MODE
        ].ContentDocumentId;

        // Link the PDF to the test run record
        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = contentDocId,
            LinkedEntityId = testRunId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert cdl;

        return cv.Id;
    }

    /**
     * AuraEnabled wrapper for LWC to generate PDF and get the ContentVersion Id.
     * @param runId The Regression_Test_Run__c Id
     * @return The ContentVersion Id for download
     */
    @AuraEnabled
    public static Id generateAndGetReportId(Id runId) {
        try {
            return generatePdf(runId);
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }
}
