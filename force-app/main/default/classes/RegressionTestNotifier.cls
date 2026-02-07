/**
 * RegressionTestNotifier - Sends email notifications after regression test runs.
 * Queued from RegressionTestRunner.finish() to send results via email.
 * Reads Regression_Config__mdt for recipient list and trigger conditions.
 */
public with sharing class RegressionTestNotifier implements Queueable {

    private final Id runId;

    @TestVisible
    private static NotificationConfig configOverride;

    public RegressionTestNotifier(Id runId) {
        this.runId = runId;
    }

    public void execute(QueueableContext context) {
        NotificationConfig config = getConfig();
        if (config == null || String.isBlank(config.emails)) {
            return;
        }

        Regression_Test_Run__c run = [
            SELECT Id, Status__c, Total_Tests__c, Passed__c, Failed__c,
                   Skipped__c, Pass_Rate__c, Duration_Seconds__c,
                   Regression_Count__c, Run_Date__c, Completed_Date__c,
                   Test_Suite__r.Name, Test_Suite__r.Product_Name__c
            FROM Regression_Test_Run__c
            WHERE Id = :runId
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        if (!shouldSend(config.triggerCondition, run)) {
            return;
        }

        List<Regression_Test_Result__c> allResults = [
            SELECT Status__c, Layer__c, Test_Case__r.Title__c, Error_Message__c
            FROM Regression_Test_Result__c
            WHERE Test_Run__c = :runId
            WITH SYSTEM_MODE
            ORDER BY Layer__c, Test_Case__r.Title__c
        ];

        // Build layer breakdown from results
        Map<String, Integer[]> layerMap = new Map<String, Integer[]>();
        List<Regression_Test_Result__c> failures = new List<Regression_Test_Result__c>();
        for (Regression_Test_Result__c res : allResults) {
            String layer = res.Layer__c != null ? res.Layer__c : 'Unknown';
            if (!layerMap.containsKey(layer)) {
                layerMap.put(layer, new Integer[]{ 0, 0, 0, 0 });
            }
            Integer[] counts = layerMap.get(layer);
            counts[0]++; // total
            if (res.Status__c == 'Passed') {
                counts[1]++;
            } else if (res.Status__c == 'Failed') {
                counts[2]++;
                if (failures.size() < 50) {
                    failures.add(res);
                }
            } else if (res.Status__c == 'Skipped') {
                counts[3]++;
            }
        }

        String suiteName = run.Test_Suite__r.Name != null
            ? run.Test_Suite__r.Name : 'Unknown Suite';
        Boolean passed = run.Status__c == 'Completed';
        Decimal passRate = run.Pass_Rate__c != null ? run.Pass_Rate__c : 0;
        String passRateStr = String.valueOf((passRate * 100).setScale(1));

        String subject = '[ForceGuard] ' + suiteName + ' - '
            + (passed ? 'PASSED' : 'FAILED') + ' (' + passRateStr + '%)';

        String htmlBody = buildHtmlBody(run, suiteName, passed, passRateStr,
            layerMap, failures);

        List<String> addresses = parseEmails(config.emails);
        if (addresses.isEmpty()) {
            return;
        }

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(addresses);
        mail.setSubject(subject);
        mail.setHtmlBody(htmlBody);
        mail.setSaveAsActivity(false);

        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        } catch (Exception e) {
            // Email delivery failures should not break the run
        }
    }

    @TestVisible
    private static NotificationConfig getConfig() {
        if (configOverride != null) {
            return configOverride;
        }

        List<Regression_Config__mdt> configs = [
            SELECT Notification_Email__c, Notification_Recipients__c, Notification_Trigger__c
            FROM Regression_Config__mdt
            WHERE DeveloperName = 'Default'
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        if (configs.isEmpty()) {
            return null;
        }

        // Prefer Notification_Recipients__c (supports semicolon-delimited list)
        // Fall back to Notification_Email__c (single email)
        String emailValue = String.isNotBlank(configs[0].Notification_Recipients__c)
            ? configs[0].Notification_Recipients__c
            : configs[0].Notification_Email__c;

        if (String.isBlank(emailValue)) {
            return null;
        }

        NotificationConfig cfg = new NotificationConfig();
        cfg.emails = emailValue;
        cfg.triggerCondition = configs[0].Notification_Trigger__c != null
            ? configs[0].Notification_Trigger__c : 'Always';
        return cfg;
    }

    private static Boolean shouldSend(String triggerCondition, Regression_Test_Run__c run) {
        if (triggerCondition == 'Always') {
            return true;
        }
        if (triggerCondition == 'Failures Only') {
            return run.Status__c == 'Failed';
        }
        if (triggerCondition == 'Regressions Only') {
            return run.Regression_Count__c != null && run.Regression_Count__c > 0;
        }
        return true;
    }

    @TestVisible
    private static List<String> parseEmails(String emailString) {
        List<String> result = new List<String>();
        if (String.isBlank(emailString)) {
            return result;
        }
        for (String email : emailString.split(';')) {
            String trimmed = email.trim();
            if (String.isNotBlank(trimmed)) {
                result.add(trimmed);
            }
        }
        return result;
    }

    private static String buildHtmlBody(
        Regression_Test_Run__c run,
        String suiteName,
        Boolean passed,
        String passRateStr,
        Map<String, Integer[]> layerBreakdown,
        List<Regression_Test_Result__c> failures
    ) {
        String statusColor = passed ? '#4CAF50' : '#F44336';
        String statusLabel = passed ? 'PASSED' : 'FAILED';
        String runDate = run.Completed_Date__c != null
            ? run.Completed_Date__c.format('yyyy-MM-dd HH:mm')
            : (run.Run_Date__c != null ? run.Run_Date__c.format('yyyy-MM-dd HH:mm') : 'N/A');

        Integer totalTests = run.Total_Tests__c != null ? run.Total_Tests__c.intValue() : 0;
        Integer passedCount = run.Passed__c != null ? run.Passed__c.intValue() : 0;
        Integer failedCount = run.Failed__c != null ? run.Failed__c.intValue() : 0;
        Integer skippedCount = run.Skipped__c != null ? run.Skipped__c.intValue() : 0;
        Decimal durationSec = run.Duration_Seconds__c != null ? run.Duration_Seconds__c : 0;
        Integer regressionCount = run.Regression_Count__c != null
            ? run.Regression_Count__c.intValue() : 0;

        String orgBaseUrl = URL.getOrgDomainURL().toExternalForm();

        String html = '';
        html += '<div style="font-family:Arial,sans-serif;max-width:700px;margin:0 auto;">';

        // Header
        html += '<div style="background:' + statusColor
            + ';color:#fff;padding:20px;text-align:center;">';
        html += '<h1 style="margin:0;font-size:24px;">ForceGuard Test Report</h1>';
        html += '<h2 style="margin:8px 0 0 0;font-size:18px;">' + suiteName + '</h2>';
        html += '<p style="margin:8px 0 0 0;font-size:14px;">' + runDate + '</p>';
        html += '</div>';

        // Status badge
        html += '<div style="padding:20px;background:#f5f5f5;">';
        html += '<table style="width:100%;border-collapse:collapse;margin-bottom:16px;">';
        html += '<tr>';
        html += '<td style="padding:8px;font-weight:bold;">Status</td>';
        html += '<td style="padding:8px;color:' + statusColor + ';font-weight:bold;">'
            + statusLabel + '</td>';
        html += '<td style="padding:8px;font-weight:bold;">Pass Rate</td>';
        html += '<td style="padding:8px;">' + passRateStr + '%</td>';
        html += '</tr>';
        html += '<tr>';
        html += '<td style="padding:8px;font-weight:bold;">Total Tests</td>';
        html += '<td style="padding:8px;">' + totalTests + '</td>';
        html += '<td style="padding:8px;font-weight:bold;">Duration</td>';
        html += '<td style="padding:8px;">' + durationSec.setScale(1) + 's</td>';
        html += '</tr>';
        html += '<tr>';
        html += '<td style="padding:8px;font-weight:bold;">Passed</td>';
        html += '<td style="padding:8px;color:#4CAF50;">' + passedCount + '</td>';
        html += '<td style="padding:8px;font-weight:bold;">Failed</td>';
        html += '<td style="padding:8px;color:#F44336;">' + failedCount + '</td>';
        html += '</tr>';
        html += '<tr>';
        html += '<td style="padding:8px;font-weight:bold;">Skipped</td>';
        html += '<td style="padding:8px;">' + skippedCount + '</td>';
        html += '<td style="padding:8px;font-weight:bold;">Regressions</td>';
        if (regressionCount > 0) {
            html += '<td style="padding:8px;color:#F44336;font-weight:bold;">'
                + regressionCount + '</td>';
        } else {
            html += '<td style="padding:8px;">0</td>';
        }
        html += '</tr>';
        html += '</table>';

        // Layer breakdown
        if (!layerBreakdown.isEmpty()) {
            html += '<h3 style="margin:16px 0 8px 0;">Results by Layer</h3>';
            html += '<table style="width:100%;border-collapse:collapse;border:1px solid #ddd;">';
            html += '<tr style="background:#e0e0e0;">';
            html += '<th style="padding:8px;text-align:left;border:1px solid #ddd;">Layer</th>';
            html += '<th style="padding:8px;text-align:center;border:1px solid #ddd;">Total</th>';
            html += '<th style="padding:8px;text-align:center;border:1px solid #ddd;">Passed</th>';
            html += '<th style="padding:8px;text-align:center;border:1px solid #ddd;">Failed</th>';
            html += '<th style="padding:8px;text-align:center;border:1px solid #ddd;">Skipped</th>';
            html += '</tr>';
            List<String> sortedLayers = new List<String>(layerBreakdown.keySet());
            sortedLayers.sort();
            for (String layer : sortedLayers) {
                Integer[] counts = layerBreakdown.get(layer);
                html += '<tr>';
                html += '<td style="padding:8px;border:1px solid #ddd;">' + layer + '</td>';
                html += '<td style="padding:8px;text-align:center;border:1px solid #ddd;">'
                    + counts[0] + '</td>';
                html += '<td style="padding:8px;text-align:center;border:1px solid #ddd;color:#4CAF50;">'
                    + counts[1] + '</td>';
                html += '<td style="padding:8px;text-align:center;border:1px solid #ddd;color:#F44336;">'
                    + counts[2] + '</td>';
                html += '<td style="padding:8px;text-align:center;border:1px solid #ddd;">'
                    + counts[3] + '</td>';
                html += '</tr>';
            }
            html += '</table>';
        }

        // Failure details
        if (!failures.isEmpty()) {
            html += '<h3 style="margin:16px 0 8px 0;color:#F44336;">Failed Tests</h3>';
            html += '<table style="width:100%;border-collapse:collapse;border:1px solid #ddd;">';
            html += '<tr style="background:#FFEBEE;">';
            html += '<th style="padding:8px;text-align:left;border:1px solid #ddd;">Test Case</th>';
            html += '<th style="padding:8px;text-align:left;border:1px solid #ddd;">Layer</th>';
            html += '<th style="padding:8px;text-align:left;border:1px solid #ddd;">Error</th>';
            html += '</tr>';
            for (Regression_Test_Result__c fail : failures) {
                String testName = fail.Test_Case__r != null && fail.Test_Case__r.Title__c != null
                    ? fail.Test_Case__r.Title__c : 'Unknown';
                String errorMsg = fail.Error_Message__c != null
                    ? fail.Error_Message__c : 'No details';
                String layer = fail.Layer__c != null ? fail.Layer__c : 'Unknown';
                html += '<tr>';
                html += '<td style="padding:8px;border:1px solid #ddd;">'
                    + testName + '</td>';
                html += '<td style="padding:8px;border:1px solid #ddd;">'
                    + layer + '</td>';
                html += '<td style="padding:8px;border:1px solid #ddd;font-size:12px;">'
                    + errorMsg + '</td>';
                html += '</tr>';
            }
            html += '</table>';
        }

        // Dashboard link
        html += '<div style="text-align:center;margin:20px 0;">';
        html += '<a href="' + orgBaseUrl + '/lightning/n/ForceGuard_Dashboard" '
            + 'style="background:#1976D2;color:#fff;padding:12px 24px;'
            + 'text-decoration:none;border-radius:4px;font-weight:bold;">'
            + 'View Dashboard</a>';
        html += '</div>';

        html += '</div>'; // end padding div

        // Footer
        html += '<div style="background:#f5f5f5;padding:12px;text-align:center;'
            + 'font-size:12px;color:#757575;border-top:1px solid #ddd;">';
        html += 'ForceGuard Regression Testing Framework | '
            + DateTime.now().format('yyyy-MM-dd HH:mm:ss z');
        html += '</div>';

        html += '</div>'; // end outer div
        return html;
    }

    @TestVisible
    public class NotificationConfig {
        public String emails;
        public String triggerCondition;
    }
}
