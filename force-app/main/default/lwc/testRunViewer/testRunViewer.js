import { LightningElement, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getTestRuns from '@salesforce/apex/TestRunViewerController.getTestRuns';
import getRunDetail from '@salesforce/apex/TestRunViewerController.getRunDetail';
import rerunFailed from '@salesforce/apex/TestRunViewerController.rerunFailed';
import exportCsv from '@salesforce/apex/TestRunViewerController.exportCsv';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const PAGE_SIZE = 10;

const ACTIONS = [
    { label: 'View Detail', name: 'view_detail' },
    { label: 'Re-run Failed', name: 'rerun_failed' },
    { label: 'Export CSV', name: 'export_csv' }
];

const COLUMNS = [
    {
        label: 'Run #', fieldName: 'Name', type: 'text',
        cellAttributes: { class: 'slds-text-title_bold' }
    },
    {
        label: 'Run Date', fieldName: 'Run_Date__c', type: 'date',
        typeAttributes: {
            year: 'numeric', month: 'short', day: '2-digit',
            hour: '2-digit', minute: '2-digit'
        }
    },
    { label: 'Suite', fieldName: 'suiteName', type: 'text' },
    { label: 'Status', fieldName: 'Status__c', type: 'text' },
    {
        label: 'Pass Rate', fieldName: 'Pass_Rate__c', type: 'percent',
        typeAttributes: { maximumFractionDigits: 1 }
    },
    { label: 'Total', fieldName: 'Total_Tests__c', type: 'number' },
    { label: 'Passed', fieldName: 'Passed__c', type: 'number' },
    { label: 'Failed', fieldName: 'Failed__c', type: 'number' },
    {
        label: 'Duration (s)', fieldName: 'Duration_Seconds__c', type: 'number',
        typeAttributes: { maximumFractionDigits: 1 }
    },
    { type: 'action', typeAttributes: { rowActions: ACTIONS } }
];

export default class TestRunViewer extends LightningElement {
    columns = COLUMNS;
    @track runs = [];
    totalCount = 0;
    pageOffset = 0;

    selectedSuiteId = '';
    selectedStatus = 'All';

    selectedRunId = null;
    runDetail = null;
    isLoadingDetail = false;

    sortedBy;
    sortedDirection;

    _wiredRunsResult;

    get statusOptions() {
        return [
            { label: 'All', value: 'All' },
            { label: 'Completed', value: 'Completed' },
            { label: 'Failed', value: 'Failed' },
            { label: 'Running', value: 'Running' },
            { label: 'Queued', value: 'Queued' },
            { label: 'Error', value: 'Error' }
        ];
    }

    get suiteOptions() {
        return [{ label: 'All Suites', value: '' }];
    }

    get hasRuns() {
        return this.runs && this.runs.length > 0;
    }

    get currentPage() {
        return Math.floor(this.pageOffset / PAGE_SIZE) + 1;
    }

    get totalPages() {
        return Math.max(1, Math.ceil(this.totalCount / PAGE_SIZE));
    }

    get isPrevDisabled() {
        return this.pageOffset <= 0;
    }

    get isNextDisabled() {
        return (this.pageOffset + PAGE_SIZE) >= this.totalCount;
    }

    get detailTitle() {
        if (this.runDetail && this.runDetail.run) {
            return 'Run Detail: ' + this.runDetail.run.Name;
        }
        return 'Run Detail';
    }

    get statusBadgeClass() {
        if (!this.runDetail || !this.runDetail.run) {
            return '';
        }
        const status = this.runDetail.run.Status__c;
        if (status === 'Completed') return 'slds-theme_success';
        if (status === 'Failed') return 'slds-theme_error';
        if (status === 'Running') return 'slds-theme_info';
        return '';
    }

    get formattedPassRate() {
        if (!this.runDetail || !this.runDetail.run || this.runDetail.run.Pass_Rate__c == null) {
            return '0%';
        }
        return (this.runDetail.run.Pass_Rate__c * 100).toFixed(1) + '%';
    }

    @wire(getTestRuns, {
        suiteId: '$wireFilterSuiteId',
        statusFilter: '$selectedStatus',
        pageSize: PAGE_SIZE,
        pageOffset: '$pageOffset'
    })
    wiredRuns(result) {
        this._wiredRunsResult = result;
        const { data, error } = result;
        if (data) {
            this.runs = data.runs.map(run => ({
                ...run,
                suiteName: run.Test_Suite__r ? run.Test_Suite__r.Product_Name__c : '',
                Pass_Rate__c: run.Pass_Rate__c != null ? run.Pass_Rate__c / 100 : 0
            }));
            this.totalCount = data.totalCount;
        } else if (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        }
    }

    get wireFilterSuiteId() {
        return this.selectedSuiteId || null;
    }

    handleSuiteChange(event) {
        this.selectedSuiteId = event.detail.value;
        this.pageOffset = 0;
    }

    handleStatusChange(event) {
        this.selectedStatus = event.detail.value;
        this.pageOffset = 0;
    }

    handleRefresh() {
        refreshApex(this._wiredRunsResult);
    }

    handlePrevious() {
        if (this.pageOffset >= PAGE_SIZE) {
            this.pageOffset -= PAGE_SIZE;
        }
    }

    handleNext() {
        if ((this.pageOffset + PAGE_SIZE) < this.totalCount) {
            this.pageOffset += PAGE_SIZE;
        }
    }

    handleRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;

        switch (action.name) {
            case 'view_detail':
                this.loadRunDetail(row.Id);
                break;
            case 'rerun_failed':
                this.handleRerunFailed(row.Id);
                break;
            case 'export_csv':
                this.handleExportCsv(row.Id, row.Name);
                break;
            default:
                break;
        }
    }

    loadRunDetail(runId) {
        this.selectedRunId = runId;
        this.isLoadingDetail = true;

        getRunDetail({ runId: runId })
            .then(result => {
                const detail = { ...result };
                if (detail.layerSummaries) {
                    detail.layerSummaries = detail.layerSummaries.map(layer => ({
                        ...layer,
                        badgeClass: layer.status === 'Passed' ? 'slds-theme_success' :
                                    layer.status === 'Failed' ? 'slds-theme_error' : ''
                    }));
                }
                this.runDetail = detail;
                this.isLoadingDetail = false;
            })
            .catch(error => {
                this.showToast('Error', this.reduceErrors(error), 'error');
                this.isLoadingDetail = false;
            });
    }

    handleCloseDetail() {
        this.selectedRunId = null;
        this.runDetail = null;
    }

    handleRerunFailed(runId) {
        rerunFailed({ runId: runId })
            .then(newRunId => {
                this.showToast('Success', 'Re-run created: ' + newRunId, 'success');
                return refreshApex(this._wiredRunsResult);
            })
            .catch(error => {
                this.showToast('Error', this.reduceErrors(error), 'error');
            });
    }

    handleExportCsv(runId, runName) {
        exportCsv({ runId: runId })
            .then(csvString => {
                const blob = new Blob([csvString], { type: 'text/csv;charset=utf-8;' });
                const link = document.createElement('a');
                link.href = URL.createObjectURL(blob);
                link.download = (runName || 'test-run') + '-results.csv';
                link.click();
                URL.revokeObjectURL(link.href);
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
