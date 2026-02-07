# ForceGuard Deployment Guide

## Deployment Order

Deploy metadata in dependency order. Objects first, then code that references them.

### Step 1: Custom Objects and Fields

```bash
sf project deploy start \
  -d force-app/main/default/objects \
  -o <target-org>
```

Objects:
1. `Regression_Test_Suite__c`
2. `Regression_Test_Case__c` (lookup to Suite)
3. `Regression_Test_Run__c` (lookup to Suite)
4. `Regression_Test_Result__c` (lookup to Run + Case)
5. `Test_Coverage_Snapshot__c` (lookup to Run)
6. `Regression_Config__mdt` (Custom Metadata Type)

### Step 2: Custom Metadata Records

```bash
sf project deploy start \
  -d force-app/main/default/customMetadata \
  -o <target-org>
```

### Step 3: Apex Classes

```bash
sf project deploy start \
  -d force-app/main/default/classes \
  -o <target-org>
```

### Step 4: Lightning Web Components

```bash
sf project deploy start \
  -d force-app/main/default/lwc \
  -o <target-org>
```

### Step 5: Flows

```bash
sf project deploy start \
  -d force-app/main/default/flows \
  -o <target-org>
```

### Step 6: Permission Sets, Tabs, Layouts

```bash
sf project deploy start \
  -d force-app/main/default/permissionsets \
  -d force-app/main/default/tabs \
  -d force-app/main/default/layouts \
  -o <target-org>
```

### Step 7: Assign Permission Sets

```bash
sf org assign permset -n ForceGuard_Admin -o <target-org>
```

## Full Deployment (All at Once)

For scratch orgs or clean environments:

```bash
sf project deploy start -o <target-org>
```

## Validation Only (No Changes)

```bash
sf project deploy start --dry-run -o <target-org>
```

## Running Tests After Deployment

```bash
# All local tests
sf apex run test -l RunLocalTests -o <target-org> -r human

# Specific test class
sf apex run test -n RegressionTestRunnerTest -o <target-org> -r human
```

## Scratch Org Setup

```bash
# Create scratch org
sf org create scratch \
  -f config/project-scratch-def.json \
  -a forceguard-dev \
  -d 30

# Deploy everything
sf project deploy start -o forceguard-dev

# Assign admin permission set
sf org assign permset -n ForceGuard_Admin -o forceguard-dev

# Open the org
sf org open -o forceguard-dev
```

## Environment Variables

None required for standard deployment. The app is fully Salesforce-native.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Deploy fails on objects | Check dependency order -- parent objects before children |
| Apex compile error | Ensure objects are deployed first |
| Permission set assignment fails | Deploy permission set metadata before assigning |
| LWC not visible | Check tab and app assignments, clear browser cache |
| Tests fail with "SObject not found" | Objects not deployed -- run Step 1 first |
