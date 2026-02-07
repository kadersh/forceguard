# Salesforce Audit Product (SOX/IPE Compliance) - Complete Catalog

**Product Name:** User Access Audit (UAA)
**Location:** `/home/ak/SynologyDrive/Claude/salesforce-solutions/change-requests/Audit`
**Secondary (AppExchange):** `/home/ak/SynologyDrive/Claude/salesforce-solutions/AppExchange-Packages/UserAccessAudit`
**Date Cataloged:** 2026-02-07
**Purpose:** SOX/IPE compliance tool for auditing user access, detecting changes, and enforcing controls in Salesforce orgs.

---

## Table of Contents

1. [Apex Classes](#1-apex-classes)
2. [Custom Objects](#2-custom-objects)
3. [LWC Components](#3-lwc-components)
4. [Flows](#4-flows)
5. [Permission Sets](#5-permission-sets)
6. [Custom Metadata Types](#6-custom-metadata-types)
7. [Key Business Logic](#7-key-business-logic-end-to-end)
8. [Test Infrastructure](#8-test-infrastructure)

---

## 1. Apex Classes

### 1.1 Core Service Classes (35 non-test classes)

#### UserAuditSnapshotBatch.cls
- **Type:** Batch Apex (Database.Batchable, Database.Stateful, Schedulable)
- **Purpose:** CORE batch job. Creates Audit_Run__c, queries all active Users with Profile/Role/PermissionSetAssignment, creates User_Audit_Snapshot__c records. In `finish()`, chains detection services and queueables.
- **Key Methods:**
  - `start()` - Returns QueryLocator for active Users
  - `execute()` - Creates snapshot records for each User batch
  - `finish()` - Chains: SetupAuditTrailService, LoginHistoryService, SegregationOfDutiesService, then enqueues TerminationCrossCheckQueueable
  - `isUserPrivileged()` - Checks profile/perm set for privileged access
  - `getUsersWithPrivilegedPermissionSets()` - Queries users with elevated permissions
  - `createPrivilegedAccessFindings()` - Creates findings for privileged users
  - `getLastSuccessfulLogins()` - Queries LoginHistory for last login dates
  - `scheduleMonthly()` - Schedules batch to run monthly
- **Dependencies:** QuarterlySignOffService, AuditFeatureService, SnapshotDuplicateDetectionService, SetupAuditTrailService, LoginHistoryService, SegregationOfDutiesService, TerminationCrossCheckQueueable
- **DML:** INSERT Audit_Run__c, INSERT User_Audit_Snapshot__c (batch), INSERT Audit_Finding__c (privileged access)
- **SOQL:** User, Profile, UserRole, PermissionSetAssignment, LoginHistory

#### AuditController.cls
- **Type:** LWC Controller (@AuraEnabled methods)
- **Purpose:** CORE controller for the auditDashboard LWC. Provides all dashboard data, audit execution, and finding management.
- **Key Methods:**
  - `getAuditSummary()` - (cacheable) Returns DashboardSummary with trend data, finding type counts
  - `runAuditNow()` - Starts batch job, returns batch job ID
  - `importTerminations(String csvContent)` - Parses CSV, creates Termination_Record__c, runs cross-check
  - `getFindings(String auditRunId, String severity, String findingType, String searchTerm, String sortField, String sortDirection, Integer pageSize, Integer pageNumber)` - Dynamic SOQL with bind variables for filters, returns FindingsResult with pagination
  - `resolveFindings(List<Id> findingIds, String notes)` - Bulk resolve findings
  - `updateFinding(Id findingId, String status, String notes)` - Single finding update
  - `exportFindings(String auditRunId, String severity)` - CSV export
  - `getAuditRuns()` - Returns list of AuditRunInfo wrappers
  - `getDistinctFindingTypes()` - Returns unique finding types for filters
  - `getBatchJobStatus(Id jobId)` - Checks AsyncApexJob status
- **Inner Classes:** DashboardSummary, TrendData, FindingTypeCount, AuditRunInfo, ImportResult, FindingWrapper, FindingsResult
- **Dependencies:** UserAuditSnapshotBatch, TerminationCrossCheckService, AuditFeatureService
- **Security:** Uses WITH USER_MODE, Security.stripInaccessible()

#### AuditControlCenterController.cls
- **Type:** LWC Controller (@AuraEnabled methods)
- **Purpose:** Admin console controller for managing features, configuration, scheduling, and system health.
- **Key Methods:**
  - `getControlCenterData()` - Returns ControlCenterData with feature categories, config counts, health status, recipients, dashboard ID
  - `runAuditBatch()` - Starts audit batch
  - `sendAuditReport()` - Triggers email report
  - `getBatchJobStatus(Id jobId)` - Checks batch status
  - `scheduleMonthlyAudit()` - Creates monthly CronTrigger
  - `unscheduleMonthlyAudit()` - Aborts scheduled job
  - `isAuditScheduled()` - Checks for existing scheduled jobs
  - `getAllFeatures()` - Returns feature toggle list
  - `getConfiguration()` - Returns system configuration summary
- **Inner Classes:** ControlCenterData, FeatureInfo, FeatureCategory, ConfigCount
- **Dependencies:** UserAuditSnapshotBatch, AuditSummaryEmailService, AuditFeatureService, FindingAssignmentService, OverdueRemediationService

#### AuditFeatureService.cls
- **Type:** Service class (static methods, cached)
- **Purpose:** Feature toggle service using Audit_Feature_Setting__mdt. Provides boolean checks for 17 features.
- **Key Methods:**
  - `isEnabled(String featureName)` - Returns whether feature is enabled
  - `ensureCacheLoaded()` - One SOQL per transaction, caches all CMT records
- **Feature Constants (17):**
  - USER_SNAPSHOT, TERMINATED_USER, PROFILE_CHANGE, ROLE_CHANGE, NEW_USER
  - PERMISSION_SET_CHANGE, PRIVILEGED_USER, SETUP_AUDIT_TRAIL, LOGIN_ANOMALY
  - SOD_VALIDATION, ACCESS_REVIEW, SIGN_OFF_ENFORCEMENT, SNAPSHOT_DUPLICATE_DETECTION
  - UNAUTHORIZED_DEPLOY, CM_TICKET, FINDING_ASSIGNMENT_SLA, OVERDUE_REMEDIATION_REMINDERS
- **Dependencies:** Audit_Feature_Setting__mdt
- **Pattern:** Lazy-loaded static Map<String, Audit_Feature_Setting__mdt> cache

#### BaselineSnapshotService.cls
- **Type:** Service class (@AuraEnabled methods)
- **Purpose:** Manages baseline audit snapshots. Mark/clear baseline, compare current vs baseline to detect access drift.
- **Key Methods:**
  - `markAsBaseline(Id auditRunId)` - Unmarks existing baselines, marks specified run as baseline. Only completed runs allowed.
  - `getBaselineRunId()` - (cacheable) Returns current baseline run ID
  - `compareToBaseline(Id currentRunId)` - Compares snapshots: finds users added/removed/modified across Profile, Role, Permission Sets, Active Status
  - `clearBaseline()` - Removes baseline marking
- **Inner Classes:** SnapshotDifference, BaselineComparisonResult
- **Dependencies:** Audit_Run__c (Is_Baseline__c field), User_Audit_Snapshot__c
- **Security:** WITH USER_MODE, Security.stripInaccessible(AccessType.UPDATABLE)

#### BaselineComparisonController.cls
- **Type:** LWC Controller (@AuraEnabled methods)
- **Purpose:** Thin wrapper around BaselineSnapshotService for the baselineComparison LWC.
- **Key Methods:**
  - `getBaselineData()` - Returns baseline run info + all completed runs
  - `setBaseline(Id auditRunId)` - Delegates to BaselineSnapshotService.markAsBaseline
  - `clearBaseline()` - Delegates to BaselineSnapshotService.clearBaseline
  - `compareWithBaseline(Id currentRunId)` - Delegates to BaselineSnapshotService.compareToBaseline
- **Dependencies:** BaselineSnapshotService

#### ProfileChangeDetector.cls
- **Type:** Service class (static methods)
- **Purpose:** Detects Profile, Role, Permission Set changes between consecutive audit runs. Also detects new users and deactivated users.
- **Key Methods:**
  - `detectChanges(Id currentAuditRunId)` - Main detection method. Finds previous run, compares all snapshots. Creates findings for: Profile Changed, Role Changed, Permission Set Changed, New User, Deactivated User
  - `compareRuns(Id currentRunId, Id previousRunId)` - Direct comparison between two specified runs
  - `getSnapshotsByUserId(Id auditRunId)` - (private) Queries snapshots keyed by User_Id__c
  - `hasChanged(String oldValue, String newValue)` - (private) Null-safe string comparison
- **Finding Types Created:** Profile Changed (Warning), Role Changed (Warning), Permission Set Changed (Warning), New User (Info), Deactivated User (Info/Resolved)
- **Dependencies:** User_Audit_Snapshot__c, Audit_Finding__c, Audit_Run__c
- **Pattern:** Creates deactivated user snapshots in bulk, then re-queries for formula field values

#### TerminationCrossCheckService.cls
- **Type:** Service class (static methods)
- **Purpose:** Compares Termination_Record__c against User_Audit_Snapshot__c to find terminated employees still active in Salesforce.
- **Key Methods:**
  - `runCrossCheck(Id auditRunId)` - Main cross-check. Queries termination records, compares against snapshots by email match
  - `checkEmails(List<String> emails)` - Checks specific emails against active users
  - `bulkCheck(Id auditRunId, List<Termination_Record__c> records)` - Bulk check from import
  - `getQueryLocatorForBatch(Id auditRunId)` - Returns QueryLocator for batch processing
- **Finding Type Created:** "Terminated User Active" (Critical)
- **Dependencies:** Termination_Record__c, User_Audit_Snapshot__c, Audit_Finding__c
- **Limit:** MAX_RECORDS = 5000

#### AccessReviewService.cls
- **Type:** Service class (static methods, @InvocableMethod)
- **Purpose:** Quarterly access review workflow. Marks snapshots as "Pending Review", tracks review status, sends reminders.
- **Key Methods:**
  - `initiateQuarterlyReview(Id auditRunId)` - Marks all snapshots as "Pending Review" with due date (90 days)
  - `markAsReviewed(List<Id> snapshotIds, String notes)` - Updates snapshots to "Reviewed"
  - `processOverdueReviews()` - Finds overdue reviews, creates "Overdue Access Review" findings
  - `sendReminderEmails()` - Sends email reminders for pending reviews
  - `getPendingReviews(Id auditRunId)` - Returns list of pending review snapshots
  - `getReviewStatistics(Id auditRunId)` - Returns review progress stats
- **@InvocableMethod:** `initiateReviewFromFlow(List<Id>)` - Flow integration for initiating reviews
- **Dependencies:** User_Audit_Snapshot__c (Review_Status__c, Next_Review_Due__c), Audit_Finding__c

#### AuditReportService.cls
- **Type:** Service class (static methods)
- **Purpose:** Report aggregation, CSV export, and audit run finalization.
- **Key Methods:**
  - `finalizeAuditRun(Id auditRunId)` - Aggregates finding counts by severity, sets status to "Completed", updates Completed_Date__c
  - `getAggregatedFindings(Id auditRunId)` - Returns AggregateResult[] grouped by Finding_Type__c + Severity__c
  - `getExportableFindings(Id auditRunId, String severity)` - Returns findings list for export
  - `generateCsvExport(Id auditRunId, String severity)` - Builds CSV string with headers
  - `getAuditRunSummary(Id auditRunId)` - Returns full summary with all counts
  - `bulkUpdateResolution(List<Id> findingIds, String status, String notes)` - Bulk update findings
  - `compareAuditRuns(Id runId1, Id runId2)` - Side-by-side comparison of two runs
- **Dependencies:** Audit_Run__c, Audit_Finding__c

#### LoginHistoryService.cls
- **Type:** Service class (static methods)
- **Purpose:** Login anomaly detection. Analyzes LoginHistory standard object for suspicious patterns.
- **Key Methods:**
  - `analyzeLoginHistory(Id auditRunId)` - Main analysis. Detects: failed logins (>5 attempts), unusual login times (outside 6AM-8PM and weekends), new IP locations
  - `isUnusualLoginTime(DateTime loginTime)` - (private) Checks if login occurred during off-hours
  - `getAnomaliesByType(Id auditRunId)` - Returns anomalies grouped by type
  - `getTopUsersWithAnomalies(Id auditRunId, Integer topN)` - Returns users with most anomalies
- **Records Created:** Login_Anomaly__c
- **Dependencies:** LoginHistory (standard), Login_Anomaly__c, Audit_Run__c

#### SegregationOfDutiesService.cls
- **Type:** Service class (static methods)
- **Purpose:** Validates users against SoD rules defined in Segregation_Rule__mdt. Checks for toxic permission combinations.
- **Key Methods:**
  - `validateSegregation(Id auditRunId)` - Main validation. Loads active rules, checks all users' permission sets against rule pairs
  - `checkUserViolations(Id userId)` - Checks single user
  - `getAllRules()` - Returns all Segregation_Rule__mdt records
- **Finding Type Created:** "Segregation of Duties Violation" (Critical)
- **Dependencies:** Segregation_Rule__mdt, PermissionSetAssignment, Audit_Finding__c, User_Audit_Snapshot__c

#### SetupAuditTrailService.cls
- **Type:** Service class (static methods)
- **Purpose:** Captures security-relevant Setup Audit Trail changes into Setup_Change_Log__c records.
- **Key Methods:**
  - `captureSetupChanges(Id auditRunId)` - Queries SetupAuditTrail for security-relevant sections (Permission, Profile, User, Role), creates Setup_Change_Log__c records
  - `getDeploymentRecords(Id auditRunId)` - Returns deployment-related setup changes
  - `isDeploymentAction(String action)` - Checks if action is a deployment
  - `getChangesBySection(Id auditRunId, String section)` - Filters changes by section
- **Dependencies:** SetupAuditTrail (standard), Setup_Change_Log__c

#### RiskScoringService.cls
- **Type:** Service class (static methods)
- **Purpose:** Risk scoring configuration and categorization.
- **Key Methods:**
  - `getRiskSummary(Id auditRunId)` - Returns risk breakdown (High/Medium/Low counts)
  - `getRiskConfig()` - Returns threshold configuration
  - `categorize(Decimal score)` - Categorizes score: High>=70, Medium>=40, Low<40
- **Dependencies:** Audit_Finding__c (Risk_Score__c field)

#### AuditSummaryPdfGenerator.cls
- **Type:** Service class (static methods)
- **Purpose:** Generates PDF audit summary reports using HTML-to-PDF (Blob.toPdf) and Visualforce page.
- **Key Methods:**
  - `generatePdf(Id auditRunId)` - Generates PDF using Visualforce page, returns ContentVersion record
  - `generatePdfBasic(Id auditRunId)` - Alternative using Blob.toPdf() with inline HTML
  - `gatherAuditData(Id auditRunId)` - (private) Collects all data for PDF
  - `buildHtmlDocument(...)` - (private) Builds HTML string for Blob.toPdf()
- **Dependencies:** ContentVersion, ContentDocumentLink, Audit_Run__c, Audit_Finding__c, AuditSummaryPdf (VF page)

#### AuditSummaryPdfController.cls
- **Type:** Visualforce Controller
- **Purpose:** Controller for AuditSummaryPdf Visualforce page. Provides data for professional PDF rendering.
- **Key Properties:**
  - `auditRun` - Main Audit_Run__c record
  - `newUsersCount`, `deactivatedCount`, `profileChangesCount`, `openFindingsCount` - Computed metrics
  - `preparedByName`, `reviewedByName` - User lookups
  - `findings` - Critical and Warning findings (LIMIT 50)
- **Key Methods:**
  - Constructor - Loads data from URL parameter `id`
  - `generatePdfBlob(Id auditRunId)` - Static method for generating PDF blob from VF page
  - `loadMetrics()` - (private) 4 SOQL queries for counts
  - `loadFindings()` - (private) Queries Critical/Warning findings
- **Security:** Id.valueOf() validation to prevent XSS, WITH USER_MODE

#### AuditSummaryEmailService.cls
- **Type:** Service class (static methods)
- **Purpose:** Sends PDF audit summary reports via email to configured recipients (Audit_Summary_Recipient__mdt).
- **Key Methods:**
  - `sendLatestAuditSummary()` - Sends latest completed run summary
  - `sendAuditSummary(Id auditRunId)` - Sends summary for specific run
  - `sendAuditSummaryToTeam()` - Sends to all active CMT recipients
  - `sendAuditSummaryToEmails(Id auditRunId, List<String> emails)` - Sends to specific emails
- **Pattern:** Creates ContentVersion -> ContentDocumentLink -> ContentDistribution (for public download URL)
- **Dependencies:** AuditSummaryPdfController.generatePdfBlob(), Audit_Summary_Recipient__mdt, ContentVersion, ContentDocumentLink, ContentDistribution

#### QuarterlySignOffService.cls
- **Type:** Service class (static methods)
- **Purpose:** Enforces sign-off on previous audit run before allowing new runs.
- **Key Methods:**
  - `validateBeforeNewRun()` - Returns validation result (pass/fail with message)
  - `enforceSignOffOrThrow()` - Throws AuraHandledException if validation fails
  - `isPreviousRunSignedOff()` - Checks if most recent completed run has Sign_Off_Date__c
- **Dependencies:** Audit_Run__c (Sign_Off_Date__c, Reviewed_By__c), AuditFeatureService

#### QuarterlyReviewController.cls
- **Type:** LWC Controller (@AuraEnabled methods)
- **Purpose:** Controller for quarterlyReview LWC. Manages review workflow and sign-off.
- **Key Methods:**
  - `getAuditRuns()` - Returns list of completed audit runs
  - `getReviewData(Id auditRunId)` - Returns ReviewData with review stats
  - `initiateReview(Id auditRunId)` - Starts quarterly review process
  - `submitReview(Id snapshotId, String notes, Boolean approved)` - Records individual review
  - `signOffAuditRun(Id auditRunId)` - Signs off run (sets Reviewed_By__c, Sign_Off_Date__c)
- **Inner Classes:** ReviewData, ReviewSnapshot
- **Dependencies:** AccessReviewService, Audit_Run__c, User_Audit_Snapshot__c

#### FindingAssignmentService.cls
- **Type:** Service class + Schedulable
- **Purpose:** SLA tracking and finding assignment. Calculates SLA status based on severity due dates.
- **Key Methods:**
  - `recalculateSlaStatuses()` - Recalculates all open finding SLA statuses
  - `calculateSlaStatus(Audit_Finding__c finding)` - Returns: On Track / At Risk / Breached
  - `getSlaSummary(Id auditRunId)` - Returns SLA breakdown
  - `assignFinding(Id findingId, Id assigneeId)` - Assigns finding to user
  - `assignFindings(List<Id> findingIds, Id assigneeId)` - Bulk assign
  - `scheduleDaily()` - Schedules daily SLA recalculation
- **SLA Thresholds:** Critical=7 days, Warning=30 days, Info=90 days
- **Dependencies:** Audit_Finding__c (Remediation_Due_Date__c, SLA_Status__c, Assigned_To__c)

#### OverdueRemediationService.cls
- **Type:** Service class + Schedulable
- **Purpose:** Sends email reminders for overdue findings.
- **Key Methods:**
  - `sendOverdueReminders()` - Finds overdue assigned findings, sends emails to assignees
  - `calculateDueDate(String severity)` - Returns due date based on severity SLA
  - `scheduleDaily()` - Schedules daily reminder check
- **SLA:** Critical=7d, Warning=30d, Info=90d
- **Dependencies:** Audit_Finding__c, Messaging.SingleEmailMessage

#### CMTicketValidationService.cls
- **Type:** Service class (static methods)
- **Purpose:** Validates deployments against Change_Request__c (change management tickets).
- **Key Methods:**
  - `validateDeployments(Id auditRunId)` - Matches setup changes to change tickets. Creates findings for: "Deployment Without Change Ticket", "Deployment Outside Window", "Unauthorized Deployer"
  - `findMatchingTicket(String deployerName, DateTime deployDateTime)` - Finds matching Change_Request__c
  - `getValidationSummary(Id auditRunId)` - Returns validation stats
- **Dependencies:** Setup_Change_Log__c, Change_Request__c, Approved_Deployer__mdt, Audit_Finding__c

#### DeploymentAuthorizationService.cls
- **Type:** Service class (static methods)
- **Purpose:** Validates deployers against Approved_Deployer__mdt whitelist.
- **Key Methods:**
  - `validateDeployments(Id auditRunId)` - Checks deployment setup changes against approved deployers
  - `isAuthorizedDeployer(String username)` - Checks if username is in approved list
  - `getDeploymentSummary(Id auditRunId)` - Returns deployment authorization stats
- **Finding Type Created:** "Unauthorized Deployment" (Critical)
- **Dependencies:** Approved_Deployer__mdt, Setup_Change_Log__c, Audit_Finding__c

#### AuditFindingCounter.cls
- **Type:** Invocable Apex (@InvocableMethod)
- **Purpose:** Called from Flow (Audit_Run_Status_Update). Counts findings by severity and updates Audit_Run__c totals.
- **Key Methods:**
  - `countFindings(List<Id> auditRunIds)` - Counts findings by severity, updates Finding_Count_Critical__c, Finding_Count_Warning__c, Finding_Count_Info__c, Finding_Count_Total__c
- **Dependencies:** Audit_Run__c, Audit_Finding__c

#### UserDeactivationHandler.cls
- **Type:** Trigger handler (static methods)
- **Purpose:** Handles User deactivation events. Validates Jira ticket requirement, enqueues async processing.
- **Key Methods:**
  - `handleDeactivations(List<User> newUsers, Map<Id, User> oldMap)` - Detects IsActive changes from true to false
  - `setDeactivationContext(String reason, String jiraTicket)` - Sets thread-local deactivation context
  - `clearDeactivationContext()` - Clears context
- **Inner Class:** DeactivatedUserInfo - Holds user deactivation data
- **Pattern:** Uses static variables for cross-trigger context passing
- **Dependencies:** UserDeactivationQueueable, Audit_Settings__c (Bypass_Jira_Ticket_Validation__c)

#### SnapshotDuplicateDetectionService.cls
- **Type:** Service class (static methods)
- **Purpose:** Prevents duplicate snapshots per user per run.
- **Key Methods:**
  - `getExistingSnapshotUserIds(Id auditRunId)` - Returns Set<String> of User_Id__c already in run
  - `filterDuplicates(Id auditRunId, List<User_Audit_Snapshot__c> snapshots)` - Removes duplicates from list
  - `findDuplicatesInRun(Id auditRunId)` - Finds duplicate snapshot records
  - `removeDuplicatesFromRun(Id auditRunId)` - Deletes duplicate snapshots (keeps first)
- **Dependencies:** User_Audit_Snapshot__c

#### AuditHistoryService.cls
- **Type:** Service class (static methods)
- **Purpose:** Queries field history tracking for audit objects.
- **Key Methods:**
  - `getAuditRunHistory(Id auditRunId)` - Returns Audit_Run__c field history
  - `getAuditFindingHistory(Id findingId)` - Returns Audit_Finding__c field history
  - `getTerminationHistory(Id terminationId)` - Returns Termination_Record__c field history
  - `getRecentAuditChanges(Integer daysBack)` - Returns recent changes across all tracked objects
- **Dependencies:** Audit_Run__History, Audit_Finding__History, Termination_Record__History (field history tracking)

#### AuditConfigurationController.cls
- **Type:** Visualforce Controller
- **Purpose:** Configuration page controller. Loads all custom metadata records for display.
- **Key Properties:** featureSettings, segregationRules, summaryRecipients, approvedDeployers
- **Dependencies:** All 4 custom metadata types

#### PermissionSetViewerController.cls
- **Type:** LWC Controller (@AuraEnabled)
- **Purpose:** Resolves Permission Set API names to Salesforce IDs for navigation.
- **Key Methods:**
  - `getPermissionSetIds(List<String> permSetNames)` - Returns Map<String, Id> of name -> ID
- **Dependencies:** PermissionSet (standard object)

#### PostInstallScript.cls
- **Type:** InstallHandler (implements InstallHandler)
- **Purpose:** Runs on package install. Creates default Audit_Settings__c, assigns Audit_Administrator perm set, sends welcome email.
- **Key Methods:**
  - `onInstall(InstallContext context)` - Package install handler
- **Dependencies:** Audit_Settings__c, Audit_Administrator (permission set)

#### PackageUninstallHandler.cls
- **Type:** UninstallHandler (implements UninstallHandler)
- **Purpose:** Runs on package uninstall. Aborts scheduled audit jobs, sends farewell email.
- **Key Methods:**
  - `onUninstall(UninstallContext context)` - Package uninstall handler
- **Dependencies:** CronTrigger (aborts scheduled jobs)

#### AuditSummaryScheduler.cls
- **Type:** Schedulable
- **Purpose:** Schedules monthly audit summary email sends.
- **Key Methods:**
  - `execute(SchedulableContext sc)` - Calls AuditSummaryEmailService.sendLatestAuditSummary()
  - `scheduleMonthly()` - Cron: 0 0 6 1 * ? (6 AM on 1st of each month)
  - `unschedule()` - Aborts scheduled job
- **Dependencies:** AuditSummaryEmailService

### 1.2 Queueable Classes

#### TerminationCrossCheckQueueable.cls
- **Type:** Queueable
- **Purpose:** Chained from UserAuditSnapshotBatch.finish(). Runs termination cross-check, then chains to ProfileChangeDetectorQueueable.
- **Key Methods:**
  - `execute(QueueableContext context)` - Calls TerminationCrossCheckService.runCrossCheck(), enqueues ProfileChangeDetectorQueueable
- **Chain Position:** 1st in post-batch chain
- **Dependencies:** TerminationCrossCheckService, ProfileChangeDetectorQueueable

#### ProfileChangeDetectorQueueable.cls
- **Type:** Queueable
- **Purpose:** Chained from TerminationCrossCheckQueueable. Runs profile change detection, then finalizes audit run.
- **Key Methods:**
  - `execute(QueueableContext context)` - Calls ProfileChangeDetector.detectChanges(), then AuditReportService.finalizeAuditRun()
- **Chain Position:** 2nd (final) in post-batch chain
- **Dependencies:** ProfileChangeDetector, AuditReportService

#### UserDeactivationQueueable.cls
- **Type:** Queueable
- **Purpose:** Processes user deactivations asynchronously (avoids MIXED_DML_OPERATION). Creates on-demand audit run, snapshots, and findings.
- **Key Methods:**
  - `execute(QueueableContext context)` - Creates/finds on-demand Audit_Run__c for today, creates snapshots and findings
  - `getOrCreateOnDemandAuditRun()` - (private) Gets existing or creates new on-demand run (identified by Notes__c = "Real-Time Deactivation Detection")
  - `updateAuditRunTotals(Id auditRunId)` - (private) Recalculates finding counts via AggregateResult
- **Dependencies:** UserDeactivationHandler.DeactivatedUserInfo, Audit_Run__c, User_Audit_Snapshot__c, Audit_Finding__c

### 1.3 Class Dependency Graph (Execution Chain)

```
UserAuditSnapshotBatch (Batch)
  |-- start(): Queries Users
  |-- execute(): Creates snapshots, checks features via AuditFeatureService
  |       |-- SnapshotDuplicateDetectionService.filterDuplicates()
  |       |-- QuarterlySignOffService.validateBeforeNewRun()
  |-- finish():
        |-- SetupAuditTrailService.captureSetupChanges()
        |-- LoginHistoryService.analyzeLoginHistory()
        |-- SegregationOfDutiesService.validateSegregation()
        |-- System.enqueueJob(TerminationCrossCheckQueueable)
              |-- TerminationCrossCheckService.runCrossCheck()
              |-- System.enqueueJob(ProfileChangeDetectorQueueable)
                    |-- ProfileChangeDetector.detectChanges()
                    |-- AuditReportService.finalizeAuditRun()
                          |-- Sets Status__c = 'Completed'
                          |-- (Triggers Flow: Audit_Run_Status_Update)
                                |-- AuditFindingCounter.countFindings()
```

**Real-Time Deactivation Chain:**
```
User Trigger (IsActive: true -> false)
  |-- UserDeactivationHandler.handleDeactivations()
        |-- System.enqueueJob(UserDeactivationQueueable)
              |-- getOrCreateOnDemandAuditRun()
              |-- Creates User_Audit_Snapshot__c
              |-- Creates Audit_Finding__c
              |-- updateAuditRunTotals()
```

---

## 2. Custom Objects

### 2.1 Audit_Run__c
**Purpose:** Central audit execution record. One per audit run.
**Relationships:** Parent of User_Audit_Snapshot__c, Audit_Finding__c, Login_Anomaly__c, Setup_Change_Log__c

| Field API Name | Type | Purpose |
|---|---|---|
| Run_Date__c | DateTime | When the audit ran |
| Period_Start__c | Date | Start of audit period |
| Period_End__c | Date | End of audit period |
| Status__c | Picklist | Running, Processing, Completed |
| Total_Users__c | Number | Total users snapshotted |
| Total_Findings__c | Number | Total findings count |
| Critical_Findings__c | Number | Critical finding count |
| Warning_Findings__c | Number | Warning finding count |
| Info_Findings__c | Number | Info finding count |
| Finding_Count_Critical__c | Number | Flow-calculated critical count |
| Finding_Count_Warning__c | Number | Flow-calculated warning count |
| Finding_Count_Info__c | Number | Flow-calculated info count |
| Finding_Count_Total__c | Number | Flow-calculated total count |
| Is_Latest__c | Checkbox | Marks most recent run |
| Is_Baseline__c | Checkbox | Marks baseline reference run |
| Completed_Date__c | DateTime | When run completed |
| Failed_Login_Count__c | Number | Failed login attempts detected |
| Login_Anomaly_Count__c | Number | Login anomalies detected |
| Notes__c | Long Text | Run notes / on-demand run identifier |
| Prepared_By__c | Lookup(User) | User who prepared the audit |
| Reviewed_By__c | Lookup(User) | User who reviewed/signed off |
| Sign_Off_Date__c | DateTime | Quarterly sign-off date |

**Field History Tracking:** Enabled (Audit_Run__History)

### 2.2 User_Audit_Snapshot__c
**Purpose:** Point-in-time capture of a user's access profile. One per user per audit run.
**Relationships:** Child of Audit_Run__c. Parent of Audit_Finding__c.

| Field API Name | Type | Purpose |
|---|---|---|
| Audit_Run__c | Lookup(Audit_Run__c) | Parent audit run |
| User_Id__c | Text(18) | Salesforce User ID |
| Username__c | Text(255) | Username |
| Email__c | Email | User's email |
| Full_Name__c | Text(255) | First + Last name |
| Is_Active__c | Checkbox | User active status at snapshot time |
| Profile_Name__c | Text(255) | Profile name |
| Role_Name__c | Text(255) | Role name |
| Permission_Sets__c | Long Text Area | Semicolon-delimited permission set names |
| Is_Privileged__c | Checkbox | Whether user has elevated access |
| Is_Latest_Run__c | Checkbox | Whether this is from the latest run |
| Last_Login__c | DateTime | Last successful login date |
| User_Created_Date__c | Date | When the user account was created |
| Snapshot_Date__c | Date | Date of the snapshot |
| Snapshot_Month__c | Formula(Text) | YYYY-MM derived from Snapshot_Date__c |
| Snapshot_Unique_Key__c | Text | Unique key for duplicate detection |
| Deactivated_By__c | Text(18) | ID of user who deactivated |
| Deactivation_Date__c | Date | When deactivated |
| Deactivation_Reason__c | Text(255) | Reason for deactivation |
| Jira_Ticket__c | Text(50) | Associated Jira ticket |
| Review_Status__c | Picklist | Pending Review, Reviewed, Overdue |
| Review_Notes__c | Long Text | Reviewer notes |
| Reviewed_By__c | Lookup(User) | Who reviewed this snapshot |
| Last_Access_Review__c | Date | Last review date |
| Next_Review_Due__c | Date | When next review is due |

### 2.3 Audit_Finding__c
**Purpose:** Individual compliance finding. One per detected issue per user per run.
**Relationships:** Child of Audit_Run__c, User_Audit_Snapshot__c, Termination_Record__c.

| Field API Name | Type | Purpose |
|---|---|---|
| Audit_Run__c | Lookup(Audit_Run__c) | Parent audit run |
| User_Snapshot__c | Lookup(User_Audit_Snapshot__c) | Related snapshot |
| Termination_Record__c | Lookup(Termination_Record__c) | Related termination (if applicable) |
| Finding_Type__c | Picklist | Type of finding (see list below) |
| Severity__c | Picklist | Critical, Warning, Info |
| Resolution_Status__c | Picklist | Open, Under Review, Resolved, Accepted |
| User_Email__c | Email | Affected user's email |
| User_Full_Name__c | Text | Affected user's name |
| Current_Value__c | Long Text | Current state |
| Previous_Value__c | Long Text | Previous state |
| Audit_Period__c | Text | YYYY-MM audit period |
| Remediation_Due_Date__c | Date | SLA due date |
| Remediation_Guidance__c | Long Text | Guidance for resolution |
| Resolution_Notes__c | Long Text | Notes on resolution |
| Resolved_By__c | Lookup(User) | Who resolved the finding |
| Resolved_Date__c | DateTime | When resolved |
| Risk_Category__c | Text | High, Medium, Low |
| Risk_Score__c | Number | Calculated risk score |
| SLA_Status__c | Picklist | On Track, At Risk, Breached |
| Assigned_To__c | Lookup(User) | Assigned remediation owner |
| Assigned_Date__c | Date | When assigned |
| Jira_Ticket__c | Text(50) | Associated Jira ticket |
| Deactivation_Reason__c | Text(255) | Deactivation reason (for deactivation findings) |

**Finding Types (14):**
1. Terminated User Active (Critical)
2. Profile Changed (Warning)
3. Role Changed (Warning)
4. Permission Set Changed (Warning)
5. New User (Info)
6. Deactivated User (Info)
7. Privileged Access Granted (Warning)
8. Overdue Access Review (Warning)
9. Segregation of Duties Violation (Critical)
10. Unauthorized Deployment (Critical)
11. Deployment Without Change Ticket (Warning)
12. Deployment Outside Window (Warning)
13. Unauthorized Deployer (Critical)
14. Access Flagged for Removal (Warning)

**Field History Tracking:** Enabled (Audit_Finding__History)

### 2.4 Termination_Record__c
**Purpose:** HR termination data imported via CSV for cross-checking.
**Relationships:** Parent of Audit_Finding__c.

| Field API Name | Type | Purpose |
|---|---|---|
| Employee_Name__c | Text | Employee full name |
| Email__c | Email | Employee email (key for matching) |
| Termination_Date__c | Date | Date of termination |
| Termination_Type__c | Picklist | Employee, Contractor |
| Department__c | Text | Department |
| Manager__c | Text | Manager name |
| Job_Title__c | Text | Job title |
| Import_Batch__c | Text | Batch identifier for CSV import |
| Import_Date__c | Date | When imported |
| SF_User_Status__c | Text | Salesforce user status at check time |
| Verified__c | Checkbox | Whether verified |
| Verified_By__c | Lookup(User) | Who verified |
| Verified_Date__c | Date | When verified |

**Field History Tracking:** Enabled (Termination_Record__History)

### 2.5 Change_Request__c
**Purpose:** Change management tickets for deployment validation.

| Field API Name | Type | Purpose |
|---|---|---|
| Ticket_Number__c | Text | CM ticket number |
| Description__c | Long Text | Change description |
| Components__c | Long Text | Affected components |
| Status__c | Picklist | Status of the change request |
| Risk_Level__c | Picklist | Risk level |
| Requested_By__c | Text | Requester |
| Approved_By__c | Text | Approver |
| Approved_Date__c | Date | Approval date |
| Deployer__c | Text | Designated deployer |
| Implementation_Date__c | Date | Planned implementation date |
| Implementation_Window_Start__c | DateTime | Window start |
| Implementation_Window_End__c | DateTime | Window end |

### 2.6 Login_Anomaly__c
**Purpose:** Records login security anomalies detected by LoginHistoryService.
**Relationships:** Child of Audit_Run__c. Lookup to User.

| Field API Name | Type | Purpose |
|---|---|---|
| Audit_Run__c | Lookup(Audit_Run__c) | Parent audit run |
| User__c | Lookup(User) | Affected user |
| Anomaly_Type__c | Picklist | Failed Login Attempts, Unusual Login Time, New Login Location, Multiple Concurrent Sessions |
| Severity__c | Picklist | Critical, Warning, Info |
| Login_Time__c | DateTime | When the login occurred |
| Login_Status__c | Text | Login status (Success, Invalid Password, etc.) |
| Source_IP__c | Text | Source IP address |
| Browser__c | Text | Browser info |
| Platform__c | Text | OS platform |
| Details__c | Long Text | Additional details |

### 2.7 Setup_Change_Log__c
**Purpose:** Captured Setup Audit Trail entries for security-relevant changes.
**Relationships:** Child of Audit_Run__c.

| Field API Name | Type | Purpose |
|---|---|---|
| Audit_Run__c | Lookup(Audit_Run__c) | Parent audit run |
| Action__c | Text | Action performed |
| Section__c | Text | Setup section (Permission Sets, Users, Profiles, Role Hierarchy) |
| Created_By_User__c | Text(18) | User ID who made the change |
| Created_Date_Time__c | DateTime | When the change occurred |
| Display__c | Long Text | Display text from SetupAuditTrail |

### 2.8 Audit_Settings__c (Hierarchy Custom Setting)
**Purpose:** User-level configuration overrides.

| Field API Name | Type | Purpose |
|---|---|---|
| Bypass_Jira_Ticket_Validation__c | Checkbox | Bypasses Jira ticket requirement for deactivations |

---

## 3. LWC Components

### 3.1 auditControlCenter
- **Purpose:** Admin console for managing the audit system
- **Targets:** AppPage, HomePage, Tab
- **Functionality:**
  - System health dashboard
  - Feature toggle management (17 features)
  - Batch job execution and status monitoring
  - Monthly scheduling (schedule/unschedule)
  - Email report sending
  - Configuration viewer (feature settings, segregation rules, recipients, deployers)
- **Apex Calls:** AuditControlCenterController.getControlCenterData, runAuditBatch, sendAuditReport, getBatchJobStatus, scheduleMonthlyAudit, unscheduleMonthlyAudit, isAuditScheduled, getAllFeatures, getConfiguration

### 3.2 auditDashboard
- **Purpose:** Main dashboard showing audit summary and findings
- **Targets:** AppPage, HomePage, Tab
- **Functionality:**
  - Summary cards (total users, findings by severity)
  - Trend charts (finding counts over time)
  - Finding type breakdown
  - Recent audit runs list
  - Run audit now button
  - Termination CSV import
  - Findings list with filtering, sorting, pagination
  - Bulk resolve findings
  - CSV export
- **Apex Calls:** AuditController.getAuditSummary, runAuditNow, importTerminations, getFindings, resolveFindings, updateFinding, exportFindings, getAuditRuns, getDistinctFindingTypes, getBatchJobStatus

### 3.3 baselineComparison
- **Purpose:** Baseline comparison UI for access drift detection
- **Targets:** Tab, AppPage, RecordPage
- **Functionality:**
  - View current baseline run
  - Set/clear baseline
  - Select run to compare against baseline
  - View comparison results: users added, removed, modified
  - Detailed difference table with field-level changes
- **Apex Calls:** BaselineComparisonController.getBaselineData, setBaseline, clearBaseline, compareWithBaseline

### 3.4 findingsReview
- **Purpose:** Review and resolve audit findings
- **Targets:** AppPage, Tab, RecordPage (Audit_Run__c), HomePage
- **Functionality:**
  - Filter by severity, type, status, search term
  - Sortable columns
  - Pagination
  - Inline editing (status, notes)
  - Bulk selection and resolve
  - Finding detail view
  - Export to CSV
- **Apex Calls:** AuditController.getFindings, resolveFindings, updateFinding, exportFindings, getDistinctFindingTypes

### 3.5 permissionSetViewer
- **Purpose:** Display permission set badges on snapshot records
- **Target:** RecordPage (User_Audit_Snapshot__c)
- **Functionality:**
  - Parses semicolon-delimited Permission_Sets__c field
  - Displays each permission set as a clickable badge
  - Links to permission set detail page
- **Apex Calls:** PermissionSetViewerController.getPermissionSetIds

### 3.6 quarterlyReview
- **Purpose:** SOX/IPE quarterly access review and sign-off workflow
- **Targets:** AppPage, HomePage, Tab
- **Functionality:**
  - Select audit run for review
  - View review statistics (pending, reviewed, overdue)
  - Initiate quarterly review (marks all snapshots as "Pending Review")
  - Individual snapshot review (approve/flag with notes)
  - Sign-off audit run (Reviewed_By, Sign_Off_Date)
  - Progress tracking
- **Apex Calls:** QuarterlyReviewController.getAuditRuns, getReviewData, initiateReview, submitReview, signOffAuditRun

### 3.7 terminationImporter
- **Purpose:** CSV upload for HR termination data
- **Targets:** AppPage, Tab, HomePage
- **Functionality:**
  - File upload (CSV format)
  - Preview parsed data before import
  - Import with duplicate detection
  - Results display (imported count, duplicates skipped, errors)
  - Template download
- **Apex Calls:** AuditController.importTerminations

---

## 4. Flows

### 4.1 Set_Latest_Flag_On_New_Audit_Run
- **Type:** Record-Triggered Flow (Before Insert)
- **Object:** Audit_Run__c
- **Trigger:** Before Insert
- **Logic:** Sets Is_Latest__c = true on the new record
- **Bypass:** Respects Bypass_All_Flows custom permission

### 4.2 Set_Latest_Audit_Run
- **Type:** Record-Triggered Flow (After Insert)
- **Object:** Audit_Run__c
- **Trigger:** After Insert
- **Logic:** Clears Is_Latest__c on all previous Audit_Run__c records (WHERE Id != triggering record AND Is_Latest__c = true)
- **DML:** UPDATE Audit_Run__c (previous records)
- **Bypass:** Respects Bypass_All_Flows custom permission

### 4.3 Audit_Run_Status_Update
- **Type:** Record-Triggered Flow (After Save)
- **Object:** Audit_Run__c
- **Trigger:** After Save, when Status__c changes to 'Completed'
- **Logic:** Calls AuditFindingCounter invocable action to count findings by severity and update totals
- **Apex Action:** AuditFindingCounter.countFindings
- **Bypass:** Respects Bypass_All_Flows custom permission

### 4.4 Notify_Audit_Team
- **Type:** Record-Triggered Flow (After Save)
- **Object:** Audit_Run__c
- **Trigger:** After Save, when Status__c changes to 'Completed'
- **Logic:** Checks if Critical findings > 0. If so, sends email notification to audit team.
- **Email:** Send Email action
- **Bypass:** Respects Bypass_All_Flows custom permission

### 4.5 Set_Assignment_Date
- **Type:** Record-Triggered Flow (Before Save)
- **Object:** Audit_Finding__c
- **Trigger:** Before Save (Create and Update)
- **Logic:** When Assigned_To__c changes from null to a value, stamps Assigned_Date__c = TODAY()
- **Bypass:** Respects Bypass_All_Flows custom permission

### 4.6 Set_Remediation_Due_Date
- **Type:** Record-Triggered Flow (Before Save)
- **Object:** Audit_Finding__c
- **Trigger:** Before Save (Create only)
- **Logic:** Sets Remediation_Due_Date__c based on Severity__c:
  - Critical: TODAY() + 7 days
  - Warning: TODAY() + 30 days
  - Info: TODAY() + 90 days
- **Bypass:** Respects Bypass_All_Flows custom permission

### 4.7 Update_SLA_Status
- **Type:** Record-Triggered Flow (Before Save)
- **Object:** Audit_Finding__c
- **Trigger:** Before Save (Create and Update)
- **Logic:** Calculates SLA_Status__c based on Remediation_Due_Date__c vs TODAY():
  - If past due: "Breached"
  - If within 3 days of due date: "At Risk"
  - Otherwise: "On Track"
  - If Resolution_Status__c = 'Resolved': clears SLA_Status__c
- **Bypass:** Respects Bypass_All_Flows custom permission

### 4.8 Access_Review_Attestation
- **Type:** Screen Flow
- **Object:** N/A (standalone)
- **Purpose:** Manager attestation during quarterly access reviews
- **Screens:** Review user access details, approve/flag access, add notes
- **Logic:** Updates User_Audit_Snapshot__c Review_Status__c based on manager decision

---

## 5. Permission Sets

### 5.1 Audit_Administrator
- **Purpose:** Full administrative access to all audit features
- **Custom Permission:** Bypass_All_Flows (allows bypassing all record-triggered flows)
- **Object Access (Full CRUD):**
  - Audit_Run__c
  - Audit_Finding__c
  - User_Audit_Snapshot__c
  - Termination_Record__c
  - Change_Request__c
  - Login_Anomaly__c
  - Setup_Change_Log__c
- **All Fields:** Read/Edit on all custom fields for all objects
- **Apex Class Access:** All 35+ Apex classes
- **Tab Access:** All custom tabs
- **Visualforce Pages:** AuditSummaryPdf, AuditConfiguration

### 5.2 Audit_Full_Access
- **Purpose:** Full CRUD access without admin bypass capabilities
- **Custom Permission:** None (no Bypass_All_Flows)
- **Object Access (Full CRUD):** Same as Administrator
- **All Fields:** Read/Edit on all custom fields
- **Apex Class Access:** All Apex classes
- **Tab Access:** All custom tabs

### 5.3 Audit_Viewer
- **Purpose:** Read-only access for viewing audit data
- **Custom Permission:** None
- **Object Access:** Read only on all audit objects
- **Field Access:** Read only on all fields
- **Apex Class Access:** Read-focused classes only (AuditController, AuditControlCenterController, BaselineComparisonController, etc.)
- **Tab Access:** All custom tabs (read only)

---

## 6. Custom Metadata Types

### 6.1 Audit_Feature_Setting__mdt
**Purpose:** Feature toggles controlling which audit checks are enabled/disabled.
**Fields:** DeveloperName, Is_Enabled__c (Checkbox), Description__c (Text), Category__c (Text), Severity_If_Disabled__c (Text)

| Record | DeveloperName | Default Enabled | Category |
|---|---|---|---|
| User Snapshot Capture | User_Snapshot_Capture | true | Core |
| Terminated User Detection | Terminated_User_Detection | true | Core |
| Profile Change Detection | Profile_Change_Detection | true | Change Detection |
| Role Change Detection | Role_Change_Detection | true | Change Detection |
| New User Detection | New_User_Detection | true | Change Detection |
| Permission Set Change Detection | Permission_Set_Change_Detection | true | Change Detection |
| Privileged User Monitoring | Privileged_User_Monitoring | true | Security |
| Setup Audit Trail | Setup_Audit_Trail | true | Security |
| Login Anomaly Detection | Login_Anomaly_Detection | true | Security |
| Segregation of Duties | Segregation_Of_Duties | true | Compliance |
| Access Review Workflow | Access_Review_Workflow | true | Compliance |
| Quarterly Sign-Off Enforcement | Quarterly_Sign_Off_Enforcement | true | Compliance |
| Snapshot Duplicate Detection | Snapshot_Duplicate_Detection | true | Data Quality |
| Unauthorized Deployment | Unauthorized_Deployment | true | Deployment |
| CM Ticket Validation | CM_Ticket_Validation | true | Deployment |
| Finding Assignment SLA | Finding_Assignment_SLA | true | Workflow |
| Overdue Remediation Reminders | Overdue_Remediation_Reminders | true | Workflow |

### 6.2 Segregation_Rule__mdt
**Purpose:** Defines toxic permission set combinations that should not co-exist on a single user.
**Fields:** DeveloperName, Rule_Name__c, Permission_A__c, Permission_B__c, Severity__c, Description__c, Is_Active__c, Category__c, Remediation_Guidance__c

| Record | Permission A | Permission B | Severity |
|---|---|---|---|
| Author_Apex_And_Deploy | Author Apex | Deploy | Critical |
| Manage_Users_And_Modify_Data | Manage Users | Modify All Data | Critical |
| View_Setup_And_Modify_Data | View Setup | Modify All Data | Warning |
| Author_Apex_And_Modify_Data | Author Apex | Modify All Data | Critical |
| Manage_Users_And_View_All | Manage Users | View All Data | Warning |
| Customize_App_And_Deploy | Customize Application | Deploy | Warning |
| Manage_Profiles_And_Assign | Manage Profiles and Permission Sets | Assign Permission Sets | Warning |
| API_Enabled_And_Modify_Data | API Enabled | Modify All Data | Warning |
| Install_Packages_And_Deploy | Install Packaging | Deploy | Critical |
| Manage_Encryption_And_Export | Manage Encryption Keys | Export Data | Critical |

### 6.3 Approved_Deployer__mdt
**Purpose:** Whitelist of authorized deployers for deployment authorization checks.
**Fields:** DeveloperName, User_Id__c (Text), Username__c (Text), Is_Active__c (Checkbox), Deployment_Type__c (Text), Notes__c (Text)

### 6.4 Audit_Summary_Recipient__mdt
**Purpose:** Email recipients for automated audit summary reports.
**Fields:** DeveloperName, Email__c, Recipient_Name__c, Team__c, Is_Active__c

| Record | Team | Purpose |
|---|---|---|
| AuditTeam | Audit | Primary audit team recipients |
| ManagementTeam | Management | Management oversight |
| SecurityTeam | Security | Security team notifications |

---

## 7. Key Business Logic (End-to-End)

### 7.1 Full Audit Run Process

1. **Initiation:** User clicks "Run Audit Now" in auditDashboard LWC or via monthly schedule
2. **Pre-check:** QuarterlySignOffService.validateBeforeNewRun() checks if previous run is signed off (if feature enabled)
3. **Batch Start:** UserAuditSnapshotBatch.start() creates Audit_Run__c record, returns QueryLocator for all active Users
4. **Batch Execute (per batch of 200):**
   - Queries User Profile, Role, PermissionSetAssignment
   - Creates User_Audit_Snapshot__c for each user
   - Checks for privileged access (System Admin profile, elevated perm sets)
   - Creates "Privileged Access Granted" findings if feature enabled
   - Checks for snapshot duplicates if feature enabled
5. **Batch Finish:**
   - Calls SetupAuditTrailService.captureSetupChanges() (if feature enabled)
   - Calls LoginHistoryService.analyzeLoginHistory() (if feature enabled)
   - Calls SegregationOfDutiesService.validateSegregation() (if feature enabled)
   - Enqueues TerminationCrossCheckQueueable
6. **Queueable Chain Step 1 (TerminationCrossCheckQueueable):**
   - Calls TerminationCrossCheckService.runCrossCheck()
   - Creates "Terminated User Active" findings (Critical)
   - Enqueues ProfileChangeDetectorQueueable
7. **Queueable Chain Step 2 (ProfileChangeDetectorQueueable):**
   - Calls ProfileChangeDetector.detectChanges()
   - Creates findings: Profile Changed, Role Changed, Permission Set Changed, New User, Deactivated User
   - Calls AuditReportService.finalizeAuditRun()
   - Sets Status__c = 'Completed'
8. **Flow Triggers (on Audit_Run__c update to Completed):**
   - Audit_Run_Status_Update: AuditFindingCounter counts findings by severity
   - Notify_Audit_Team: Sends email if Critical findings exist
9. **Post-Completion:**
   - Dashboard refreshes showing new data
   - Findings available for review/remediation
   - PDF/email reports available

### 7.2 Real-Time Deactivation Detection

1. **Trigger:** User.IsActive changes from true to false
2. **Handler:** UserDeactivationHandler.handleDeactivations() fires
3. **Validation:** Checks Audit_Settings__c.Bypass_Jira_Ticket_Validation__c
4. **Queueable:** Enqueues UserDeactivationQueueable (avoids MIXED_DML)
5. **Processing:**
   - Gets/creates on-demand Audit_Run__c for today
   - Creates User_Audit_Snapshot__c with deactivation details
   - Creates "Deactivated User" finding (Info, pre-resolved)
   - Updates run totals

### 7.3 Termination Cross-Check

1. **Import:** User uploads CSV via terminationImporter LWC
2. **Parsing:** AuditController.importTerminations() parses CSV, creates Termination_Record__c
3. **Cross-Check:** TerminationCrossCheckService.runCrossCheck() matches emails
4. **Finding:** Creates "Terminated User Active" (Critical) for matches

### 7.4 Quarterly Access Review

1. **Initiation:** Admin clicks "Initiate Review" in quarterlyReview LWC
2. **Setup:** AccessReviewService.initiateQuarterlyReview() marks all snapshots as "Pending Review" with 90-day due date
3. **Review:** Managers review individual snapshots, approve or flag
4. **Overdue:** AccessReviewService.processOverdueReviews() creates "Overdue Access Review" findings
5. **Sign-Off:** Admin signs off run (sets Reviewed_By, Sign_Off_Date)

### 7.5 Baseline Comparison

1. **Set Baseline:** Admin marks a completed run as baseline via baselineComparison LWC
2. **Compare:** Select current run, calls BaselineSnapshotService.compareToBaseline()
3. **Results:** Shows users added, removed, and field-level changes (Profile, Role, Permission Sets, Active Status)

### 7.6 Deployment Authorization

1. **During Audit:** SetupAuditTrailService captures deployment-related setup changes
2. **Validation:** CMTicketValidationService matches deployments to Change_Request__c records
3. **Authorization:** DeploymentAuthorizationService checks deployers against Approved_Deployer__mdt
4. **Findings:** Creates findings for unauthorized deployments, missing change tickets, out-of-window deployments

### 7.7 SLA Management

1. **Creation:** Flow Set_Remediation_Due_Date sets due date on new findings based on severity
2. **Tracking:** Flow Update_SLA_Status calculates SLA status on every save
3. **Assignment:** FindingAssignmentService.assignFinding() tracks assignment dates
4. **Reminders:** OverdueRemediationService sends daily email reminders for overdue findings
5. **Recalculation:** FindingAssignmentService.recalculateSlaStatuses() runs daily via scheduler

### 7.8 Reporting

1. **PDF Generation:** AuditSummaryPdfGenerator creates PDF via Visualforce page or Blob.toPdf()
2. **Email Distribution:** AuditSummaryEmailService sends PDF to Audit_Summary_Recipient__mdt recipients
3. **Public URL:** Creates ContentDistribution for shareable download link
4. **CSV Export:** AuditReportService.generateCsvExport() for data export
5. **Scheduling:** AuditSummaryScheduler runs monthly on 1st at 6 AM

---

## 8. Test Infrastructure

### 8.1 UserAuditTestDataFactory.cls
- **Type:** @isTest utility class
- **Purpose:** Centralized test data factory for all test classes
- **Key Methods:**
  - `createAuditRun()` - Creates running audit run
  - `createPreviousAuditRun()` - Creates completed previous-month run
  - `createCompletedAuditRunWithData(...)` - Creates completed run with snapshots and findings (parameterized)
  - `createSnapshots(Id, Integer)` - Creates basic snapshots
  - `createSnapshotsWithPrivileged(Id, Integer, Integer)` - Creates snapshots with privileged status
  - `createSnapshotsForMonth(Id, Integer, Date)` - Creates snapshots for specific date
  - `createSnapshotsWithReviewStatus(Id, Integer, String, Integer)` - Creates snapshots with review status
  - `createTerminationRecords(Integer)` - Creates termination records
  - `createMatchingTerminationRecords(Integer)` - Creates terminations matching snapshot emails
  - `createFindings(Id, Id, Integer)` - Creates findings cycling through all 14 types and 3 severities
  - `createBulkTestData(Integer, Integer, Integer)` - Creates full test dataset
  - `createSetupChangeLogs(Id, Integer)` - Creates setup change log records
  - `createLoginAnomalies(Id, Integer)` - Creates login anomaly records
  - `createLoginAnomaliesOfType(Id, String, Integer)` - Creates specific anomaly types

### 8.2 Test Classes (35 test files)

All test classes follow the naming convention `*Test.cls` and use `@isTest` annotation with `UserAuditTestDataFactory` for data setup.

**Coverage targets all 35 non-test Apex classes.**

---

## 9. Security Patterns Summary

| Pattern | Usage |
|---|---|
| WITH USER_MODE | Used in all LWC controller queries (respects FLS/CRUD) |
| WITH SYSTEM_MODE | Used in batch/service classes that need elevated access |
| Security.stripInaccessible() | Used before DML in user-context operations |
| Id.valueOf() | URL parameter validation to prevent injection |
| Bind variables | Used in all dynamic SOQL (no string concatenation for user input) |
| Bypass_All_Flows | Custom permission for admin flow bypass |
| Audit_Settings__c | Hierarchy custom setting for user-level config |

---

## 10. Governor Limit Patterns

| Pattern | Implementation |
|---|---|
| Batch processing | UserAuditSnapshotBatch for bulk user queries |
| Queueable chaining | TerminationCrossCheckQueueable -> ProfileChangeDetectorQueueable |
| MIXED_DML avoidance | UserDeactivationQueueable for async processing after User trigger |
| Bulk DML | All services use bulk insert/update (List-based DML) |
| Cached metadata | AuditFeatureService loads CMT once per transaction |
| Aggregate queries | AuditFindingCounter, UserDeactivationQueueable for counting |
| Query pagination | AuditController.getFindings() with LIMIT/OFFSET |

---

## 11. Custom Labels (Referenced)

- UAA_Error_AuditRunNotFound
- UAA_Error_OnlyCompletedBaseline
- UAA_Error_NoBaselineRunSet
- UAA_Error_CurrentRunNotFound
- UAA_Error_NoBaselineCurrentlySet

---

## 12. Visualforce Pages

- **AuditSummaryPdf** - PDF rendering page (controller: AuditSummaryPdfController)
- **AuditConfiguration** - Configuration viewer page (controller: AuditConfigurationController)

---

## Summary Statistics

| Category | Count |
|---|---|
| Non-test Apex classes | 35 |
| Test Apex classes | 35 |
| Test data factory | 1 |
| Custom objects | 7 |
| Hierarchy custom settings | 1 |
| Custom metadata types | 4 |
| Custom metadata records | 30 |
| LWC components | 7 |
| Flows | 8 |
| Permission sets | 3 |
| Visualforce pages | 2 |
| Custom labels | 5+ |
| Finding types | 14 |
| Feature toggles | 17 |
| SoD rules | 10 |

**Total Apex files: 71**
**Total components: ~100+ metadata items**
