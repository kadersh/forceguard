/**
 * RegressionTestResultTrigger - Fires after insert on Regression_Test_Result__c.
 * Creates Regression_Finding__c records for results that represent regressions.
 */
trigger RegressionTestResultTrigger on Regression_Test_Result__c (after insert) {
    if (FeatureManagement.checkPermission('Bypass_All_Automation')) {
        return;
    }
    RegressionFindingHandler.handleAfterInsert(Trigger.new);
}
