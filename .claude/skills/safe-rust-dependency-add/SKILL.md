---
name: safe-rust-dependency-add
description: Security gate for any new Rust dependency (cargo add / Cargo.toml edits / feature changes). Run before adding deps; includes RustSec pre-check, 48h age gate, exact pinning, and cargo-audit before/after delta.
user-invocable: true
disable-model-invocation: false
---

# Skill: Mandatory Safe Rust Dependency Add

## Purpose

This skill MUST automatically execute whenever a new Rust dependency is added,
whether explicitly requested by the user or implicitly required to fulfill a task.

This includes:
- `cargo add <crate>`
- Editing `Cargo.toml` to introduce a new dependency
- Adding a dependency to a workspace member
- Introducing a transitive dependency via feature changes
- Installing a crate via `cargo install` inside the project

This skill is NOT optional.
It is a required security gate before any dependency modification.

---

# Enforcement Policy

## Trigger Condition

This skill MUST run when:

1. The assistant intends to:
   - Run `cargo add`
   - Modify `Cargo.toml`
   - Suggest adding a new crate dependency
   - Generate code that requires adding a new dependency

2. The user asks to:
   - Add a crate
   - Install a crate
   - Include a new Rust library
   - Fix an error by adding a dependency

Before performing the action, the assistant MUST invoke this skill.

---

# High-Level Flow

0) Preconditions
- Confirm Rust project (Cargo.toml present)
- Ensure `cargo-audit` exists; if not:
  - `cargo install cargo-audit`

---

1) Baseline Audit

If no Cargo.lock:
- `cargo generate-lockfile`

Run:
- `cargo audit --json > /tmp/audit_before.json`

This establishes baseline vulnerability state.

---

2) RustSec Advisory Pre-Check

Update advisory DB if needed:
- Clone or pull https://github.com/RustSec/advisory-db

Search for advisories affecting the crate.

If advisories exist:
- Determine affected version ranges
- Continue to version selection logic

Do NOT stop yet — some versions may be fixed.

---

3) Version Selection (crates.io age gate)

Fetch all non-yanked stable versions from crates.io.

Definitions:
- "Fresh release" = published within last 48 hours
- Ignore pre-releases unless explicitly requested

Determine:
- latest_version
- newest_version_older_than_48h

Decision logic:

A) If latest_version is older than 48h:
   → Use latest_version

B) If latest_version is < 48h old:
   - Check if it fixes a RustSec advisory affecting the older version.
   - If YES → Use latest_version
   - If NO → Use newest_version_older_than_48h

Optional:
If choosing a fresh release without security necessity:
- Perform source diff against previous stable version
- Check for:
  - New build.rs
  - Suspicious network/process usage
  - Large binary blobs
  - Obfuscated additions
If suspicious → STOP

---

4) Add Dependency (Exact Pin Required)

Always pin exact patch:

cargo add crate_name@=X.Y.Z

If needed, manually edit Cargo.toml to enforce:
version = "=X.Y.Z"

Never use:
- caret (^)
- wildcard (*)
- loose semver ranges

---

5) Post-Add Audit

Run:
- cargo audit --json > /tmp/audit_after.json

Compare before vs after.

If new vulnerabilities are introduced by:
- the added crate
- or new transitive dependencies

→ WARN and STOP.

If vulnerabilities existed before:
→ Proceed but clearly report them.

---

6) Final Report Must Include

- Selected version and why
- Whether age gate was triggered
- RustSec findings
- Audit delta summary
- Exact Cargo.toml entry
- Stop/Proceed decision

---

# Non-Bypass Rule

The assistant must NOT:
- Skip this process for convenience
- Add a crate directly without audit
- Use the latest version blindly

The only valid bypass is if the user explicitly says:
"Skip dependency security checks"

Even then:
- The assistant must warn clearly before proceeding.

---

# Scope

Applies to:
- Direct dependencies
- Dev dependencies
- Build dependencies
- Workspace member dependencies

Does NOT apply to:
- Pure std-only code
- Code refactors without dependency change

---

# Security Priority

If there is any ambiguity:
→ Prefer older stable version
→ Prefer stopping
→ Prefer warning loudly
