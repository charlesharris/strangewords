# Phase 1: Clean Tree & Trustworthy iOS Harness - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-08
**Phase:** 1-Clean Tree & Trustworthy iOS Harness
**Areas discussed:** Dirty-tree reconciliation, Harness entry point, Simulator policy, Signing for test runs

---

## Dirty-tree reconciliation

| Option | Description | Selected |
|--------|-------------|----------|
| Keep all of it | Deliberate App Attest/signing WIP; docs already describe it; bundle ID must match registered App ID | ✓ |
| Keep iOS, revert server | Keep signing/scheme/docs, revert the unused AppAttestAppID config scaffold | |
| Revert everything | Baseline from last commit, redo signing work later | |

**User's choice:** Keep all of it
**Notes:** Follow-up — commit shape:

| Option | Description | Selected |
|--------|-------------|----------|
| Split by concern | iOS signing/scheme (+docs) and server config scaffold as separate commits | ✓ |
| One commit | Single "reconcile working tree" commit | |

---

## Harness entry point

| Option | Description | Selected |
|--------|-------------|----------|
| scripts/ dir | New top-level scripts/test-ios.sh; run.sh untouched; Phase 4 verify.sh lives beside it | ✓ |
| Makefile target | ios/Makefile mirroring server/Makefile convention | |
| Extend run.sh | Add --test mode to the existing entry script | |

**User's choice:** scripts/ dir
**Notes:** Follow-ups — script scope: iOS runner only this phase (Go checks run bare; aggregation is Phase 4) ✓ over "both scripts now". Evidence location: gitignored `build/verify/<timestamp>/` ✓ over `ios/build/` or discretion.

---

## Simulator policy

| Option | Description | Selected |
|--------|-------------|----------|
| Pin name, manage boot | Pin "iPhone 16" (OS floats), bootstatus before, shutdown after | ✓ |
| Pin name + OS version | Fully deterministic but breaks on runtime updates | |
| Leave sim running | Faster repeated local runs, state leaks between runs | |

**User's choice:** Pin name, manage boot

---

## Signing for test runs

| Option | Description | Selected |
|--------|-------------|----------|
| CODE_SIGNING_ALLOWED=NO | Machine-independent test runs, avoids silent-keychain failures | ✓ |
| Automatic signing | Closer to device reality, ties harness to this machine | |
| You decide | Planner picks based on research prototype | |

**User's choice:** CODE_SIGNING_ALLOWED=NO

---

## Proof test (follow-up within Harness area)

| Option | Description | Selected |
|--------|-------------|----------|
| Real Syllables seed | 2-3 genuine cases, kept as seed of Phase 2's suite | ✓ |
| Throwaway placeholder | Pure probe deleted in Phase 2 | |
| You decide | Planner picks what best proves the verdict paths | |

**User's choice:** Real Syllables seed

## Claude's Discretion

- Test target naming / bundle ID (confirm against new `bundleIdPrefix`)
- `scripts/test-ios.sh` flag surface, retry mechanics, summary format
- `GENERATE_INFOPLIST_FILE` vs explicit plist for the test target

## Deferred Ideas

None — discussion stayed within phase scope.
