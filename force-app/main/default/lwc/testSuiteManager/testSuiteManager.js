import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getSuites from '@salesforce/apex/TestSuiteManagerController.getSuites';
import getTestCases from '@salesforce/apex/TestSuiteManagerController.getTestCases';
import createSuite from '@salesforce/apex/TestSuiteManagerController.createSuite';
import updateSuite from '@salesforce/apex/TestSuiteManagerController.updateSuite';
import createTestCase from '@salesforce/apex/TestSuiteManagerController.createTestCase';
import updateTestCase from '@salesforce/apex/TestSuiteManagerController.updateTestCase';
import deleteTestCases from '@salesforce/apex/TestSuiteManagerController.deleteTestCases';
import toggleActive from '@salesforce/apex/TestSuiteManagerController.toggleActive';

const LAYER_OPTIONS = [
    { label: 'All Layers', value: '' },
    { label: 'Deployment', value: 'Deployment' },
    { label: 'Apex Test', value: 'Apex Test' },
    { label: 'Data Scenario', value: 'Data Scenario' },
    { label: 'Static Analysis', value: 'Static Analysis' }
];

const CATEGORY_OPTIONS = [
    { label: 'All Categories', value: '' },
    { label: 'Deployment', value: 'Deployment' },
    { label: 'Functional', value: 'Functional' },
    { label: 'Edge Case', value: 'Edge Case' },
    { label: 'Bulk Performance', value: 'Bulk Performance' },
    { label: 'Security Permission', value: 'Security Permission' },
    { label: 'Integration', value: 'Integration' },
    { label: 'Regression', value: 'Regression' },
    { label: 'UAT', value: 'UAT' }
];

const PRIORITY_OPTIONS = [
    { label: 'All Priorities', value: '' },
    { label: 'P0', value: 'P0' },
    { label: 'P1', value: 'P1' },
    { label: 'P2', value: 'P2' }
];

const TEST_LAYER_PICKLIST = [
    { label: 'Deployment', value: 'Deployment' },
    { label: 'Apex Test', value: 'Apex Test' },
    { label: 'Data Scenario', value: 'Data Scenario' },
    { label: 'Static Analysis', value: 'Static Analysis' }
];

const CATEGORY_PICKLIST = [
    { label: 'Deployment', value: 'Deployment' },
    { label: 'Functional', value: 'Functional' },
    { label: 'Edge Case', value: 'Edge Case' },
    { label: 'Bulk Performance', value: 'Bulk Performance' },
    { label: 'Security Permission', value: 'Security Permission' },
    { label: 'Integration', value: 'Integration' },
    { label: 'Regression', value: 'Regression' },
    { label: 'UAT', value: 'UAT' }
];

const PERSPECTIVE_PICKLIST = [
    { label: 'Developer', value: 'Developer' },
    { label: 'Admin', value: 'Admin' },
    { label: 'Product Manager', value: 'Product Manager' },
    { label: 'Designer', value: 'Designer' },
    { label: 'Client', value: 'Client' }
];

const PRIORITY_PICKLIST = [
    { label: 'P0', value: 'P0' },
    { label: 'P1', value: 'P1' },
    { label: 'P2', value: 'P2' }
];

const ASSERTION_TYPE_PICKLIST = [
    { label: 'Record Exists', value: 'Record Exists' },
    { label: 'Field Value', value: 'Field Value' },
    { label: 'Record Count', value: 'Record Count' },
    { label: 'Coverage Threshold', value: 'Coverage Threshold' },
    { label: 'No Error', value: 'No Error' },
    { label: 'Custom Script', value: 'Custom Script' }
];

const COLUMNS = [
    { label: 'Title', fieldName: 'Title__c', type: 'text', sortable: true },
    { label: 'Layer', fieldName: 'Test_Layer__c', type: 'text', sortable: true },
    { label: 'Category', fieldName: 'Category__c', type: 'text', sortable: true },
    { label: 'Perspective', fieldName: 'Perspective__c', type: 'text' },
    { label: 'Priority', fieldName: 'Priority__c', type: 'text', sortable: true },
    { label: 'Active', fieldName: 'Is_Active__c', type: 'boolean' },
    { label: 'Last Status', fieldName: 'Last_Result_Status__c', type: 'text' },
    { label: 'Order', fieldName: 'Execution_Order__c', type: 'number', sortable: true },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [
                { label: 'Edit', name: 'edit' },
                { label: 'Delete', name: 'delete' }
            ]
        }
    }
];

const EMPTY_SUITE_FORM = {
    Name: '',
    Product_Name__c: '',
    Version__c: '',
    Description__c: '',
    Source_Path__c: ''
};

const EMPTY_TEST_CASE_FORM = {
    Title__c: '',
    Description__c: '',
    Test_Layer__c: '',
    Category__c: '',
    Perspective__c: '',
    Priority__c: 'P1',
    Assertion_Type__c: '',
    Steps__c: '',
    Expected_Result__c: '',
    Execution_Order__c: null,
    Tags__c: '',
    Target_Object__c: ''
};

export default class TestSuiteManager extends LightningElement {
    // Suite data
    @track suites = [];
    suitesLoading = false;
    _wiredSuitesResult;

    // Test case data
    @track testCases = [];
    casesLoading = false;
    _wiredCasesResult;

    // Selection and filters
    selectedSuiteId = '';
    layerFilter = '';
    categoryFilter = '';
    priorityFilter = '';
    selectedRows = [];

    // Sorting
    sortedBy = 'Execution_Order__c';
    sortedDirection = 'asc';

    // Modals
    showSuiteModal = false;
    showTestCaseModal = false;
    isEditingSuite = false;
    isEditingTestCase = false;
    isSaving = false;
    editingSuiteId = null;
    editingTestCaseId = null;

    // Forms
    @track suiteForm = { ...EMPTY_SUITE_FORM };
    @track testCaseForm = { ...EMPTY_TEST_CASE_FORM };

    // Expose constants to template
    get columns() { return COLUMNS; }
    get layerOptions() { return LAYER_OPTIONS; }
    get categoryOptions() { return CATEGORY_OPTIONS; }
    get priorityOptions() { return PRIORITY_OPTIONS; }
    get testLayerPicklist() { return TEST_LAYER_PICKLIST; }
    get categoryPicklist() { return CATEGORY_PICKLIST; }
    get perspectivePicklist() { return PERSPECTIVE_PICKLIST; }
    get priorityPicklist() { return PRIORITY_PICKLIST; }
    get assertionTypePicklist() { return ASSERTION_TYPE_PICKLIST; }

    // Computed
    get hasSuites() {
        return this.suites && this.suites.length > 0;
    }

    get hasSelectedRows() {
        return this.selectedRows.length > 0;
    }

    get testCasesPanelTitle() {
        if (!this.selectedSuiteId) {
            return 'Test Cases';
        }
        const selected = this.suites.find(s => s.suite.Id === this.selectedSuiteId);
        return selected ? 'Test Cases - ' + selected.suite.Name : 'Test Cases';
    }

    get suiteModalTitle() {
        return this.isEditingSuite ? 'Edit Suite' : 'New Suite';
    }

    get testCaseModalTitle() {
        return this.isEditingTestCase ? 'Edit Test Case' : 'New Test Case';
    }

    // Wire: getSuites
    @wire(getSuites)
    wiredSuites(result) {
        this._wiredSuitesResult = result;
        this.suitesLoading = false;
        if (result.data) {
            this.suites = result.data.map(item => ({
                ...item,
                cssClass: this.selectedSuiteId === item.suite.Id
                    ? 'slds-box slds-theme_shade slds-m-bottom_xx-small suite-card suite-selected'
                    : 'slds-box slds-m-bottom_xx-small suite-card',
                statusLabel: item.suite.Last_Run_Status__c || 'Not Run',
                statusClass: this._getStatusBadgeClass(item.suite.Last_Run_Status__c)
            }));
        } else if (result.error) {
            this._showToast('Error', this._reduceErrors(result.error), 'error');
        }
    }

    // Wire: getTestCases
    @wire(getTestCases, {
        suiteId: '$selectedSuiteId',
        layerFilter: '$layerFilter',
        categoryFilter: '$categoryFilter',
        priorityFilter: '$priorityFilter'
    })
    wiredTestCases(result) {
        this._wiredCasesResult = result;
        this.casesLoading = false;
        if (result.data) {
            this.testCases = result.data;
        } else if (result.error) {
            this._showToast('Error', this._reduceErrors(result.error), 'error');
        }
    }

    // --- Suite Handlers ---

    handleSuiteSelect(event) {
        const suiteId = event.currentTarget.dataset.suiteId;
        if (this.selectedSuiteId === suiteId) {
            return;
        }
        this.selectedSuiteId = suiteId;
        this.selectedRows = [];
        this.casesLoading = true;
        // Update CSS classes for selection highlight
        this.suites = this.suites.map(item => ({
            ...item,
            cssClass: this.selectedSuiteId === item.suite.Id
                ? 'slds-box slds-theme_shade slds-m-bottom_xx-small suite-card suite-selected'
                : 'slds-box slds-m-bottom_xx-small suite-card'
        }));
    }

    handleNewSuite() {
        this.isEditingSuite = false;
        this.editingSuiteId = null;
        this.suiteForm = { ...EMPTY_SUITE_FORM };
        this.showSuiteModal = true;
    }

    handleEditSuite(event) {
        event.stopPropagation();
        const suiteId = event.currentTarget.dataset.suiteId;
        const item = this.suites.find(s => s.suite.Id === suiteId);
        if (item) {
            this.isEditingSuite = true;
            this.editingSuiteId = suiteId;
            this.suiteForm = {
                Name: item.suite.Name || '',
                Product_Name__c: item.suite.Product_Name__c || '',
                Version__c: item.suite.Version__c || '',
                Description__c: item.suite.Description__c || '',
                Source_Path__c: item.suite.Source_Path__c || ''
            };
            this.showSuiteModal = true;
        }
    }

    handleCloseSuiteModal() {
        this.showSuiteModal = false;
    }

    handleSuiteFormChange(event) {
        const field = event.target.dataset.field;
        this.suiteForm = { ...this.suiteForm, [field]: event.target.value };
    }

    async handleSaveSuite() {
        if (!this.suiteForm.Name) {
            this._showToast('Validation Error', 'Suite Name is required.', 'error');
            return;
        }

        this.isSaving = true;
        try {
            const suiteRecord = {
                Name: this.suiteForm.Name,
                Product_Name__c: this.suiteForm.Product_Name__c,
                Version__c: this.suiteForm.Version__c,
                Description__c: this.suiteForm.Description__c,
                Source_Path__c: this.suiteForm.Source_Path__c,
                Is_Active__c: true
            };

            if (this.isEditingSuite) {
                suiteRecord.Id = this.editingSuiteId;
                await updateSuite({ suite: suiteRecord });
                this._showToast('Success', 'Suite updated successfully.', 'success');
            } else {
                await createSuite({ suite: suiteRecord });
                this._showToast('Success', 'Suite created successfully.', 'success');
            }

            this.showSuiteModal = false;
            await refreshApex(this._wiredSuitesResult);
        } catch (error) {
            this._showToast('Error', this._reduceErrors(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    // --- Filter Handlers ---

    handleLayerChange(event) {
        this.layerFilter = event.detail.value;
        this.casesLoading = true;
    }

    handleCategoryChange(event) {
        this.categoryFilter = event.detail.value;
        this.casesLoading = true;
    }

    handlePriorityChange(event) {
        this.priorityFilter = event.detail.value;
        this.casesLoading = true;
    }

    // --- Sort Handler ---

    handleSort(event) {
        const { fieldName, sortDirection } = event.detail;
        this.sortedBy = fieldName;
        this.sortedDirection = sortDirection;

        const clonedData = [...this.testCases];
        clonedData.sort((a, b) => {
            let valA = a[fieldName] || '';
            let valB = b[fieldName] || '';
            if (typeof valA === 'string') {
                valA = valA.toLowerCase();
                valB = (valB || '').toLowerCase();
            }
            let result = 0;
            if (valA > valB) { result = 1; }
            else if (valA < valB) { result = -1; }
            return sortDirection === 'asc' ? result : -result;
        });
        this.testCases = clonedData;
    }

    // --- Test Case Handlers ---

    handleNewTestCase() {
        this.isEditingTestCase = false;
        this.editingTestCaseId = null;
        this.testCaseForm = { ...EMPTY_TEST_CASE_FORM };
        this.showTestCaseModal = true;
    }

    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        if (actionName === 'edit') {
            this.isEditingTestCase = true;
            this.editingTestCaseId = row.Id;
            this.testCaseForm = {
                Title__c: row.Title__c || '',
                Description__c: row.Description__c || '',
                Test_Layer__c: row.Test_Layer__c || '',
                Category__c: row.Category__c || '',
                Perspective__c: row.Perspective__c || '',
                Priority__c: row.Priority__c || '',
                Assertion_Type__c: row.Assertion_Type__c || '',
                Steps__c: row.Steps__c || '',
                Expected_Result__c: row.Expected_Result__c || '',
                Execution_Order__c: row.Execution_Order__c,
                Tags__c: row.Tags__c || '',
                Target_Object__c: row.Target_Object__c || ''
            };
            this.showTestCaseModal = true;
        } else if (actionName === 'delete') {
            this._deleteTestCases([row.Id]);
        }
    }

    handleRowSelection(event) {
        this.selectedRows = event.detail.selectedRows;
    }

    handleCloseTestCaseModal() {
        this.showTestCaseModal = false;
    }

    handleTestCaseFormChange(event) {
        const field = event.target.dataset.field;
        let value = event.target.value;
        if (field === 'Execution_Order__c' && value !== null && value !== '') {
            value = parseInt(value, 10);
        }
        this.testCaseForm = { ...this.testCaseForm, [field]: value };
    }

    async handleSaveTestCase() {
        if (!this.testCaseForm.Title__c) {
            this._showToast('Validation Error', 'Title is required.', 'error');
            return;
        }
        if (!this.testCaseForm.Test_Layer__c) {
            this._showToast('Validation Error', 'Test Layer is required.', 'error');
            return;
        }

        this.isSaving = true;
        try {
            const caseRecord = {
                Title__c: this.testCaseForm.Title__c,
                Description__c: this.testCaseForm.Description__c,
                Test_Layer__c: this.testCaseForm.Test_Layer__c,
                Category__c: this.testCaseForm.Category__c,
                Perspective__c: this.testCaseForm.Perspective__c,
                Priority__c: this.testCaseForm.Priority__c,
                Assertion_Type__c: this.testCaseForm.Assertion_Type__c,
                Steps__c: this.testCaseForm.Steps__c,
                Expected_Result__c: this.testCaseForm.Expected_Result__c,
                Execution_Order__c: this.testCaseForm.Execution_Order__c,
                Tags__c: this.testCaseForm.Tags__c,
                Target_Object__c: this.testCaseForm.Target_Object__c,
                Is_Active__c: true
            };

            if (this.isEditingTestCase) {
                caseRecord.Id = this.editingTestCaseId;
                await updateTestCase({ testCase: caseRecord });
                this._showToast('Success', 'Test case updated successfully.', 'success');
            } else {
                caseRecord.Test_Suite__c = this.selectedSuiteId;
                await createTestCase({ testCase: caseRecord });
                this._showToast('Success', 'Test case created successfully.', 'success');
            }

            this.showTestCaseModal = false;
            await Promise.all([
                refreshApex(this._wiredCasesResult),
                refreshApex(this._wiredSuitesResult)
            ]);
        } catch (error) {
            this._showToast('Error', this._reduceErrors(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    // --- Bulk Handlers ---

    async handleBulkActivate() {
        const ids = this.selectedRows.map(r => r.Id);
        try {
            await toggleActive({ testCaseIds: ids, isActive: true });
            this._showToast('Success', ids.length + ' test case(s) activated.', 'success');
            this.selectedRows = [];
            await Promise.all([
                refreshApex(this._wiredCasesResult),
                refreshApex(this._wiredSuitesResult)
            ]);
        } catch (error) {
            this._showToast('Error', this._reduceErrors(error), 'error');
        }
    }

    async handleBulkDeactivate() {
        const ids = this.selectedRows.map(r => r.Id);
        try {
            await toggleActive({ testCaseIds: ids, isActive: false });
            this._showToast('Success', ids.length + ' test case(s) deactivated.', 'success');
            this.selectedRows = [];
            await Promise.all([
                refreshApex(this._wiredCasesResult),
                refreshApex(this._wiredSuitesResult)
            ]);
        } catch (error) {
            this._showToast('Error', this._reduceErrors(error), 'error');
        }
    }

    async handleBulkDelete() {
        const ids = this.selectedRows.map(r => r.Id);
        await this._deleteTestCases(ids);
    }

    // --- Private Helpers ---

    async _deleteTestCases(ids) {
        try {
            await deleteTestCases({ testCaseIds: ids });
            this._showToast('Success', ids.length + ' test case(s) deleted.', 'success');
            this.selectedRows = [];
            await Promise.all([
                refreshApex(this._wiredCasesResult),
                refreshApex(this._wiredSuitesResult)
            ]);
        } catch (error) {
            this._showToast('Error', this._reduceErrors(error), 'error');
        }
    }

    _getStatusBadgeClass(status) {
        if (!status) {
            return 'slds-badge';
        }
        switch (status) {
            case 'Passed': return 'slds-badge slds-theme_success';
            case 'Failed': return 'slds-badge slds-theme_error';
            case 'Running': return 'slds-badge slds-theme_warning';
            default: return 'slds-badge';
        }
    }

    _showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    _reduceErrors(error) {
        if (typeof error === 'string') {
            return error;
        }
        if (error?.body?.message) {
            return error.body.message;
        }
        if (error?.message) {
            return error.message;
        }
        if (Array.isArray(error?.body)) {
            return error.body.map(e => e.message).join(', ');
        }
        return 'Unknown error';
    }
}
