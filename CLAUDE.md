# CLAUDE.md - ForceGuard

This file provides guidance to Claude Code when working on the ForceGuard product.

## What This Is

**ForceGuard** is a Salesforce-native regression testing framework. It defines test scenarios, executes them, tracks results, and reports failures. Built as an installable product for clients.

**Starting scope:** Audit product (SOX/IPE compliance) - 38+ Apex classes, 8 custom objects, 7 LWC, 8 Flows.

## Product Architecture

### 4-Layer Testing Model

```
Layer 1: Deployment Validation  [BLOCKING]  ~30-60s
  sf project deploy validate -> syntax, dependencies, references

Layer 2: Apex Test Execution    [BLOCKING]  ~2-5m
  sf apex run test -> unit assertions, code coverage (85%+)

Layer 3: Data Scenario Testing  [VERIFICATION]  ~5-15m
  sf data create/query + anonymous apex -> end-to-end business logic

Layer 4: Static Analysis        [QUALITY GATE]  ~1-2m
  sf code-analyzer run -> security, patterns, best practices
```

### Custom Objects

| Object | Purpose |
|--------|---------|
| `Regression_Test_Suite__c` | Groups tests per product (name, version, target org) |
| `Regression_Test_Case__c` | Individual test definitions (steps, assertions, perspective) |
| `Regression_Test_Run__c` | Execution instances (date, status, pass/fail counts) |
| `Regression_Test_Result__c` | Individual results per test case per run |
| `Regression_Config__mdt` | Configuration (thresholds, org aliases, settings) |

### Stakeholder Perspectives

Each test tagged with: **Developer**, **Admin**, **Product Manager**, **Designer**, **Client**

### Test Categories

Deployment | Functional | Edge Case | Bulk/Performance | Security/Permission | Integration | Regression | UAT

## Directory Structure

```
ForceGuard/
├── CLAUDE.md                    # This file
├── README.md                    # Product overview
├── sfdx-project.json            # Salesforce DX project config
├── manifest/
│   └── package.xml              # Deployment manifest
├── force-app/main/default/
│   ├── classes/                 # Apex classes + test classes
│   ├── lwc/                     # Lightning Web Components
│   ├── objects/                 # Custom objects and fields
│   ├── customMetadata/          # Configuration records
│   └── flows/                   # Flow definitions
├── docs/
│   ├── INSTALLATION-GUIDE.md
│   ├── CONFIGURATION-GUIDE.md
│   └── WRITING-TESTS.md
├── DEPLOYMENT.md
├── TESTING_GUIDE.md
└── GUMROAD-LISTING.md
```

## Build Commands

```bash
# Validate deployment
sf project deploy validate --source-dir force-app --target-org <alias>

# Deploy
sf project deploy start --source-dir force-app --target-org <alias>

# Run Apex tests
sf apex run test --target-org <alias> --test-level RunLocalTests --result-format human

# Retrieve metadata
sf project retrieve start --source-dir force-app --target-org <alias>
```

## OpenProject

| Item | Value |
|------|-------|
| Project | ForceGuard (ID: 9) |
| URL | http://192.168.1.249:5683/projects/forceguard/work_packages |
| Epic | WP#901: ForceGuard - Audit Product |
| Phases | WP#902-908 (7 phases) |
| Tasks | WP#911-948 (38 tasks) |

## GitHub

| Item | Value |
|------|-------|
| Repo | https://github.com/kadersh/forceguard |

## Agent Routing

| Task | Agent |
|------|-------|
| Apex, Flows, LWC development | `salesforce-builder` |
| Test classes, coverage | `salesforce-qa-specialist` |
| Deployment, packaging | `sf-devops-specialist` |
| Documentation | `documentation-specialist` |
| OpenProject updates | `openproject-specialist` |

## Audit Product Reference

The Audit product we're testing is at:
`/home/ak/SynologyDrive/Claude/salesforce-solutions/change-requests/Audit`

Key components to test:
- 38+ Apex classes (batch jobs, services, controllers)
- 8 custom objects (Audit_Run__c, User_Audit_Snapshot__c, Audit_Finding__c, etc.)
- 7 LWC (dashboard, control center, termination importer, findings review, etc.)
- 8 Flows (status updates, notifications, SLA tracking)
- 4 Custom Metadata Types (recipients, SoD rules, feature toggles, approved deployers)
- 3 Permission Sets (Administrator, Full Access, Viewer)

## Quality Requirements

- Handles bulk operations (200+ records) without governor limits
- All DML operations have fault/error handling
- No hardcoded values - use Custom Metadata Types
- Apex test coverage 90%+
- Works on any Salesforce org with the Audit product installed
- All Flows include descriptions on every element

## Validation Before Completion

| Component | Validation |
|-----------|-----------|
| Apex classes | `sf project deploy validate` succeeds |
| Flows | Flow activates without errors |
| LWC | `npm run lint` + deployment succeeds |
| Full product | Deploy to clean org + all tests pass |
