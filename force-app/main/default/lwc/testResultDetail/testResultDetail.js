import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getRunResults from '@salesforce/apex/TestResultDetailController.getRunResults';
import getResultDetail from '@salesforce/apex/TestResultDetailController.getResultDetail';
import markKnownIssue from '@salesforce/apex/TestResultDetailController.markKnownIssue';
import rerunTestCase from '@salesforce/apex/TestResultDetailController.rerunTestCase';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const LAYER_ORDER = ['Deployment', 'Apex Test', 'Data Scenario', 'Static Analysis'];

const RESULT_ACTIONS = [
    { label: 'View Detail', name: 'view_detail' },
    { label: 'Re-run Test', name: 'rerun_test' }
];

const RESULT_COLUMNS = [
    { label: 'Test Case', fieldName: 'testCaseTitle', type: 'text' },
    { label: 'Status', fieldName: 'status', type: 'text' },
    { label: 'Duration (ms)', fieldName: 'durationMs', type: 'number' },
    { label: 'Regression', fieldName: 'isRegression', type: 'boolean' },
    { label: 'Known Issue', fieldName: 'isKnownIssue', type: 'boolean' },
    { label: 'Priority', fieldName: 'priority', type: 'text' },
    { type: 'action', typeAttributes: { rowActions: RESULT_ACTIONS } }
];

export default class TestResultDetail extends LightningElement {
    @api runId;

    resultColumns = RESULT_COLUMNS;
    @track layerList = [];
    runInfo = null;
    isLoading = true;

    selectedResult = null;
    selectedResultId = null;
    isLoadingResultDetail = false;

    activeSections = [...LAYER_ORDER];

    _wiredResultsData;

    get hasLayers() {
        return this.layerList && this.layerList.length > 0;
    }

    get suiteName() {
        if (this.runInfo && this.runInfo.Test_Suite__r) {
            return this.runInfo.Test_Suite__r.Product_Name__c;
        }
        return '';
    }

    get runStatusBadgeClass() {
        if (!this.runInfo) return '';
        const status = this.runInfo.Status__c;
        if (status === 'Completed') return 'slds-theme_success';
        if (status === 'Failed') return 'slds-theme_error';
        if (status === 'Running') return 'slds-theme_info';
        return '';
    }

    get formattedPassRate() {
        if (!this.runInfo || this.runInfo.Pass_Rate__c == null) return '0%';
        return (this.runInfo.Pass_Rate__c * 100).toFixed(1) + '%';
    }

    get selectedResultTitle() {
        if (this.selectedResult) {
            return 'Result: ' + this.selectedResult.testCaseTitle;
        }
        return 'Result Detail';
    }

    get selectedResultBadgeClass() {
        if (!this.selectedResult || !this.selectedResult.result) return '';
        const status = this.selectedResult.result.Status__c;
        if (status === 'Passed') return 'slds-theme_success';
        if (status === 'Failed' || status === 'Error') return 'slds-theme_error';
        if (status === 'Skipped') return 'slds-theme_warning';
        return '';
    }

    get selectedResultActual() {
        if (this.selectedResult && this.selectedResult.result && this.selectedResult.result.Actual_Result__c) {
            return this.selectedResult.result.Actual_Result__c;
        }
        return 'N/A';
    }

    get hasNoError() {
        return !this.selectedResult || !this.selectedResult.result || !this.selectedResult.result.Error_Message__c;
    }

    @wire(getRunResults, { runId: '$runId' })
    wiredResults(result) {
        this._wiredResultsData = result;
        const { data, error } = result;
        if (data) {
            this.runInfo = data.runInfo;
            this.layerList = this.buildLayerList(data.layers);
            this.isLoading = false;
        } else if (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
            this.isLoading = false;
        }
    }

    buildLayerList(layersMap) {
        if (!layersMap) return [];

        const result = [];
        for (const layerName of LAYER_ORDER) {
            const items = layersMap[layerName];
            if (items && items.length > 0) {
                const passedCount = items.filter(i => i.result.Status__c === 'Passed').length;
                const failedCount = items.filter(i => i.result.Status__c === 'Failed' || i.result.Status__c === 'Error').length;

                result.push({
                    name: layerName,
                    sectionLabel: layerName + ' (' + passedCount + '/' + items.length + ' passed, ' + failedCount + ' failed)',
                    items: items.map(item => ({
                        resultId: item.result.Id,
                        testCaseTitle: item.testCaseTitle,
                        testCaseId: item.testCaseId,
                        status: item.result.Status__c,
                        durationMs: item.result.Duration_Ms__c,
                        isRegression: item.result.Is_Regression__c,
                        isKnownIssue: item.result.Is_Known_Issue__c,
                        priority: item.priority,
                        category: item.category,
                        suiteId: this.runInfo ? this.runInfo.Test_Suite__c : null
                    }))
                });
            }
        }
        return result;
    }

    handleResultAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;

        switch (action.name) {
            case 'view_detail':
                this.loadResultDetail(row.resultId);
                break;
            case 'rerun_test':
                this.handleRerunTest(row.testCaseId, row.suiteId);
                break;
            default:
                break;
        }
    }

    loadResultDetail(resultId) {
        this.selectedResultId = resultId;
        this.isLoadingResultDetail = true;

        getResultDetail({ resultId: resultId })
            .then(data => {
                this.selectedResult = data;
                this.isLoadingResultDetail = false;
            })
            .catch(error => {
                this.showToast('Error', this.reduceErrors(error), 'error');
                this.isLoadingResultDetail = false;
            });
    }

    handleCloseResultDetail() {
        this.selectedResult = null;
        this.selectedResultId = null;
    }

    handleToggleKnownIssue(event) {
        const isKnown = event.target.checked;
        markKnownIssue({ resultId: this.selectedResultId, isKnown: isKnown })
            .then(() => {
                this.showToast('Success',
                    isKnown ? 'Marked as known issue' : 'Removed known issue flag',
                    'success'
                );
                return refreshApex(this._wiredResultsData);
            })
            .then(() => {
                this.loadResultDetail(this.selectedResultId);
            })
            .catch(error => {
                this.showToast('Error', this.reduceErrors(error), 'error');
            });
    }

    handleCopyError() {
        if (this.selectedResult && this.selectedResult.result && this.selectedResult.result.Error_Message__c) {
            const text = this.selectedResult.result.Error_Message__c;
            if (navigator.clipboard && navigator.clipboard.writeText) {
                navigator.clipboard.writeText(text).then(() => {
                    this.showToast('Copied', 'Error message copied to clipboard', 'success');
                });
            }
        }
    }

    handleRerunTest(testCaseId, suiteId) {
        rerunTestCase({ testCaseId: testCaseId, suiteId: suiteId })
            .then(newRunId => {
                this.showToast('Success', 'Re-run created: ' + newRunId, 'success');
            })
            .catch(error => {
                this.showToast('Error', this.reduceErrors(error), 'error');
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceErrors(error) {
        if (typeof error === 'string') return error;
        if (error.body && error.body.message) return error.body.message;
        if (error.message) return error.message;
        return 'Unknown error';
    }
}
