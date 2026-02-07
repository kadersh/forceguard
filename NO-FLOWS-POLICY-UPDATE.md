# No Flows Policy Update - Architecture Plan

**Date:** 2026-02-07
**Document:** `planning/architecture-plan.md`
**Reason:** ForceGuard is a managed package - Flows expose IP, Apex is obfuscated

## Changes Made

### 1. Added Key Policies Section (After TOC)
**Location:** Lines 21-47

Added comprehensive policy explanation:
- Why no Flows (IP protection, obfuscation, licensing, professional image)
- Implementation patterns (Triggers, Schedulable, LWC, EventBus)
- @InvocableMethod usage (customer extensibility without exposing logic)
- Critical distinction: ForceGuard has ZERO Flows, but tests products that MAY have Flows

### 2. Updated Task 1.2: Package Manifest (Phase 1)
**Location:** Lines 281, 287

- Description: Added note that ForceGuard contains NO Flows
- Acceptance Criteria: Changed "Placeholder entries for Apex classes, LWC, Flows" to "Placeholder entries for Apex classes and LWC (NO Flows - see Phase 6 policy)"

### 3. Updated Task 4.2: Layer 1 Deployment Tests (Phase 4)
**Location:** Lines 639, 643, 647

- Description: Added inline note *[Note: These are the AUDIT product's Flows being tested - ForceGuard itself has no Flows]*
- Acceptance Criteria: Changed "Flows" to "Audit product Flows"
- Acceptance Criteria: Changed "Test for Flow activation" to "Test for Flow activation on Audit product Flows (not applicable to ForceGuard - it has no Flows)"

### 4. Updated Task 4.7: Security Permission Tests (Phase 4)
**Location:** Lines 743, 749

- Description: Added inline note about Bypass_All_Flows being the AUDIT product's permission
- Acceptance Criteria: Changed "Bypass_All_Flows custom permission verified on Admin only" to "...verified on Admin only (Audit product's permission)"

### 5. Phase 6: No Changes Needed
**Location:** Lines 871-978

Phase 6 (Automation & Reporting) was already correctly written:
- "No Flows Policy (CRITICAL)" section already existed
- Task 6.1 already written as Apex Trigger + handler pattern (NOT Flow)
- All 5 tasks are pure Apex solutions
- @InvocableMethod pattern correctly documented

### 6. Updated Task 7.6: Package Deployment (Phase 7)
**Location:** Lines 1111-1112

- Acceptance Criteria: Expanded "All 6 objects, all Apex classes, all LWC included (no Flows in package)" into two lines:
  - "All 6 objects, all Apex classes, all LWC included"
  - "CRITICAL: Zero Flows in package (verify with `sf project retrieve start -m Flow`)"

### 7. Updated Section 3.1: Audit Product Test Mapping
**Location:** Lines 1128-1129

Enhanced critical clarification:
- Changed from: "These are the AUDIT product's Flows being TESTED by ForceGuard. ForceGuard itself contains NO Flows"
- To: Added "CRITICAL CLARIFICATION" with bold emphasis and expanded explanation

## Verification Commands

### Before Build (Phase 1)
```bash
# Verify package.xml has NO Flow metadata type
grep -i "<name>Flow</name>" manifest/package.xml
# Expected: No results

# Verify .forceignore excludes any Flow files
grep -i "\.flow-meta\.xml" .forceignore
# Expected: Should have pattern (if any Flow files exist accidentally)
```

### Before Packaging (Phase 7)
```bash
# Verify no Flow metadata in source
sf project retrieve start -m Flow -o target-org
# Expected: "No results found" or empty manifest

# Verify no .flow-meta.xml files in force-app
find force-app -name "*.flow-meta.xml"
# Expected: No results

# Code Analyzer: Verify no Flow references in Apex
sf code-analyzer run --target force-app --rule-selector "pmd:UnusedNullCheckInEquals"
```

## Key Points

1. **ForceGuard:** ZERO Flows (managed package IP protection)
2. **Audit Product:** MAY have Flows (product being tested)
3. **Phase 6 Tasks:** Already correctly written as Apex-only
4. **Test Scenarios (Section 3.1):** References to "Flow 1-8" are AUDIT product Flows being TESTED
5. **@InvocableMethod:** Allows customer extensibility while protecting core logic

## Related Files

- `planning/architecture-plan.md` - Main architecture document (updated)
- `PLANNING-CHECKPOINT.md` - Planning checkpoint (no changes needed)
- `planning/research-report.md` - Competitor analysis (no changes needed)
- `planning/audit-product-catalog.md` - Audit product inventory (references Audit's Flows, correct)

## OpenProject Updates Needed

**Project ID:** 9 (ForceGuard)
**Work Packages to Update:**

- WP#939 (Task 6.1): Description already correct - Apex Trigger pattern
- WP#940-943: Verify descriptions mention Apex-only approach
- All Phase 4 WPs (test scenarios): Add note that Flow references are AUDIT product, not ForceGuard

## Next Steps

1. Build Phase 1 (SFDX setup) - manifest will have NO Flow metadata type
2. During Phase 6 build - verify each task is pure Apex (no accidental Flows)
3. Before Phase 7 packaging - run verification commands above
4. AppExchange security review - emphasize "No declarative automation, all code-based"

---

**Status:** Architecture plan updated successfully. All Flow references clarified. Ready for Phase 1 build.
