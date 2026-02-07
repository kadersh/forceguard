import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getDashboardSummary from '@salesforce/apex/RegressionDashboardController.getDashboardSummary';
import getSuiteOverviews from '@salesforce/apex/RegressionDashboardController.getSuiteOverviews';
import getRecentRuns from '@salesforce/apex/RegressionDashboardController.getRecentRuns';
import runSuiteApex from '@salesforce/apex/RegressionDashboardController.runSuite';
import getBatchJobStatus from '@salesforce/apex/RegressionDashboardController.getBatchJobStatus';
import scheduleRunApex from '@salesforce/apex/RegressionDashboardController.scheduleRun';

const POLL_INTERVAL_MS = 3000;
const COMPLETED_STATUSES = ['Completed', 'Failed', 'Aborted'];

const SUITE_COLUMNS = [
    { label: 'Suite Name', fieldName: 'suiteName', type: 'text', sortable: true },
    { label: 'Product', fieldName: 'productName', type: 'text', sortable: true },
    { label: 'Version', fieldName: 'version', type: 'text' },
    { label: 'Status', fieldName: 'lastRunStatus', type: 'text', sortable: true },
    {
        label: 'Pass Rate',
        fieldName: 'passRate',
        type: 'number',
        typeAttributes: { minimumFractionDigits: 1, maximumFractionDigits: 1, suffix: '%' },
        sortable: true
    },
    { label: 'Test Cases', fieldName: 'testCaseCount', type: 'number' },
    { label: 'Last Run', fieldName: 'lastRunDate', type: 'date',
        typeAttributes: { year: 'numeric', month: 'short', day: '2-digit',
            hour: '2-digit', minute: '2-digit' }
    },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [
                { label: 'Run Now', name: 'run_now' }
            ]
        }
    }
];

const RUN_COLUMNS = [
    { label: 'Run #', fieldName: 'Name', type: 'text' },
    { label: 'Suite', fieldName: 'suiteName', type: 'text', sortable: true },
    { label: 'Run Date', fieldName: 'Run_Date__c', type: 'date',
        typeAttributes: { year: 'numeric', month: 'short', day: '2-digit',
            hour: '2-digit', minute: '2-digit' },
        sortable: true
    },
    { label: 'Status', fieldName: 'Status__c', type: 'text', sortable: true },
    {
        label: 'Pass Rate',
        fieldName: 'Pass_Rate__c',
        type: 'percent',
        typeAttributes: { minimumFractionDigits: 1, maximumFractionDigits: 1 },
        sortable: true
    },
    { label: 'Total', fieldName: 'Total_Tests__c', type: 'number' },
    { label: 'Passed', fieldName: 'Passed__c', type: 'number' },
    { label: 'Failed', fieldName: 'Failed__c', type: 'number' },
    {
        label: 'Duration (s)',
        fieldName: 'Duration_Seconds__c',
        type: 'number',
        typeAttributes: { minimumFractionDigits: 1, maximumFractionDigits: 1 }
    }
];

export default class RegressionTestDashboard extends LightningElement {
    // Wire results for refreshApex
    _wiredSummary;
    _wiredSuites;
    _wiredRuns;

    // Summary card data
    summaryData;

    // Suite datatable
    suiteData = [];
    suiteColumns = SUITE_COLUMNS;

    // Run datatable
    runData = [];
    runColumns = RUN_COLUMNS;
    runSortedBy = 'Run_Date__c';
    runSortedDirection = 'desc';

    // Loading / error state
    isLoading = true;
    error;

    // Running job state
    isRunning = false;
    activeJobId;
    jobStatus = '';
    jobProgress = 0;
    _pollTimerId;

    // Schedule modal state
    showScheduleModal = false;
    selectedFrequency = '';

    get frequencyOptions() {
        return [
            { label: 'Daily (2:00 AM)', value: 'daily' },
            { label: 'Weekly (Monday 2:00 AM)', value: 'weekly' },
            { label: 'Monthly (1st at 2:00 AM)', value: 'monthly' }
        ];
    }

    get isScheduleDisabled() {
        return !this.selectedFrequency;
    }

    // Summary card display getters
    get displayPassRate() {
        if (this.summaryData && this.summaryData.overallPassRate != null) {
            return this.summaryData.overallPassRate + '%';
        }
        return '--';
    }

    get displayTotalTests() {
        return this.summaryData ? (this.summaryData.totalTestCases || 0) : '--';
    }

    get displayFailures() {
        return this.summaryData ? (this.summaryData.totalFailures || 0) : '--';
    }

    get displaySuites() {
        return this.summaryData ? (this.summaryData.totalSuites || 0) : '--';
    }

    get hasSuites() {
        return this.suiteData && this.suiteData.length > 0;
    }

    get hasRuns() {
        return this.runData && this.runData.length > 0;
    }

    // Wire: Dashboard Summary
    @wire(getDashboardSummary)
    wiredSummary(result) {
        this._wiredSummary = result;
        if (result.data) {
            this.summaryData = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = this._reduceError(result.error);
            this.summaryData = undefined;
        }
        this._checkLoading();
    }

    // Wire: Suite Overviews
    @wire(getSuiteOverviews)
    wiredSuites(result) {
        this._wiredSuites = result;
        if (result.data) {
            this.suiteData = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = this._reduceError(result.error);
            this.suiteData = [];
        }
        this._checkLoading();
    }

    // Wire: Recent Runs
    @wire(getRecentRuns, { runLimit: 10 })
    wiredRuns(result) {
        this._wiredRuns = result;
        if (result.data) {
            this.runData = this._flattenRunData(result.data);
            this.error = undefined;
        } else if (result.error) {
            this.error = this._reduceError(result.error);
            this.runData = [];
        }
        this._checkLoading();
    }

    disconnectedCallback() {
        this._stopPolling();
    }

    // --- Suite Row Actions ---
    handleSuiteRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;
        if (action.name === 'run_now') {
            this._executeRun(row.suiteId);
        }
    }

    // --- Run Suite ---
    async _executeRun(suiteId) {
        try {
            this.isRunning = true;
            this.jobProgress = 0;
            this.jobStatus = 'Queued';
            this.activeJobId = await runSuiteApex({ suiteId });
            this._startPolling();
            this.dispatchEvent(new ShowToastEvent({
                title: 'Test Run Started',
                message: 'Regression test suite is now running.',
                variant: 'success'
            }));
        } catch (err) {
            this.isRunning = false;
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error Starting Run',
                message: this._reduceError(err),
                variant: 'error'
            }));
        }
    }

    // --- Polling for batch job status ---
    _startPolling() {
        this._stopPolling();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._pollTimerId = setInterval(() => {
            this._pollJobStatus();
        }, POLL_INTERVAL_MS);
    }

    _stopPolling() {
        if (this._pollTimerId) {
            clearInterval(this._pollTimerId);
            this._pollTimerId = undefined;
        }
    }

    async _pollJobStatus() {
        if (!this.activeJobId) {
            this._stopPolling();
            return;
        }
        try {
            const result = await getBatchJobStatus({ jobId: this.activeJobId });
            this.jobStatus = result.status;
            this.jobProgress = result.progress;

            if (COMPLETED_STATUSES.includes(result.status)) {
                this._stopPolling();
                this.isRunning = false;
                this.activeJobId = null;
                await this._refreshAll();
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Test Run Complete',
                    message: 'Status: ' + result.status +
                        (result.errors > 0 ? ' (' + result.errors + ' errors)' : ''),
                    variant: result.status === 'Completed' ? 'success' : 'warning'
                }));
            }
        } catch (err) {
            this._stopPolling();
            this.isRunning = false;
        }
    }

    // --- Schedule Modal ---
    handleOpenScheduleModal() {
        this.showScheduleModal = true;
        this.selectedFrequency = '';
    }

    handleCloseScheduleModal() {
        this.showScheduleModal = false;
    }

    handleFrequencyChange(event) {
        this.selectedFrequency = event.detail.value;
    }

    async handleSchedule() {
        try {
            await scheduleRunApex({
                frequency: this.selectedFrequency,
                suiteId: null
            });
            this.showScheduleModal = false;
            this.dispatchEvent(new ShowToastEvent({
                title: 'Schedule Set',
                message: 'Regression tests scheduled: ' + this.selectedFrequency,
                variant: 'success'
            }));
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Scheduling Error',
                message: this._reduceError(err),
                variant: 'error'
            }));
        }
    }

    // --- Run Sort ---
    handleRunSort(event) {
        const { fieldName, sortDirection } = event.detail;
        this.runSortedBy = fieldName;
        this.runSortedDirection = sortDirection;
        this.runData = this._sortData(
            [...this.runData],
            fieldName,
            sortDirection
        );
    }

    // --- Helpers ---
    _checkLoading() {
        if (this._wiredSummary && this._wiredSuites && this._wiredRuns) {
            this.isLoading = false;
        }
    }

    _flattenRunData(runs) {
        return runs.map(run => ({
            ...run,
            suiteName: run.Test_Suite__r ? run.Test_Suite__r.Product_Name__c : ''
        }));
    }

    _sortData(data, fieldName, sortDirection) {
        const reverse = sortDirection === 'asc' ? 1 : -1;
        return data.sort((a, b) => {
            const valA = a[fieldName] || '';
            const valB = b[fieldName] || '';
            if (valA < valB) return -1 * reverse;
            if (valA > valB) return 1 * reverse;
            return 0;
        });
    }

    async _refreshAll() {
        await Promise.all([
            refreshApex(this._wiredSummary),
            refreshApex(this._wiredSuites),
            refreshApex(this._wiredRuns)
        ]);
    }

    _reduceError(error) {
        if (typeof error === 'string') {
            return error;
        }
        if (error?.body?.message) {
            return error.body.message;
        }
        if (error?.message) {
            return error.message;
        }
        return 'Unknown error';
    }
}
