# ForceGuard Phase 1: Foundation & Project Setup
## Build Start Checklist - 2026-02-07

**Project:** ForceGuard (Salesforce Regression Testing Framework)
**OpenProject:** Project ID 9
**Scope:** Foundation setup and project infrastructure
**Duration:** 3-5 days
**Status:** Ready to start
**All WPs:** WP#911-914 (Phase 1 tasks)

---

## Phase 1 Complete Hierarchy

```
Epic: WP#901 (ForceGuard - Audit Product)
└── Phase 1: WP#902 (Foundation & Project Setup)
    ├── Task 1.1: WP#911 - Create SFDX Project Structure
    ├── Task 1.2: WP#912 - Create Package Manifest
    ├── Task 1.3: WP#913 - Initialize GitHub Repository
    └── Task 1.4: WP#914 - Create Project Documentation
```

---

## Phase 1 Tasks (4 Total)

### WP#911: Create SFDX Project Structure
**Priority:** P0 (High)
**Effort:** Small (1-2 days)
**Status:** New
**Dependencies:** None

**What to build:**
- Initialize ForceGuard SFDX project with `forceguard` namespace
- Create `sfdx-project.json` with API version 62.0
- Create `project-scratch-def.json` for scratch org definition
- Directory structure:
  ```
  force-app/main/default/
  ├── classes/
  ├── lwc/
  ├── objects/
  ├── customMetadata/
  ├── flows/
  ├── permissionsets/
  ├── tabs/
  └── layouts/
  ```
- Add `.gitignore` (standard Salesforce ignores)

**Acceptance Criteria - 5 checklist items:**
- [ ] `sfdx-project.json` exists with correct namespace and API version
- [ ] `project-scratch-def.json` creates a working scratch org
- [ ] Directory structure matches planned layout (classes/, lwc/, objects/, etc.)
- [ ] `.gitignore` excludes `.sfdx/`, `.sf/`, `node_modules/`, etc.
- [ ] `sf project deploy validate` runs without errors on empty project

**Validation:** `sf project deploy validate --source-dir force-app` should complete successfully

---

### WP#912: Create Package Manifest
**Priority:** P0 (High)
**Effort:** Small (1 day)
**Status:** New
**Dependencies:** WP#911 (needs SFDX project first)

**What to build:**
- Create `manifest/package.xml` with API version 62.0
- List all 6 custom objects:
  - Regression_Test_Suite__c
  - Regression_Test_Case__c
  - Regression_Test_Run__c
  - Regression_Test_Result__c
  - Test_Coverage_Snapshot__c
  - (1 more - see data model)
- List custom metadata type: Regression_Config__mdt
- Add placeholder sections for Apex classes, LWC, Flows (to be filled in later)
- Start with data model components first

**Acceptance Criteria - 5 checklist items:**
- [ ] `manifest/package.xml` exists with correct API version
- [ ] All 6 custom objects listed under `CustomObject`
- [ ] Custom metadata types listed under `CustomMetadata`
- [ ] Placeholder entries for Apex classes, LWC, Flows
- [ ] Manifest validates with `sf project retrieve start` (no syntax errors)

**Validation:** `sf project retrieve start` should accept the manifest syntax

---

### WP#913: Initialize GitHub Repository
**Priority:** P0 (High)
**Effort:** Small (1-2 days)
**Status:** New
**Dependencies:** WP#911, WP#912 (needs project structure and manifest)

**What to build:**
- Create GitHub repo: `kadersh/forceguard`
- Configure branch protection on `main` branch:
  - Require pull request reviews
  - Require status checks to pass
- Create `develop` branch for active development
- Create README.md with:
  - Product overview
  - Installation instructions (placeholder)
  - Badge links
- Create DEPLOYMENT.md with:
  - Deployment workflow for sandbox
  - Deployment workflow for production
  - Rollback instructions (optional)
- Push initial SFDX project structure to `develop` branch

**Acceptance Criteria - 6 checklist items:**
- [ ] GitHub repo exists at `github.com/kadersh/forceguard`
- [ ] `main` branch has branch protection enabled
- [ ] `develop` branch exists for active development
- [ ] README.md has product overview section
- [ ] DEPLOYMENT.md has deployment workflow documented
- [ ] Initial commit contains full SFDX project structure

**Validation:** All files pushed to GitHub and visible in repository

---

### WP#914: Create Project Documentation
**Priority:** P1 (Normal)
**Effort:** Small (1-2 days)
**Status:** New
**Dependencies:** WP#911 (needs project context)

**What to build:**
- Create CLAUDE.md with:
  - Project context and overview
  - Agent routing (which agents handle which tasks)
  - Directory structure documentation
  - Build commands (deploy, test, retrieve)
  - OpenProject reference (Project ID 9, task structure)
- Create TESTING_GUIDE.md explaining:
  - How to write test scenarios
  - How to create test suites
  - How to add new test cases
  - Test case structure and fields
- Create CODING_STANDARDS.md covering:
  - Bulkification patterns for ForceGuard code
  - Error handling conventions
  - Naming conventions (ForceGuard_ prefix for all classes)
  - SOQL/DML best practices

**Acceptance Criteria - 4 checklist items:**
- [ ] CLAUDE.md exists with accurate project context and agent routing
- [ ] TESTING_GUIDE.md explains how to create test suites and cases
- [ ] Coding standards documented (naming, patterns, conventions)
- [ ] All documentation reflects the 4-layer model accurately

**Validation:** Documentation should be complete and readable

---

## Build Sequence

**Recommended order (respects dependencies):**

1. **WP#911** (SFDX Project) → Creates the foundation everything else depends on
2. **WP#912** (Package Manifest) → Requires SFDX project, needed before GitHub
3. **WP#913** (GitHub Repo) → Requires both above, needs files to push
4. **WP#914** (Documentation) → Can happen in parallel with others, but last makes sense

**Parallel execution possible:**
- WP#914 can start immediately (doesn't depend on others)
- WP#913 must wait for WP#912
- WP#912 must wait for WP#911

---

## What Phase 1 Enables

After Phase 1 is complete:
- Salesforce project is properly structured for development
- GitHub repo is set up with proper branching and protection
- Team has clear documentation on coding standards and testing approach
- Foundation ready for Phase 2 (Custom Objects & Data Model)

---

## Files to Create/Modify

### New Files
- `sfdx-project.json` - Project configuration
- `project-scratch-def.json` - Scratch org definition
- `manifest/package.xml` - Deployment manifest
- `.gitignore` - Standard Salesforce ignores
- `README.md` - Product overview
- `DEPLOYMENT.md` - Deployment guide
- `CLAUDE.md` - Developer instructions
- `TESTING_GUIDE.md` - Test writing guide
- `CODING_STANDARDS.md` - Naming and patterns guide

### Directory Structure to Create
```
force-app/main/default/
├── classes/
├── lwc/
├── objects/
├── customMetadata/
├── flows/
├── permissionsets/
├── tabs/
└── layouts/
```

---

## Success Criteria for Phase 1

✅ All 4 tasks marked as "Closed" in OpenProject
✅ SFDX project validates with no errors
✅ GitHub repo created and accessible
✅ All documentation complete and accurate
✅ Team ready to start Phase 2

---

## Next Phase Preview

**Phase 2: Custom Objects & Data Model**
- Build 6 custom objects with 40+ fields total
- Create custom metadata type for configuration
- Set up validation rules and relationships
- Duration: 4-6 days
- 6 tasks (WP#915-920)

---

## Reference Documentation

**Key files in this repository:**
- `/home/ak/SynologyDrive/Claude/Personal/salesforce-solutions/Products/ForceGuard/planning/architecture-plan.md` - Full technical blueprint (1698 lines)
- `/home/ak/SynologyDrive/Claude/Personal/salesforce-solutions/Products/ForceGuard/PLANNING-CHECKPOINT.md` - Status tracker
- `/home/ak/SynologyDrive/Claude/Personal/salesforce-solutions/Products/ForceGuard/forceguard-product-vision.html` - Product vision document

