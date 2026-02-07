# ForceGuard

Salesforce-native regression testing framework. Test your Salesforce products through automated, repeatable pipelines that catch regressions before they reach production.

## What It Does

ForceGuard runs a 4-layer testing pipeline against any Salesforce product:

| Layer | Type | Purpose | Blocking? |
|-------|------|---------|-----------|
| 1 | Deployment Validation | Verifies all metadata compiles and deploys cleanly | Yes |
| 2 | Apex Test Execution | Runs Apex tests, checks coverage thresholds | Yes |
| 3 | Data Scenario Testing | Creates real data, triggers automations, asserts outcomes | No |
| 4 | Static Analysis | Runs Salesforce Code Analyzer for quality violations | No |

Blocking layers halt the pipeline on failure -- there is no point running expensive data tests if the code does not compile.

## Architecture

- **Custom Objects**: Test Suites, Test Cases, Test Runs, Test Results, Coverage Snapshots
- **Custom Metadata**: Regression_Config__mdt for feature toggles and configuration
- **LWC Dashboard**: Manage suites, execute runs, view results
- **Auto-Ticket Creation**: Creates tasks/cases on test failures
- **Scheduled Execution**: Cron-based automated regression runs
- **100% Apex Automation**: No Flows in ForceGuard's codebase (IP protection for managed package). All automation is implemented in Apex triggers, batch classes, and queueables.

## First Target

The initial test suite targets the **Audit (SOX/IPE compliance)** product with 85+ test scenarios covering Flows, Batch/Queueable chains, Finding types, and Permission sets.

A sample **Sales** test suite (33 scenarios) demonstrates that ForceGuard works for any Salesforce product.

## Project Structure

```
ForceGuard/
  force-app/main/default/
    classes/          # Apex classes (Runner, Executor, Assertion, etc.)
    lwc/              # Lightning Web Components (Dashboard, Suite Manager)
    objects/          # Custom object definitions
    customMetadata/   # Regression_Config__mdt records
    permissionsets/   # ForceGuard Admin, User, Viewer
    tabs/             # Custom tabs
    layouts/          # Page layouts
  manifest/           # package.xml
  config/             # Scratch org definition
  docs/               # Additional documentation
  scripts/            # Automation scripts
  planning/           # Architecture plan, research, product catalog
```

## Prerequisites

- Salesforce CLI (`sf`) v2+
- A Salesforce Scratch Org (recommended) or Developer Edition org
- A DevHub org for scratch org creation
- Node.js 18+ (for LWC development)

## Getting Started

```bash
# Clone the repository
git clone https://github.com/kadersh/forceguard.git
cd forceguard

# Create a scratch org
sf org create scratch -f config/project-scratch-def.json -a forceguard-dev -d 30

# Deploy to scratch org
sf project deploy start -o forceguard-dev

# Run tests
sf apex run test -l RunLocalTests -o forceguard-dev -r human
```

## Pricing

| Tier | Price | Includes |
|------|-------|----------|
| Free | $0/month | 1 test suite, 10 test cases, manual runs only |
| Professional | $99/month | 5 suites, unlimited cases, scheduled runs |
| Enterprise | $249/month | Unlimited suites, auto-ticketing, API access |
| Unlimited | $499/month | Multi-org support, priority support |

Per-org pricing. No per-user fees.

## License

Proprietary. All rights reserved.
