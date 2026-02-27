# Conventions Diff — Dry Run

Generated: 2026-02-27T00:00:00Z
Source changed: Solidity Style Guide (`902a245…` → `7978f4a…`)
Source unchanged: OpenZeppelin GUIDELINES.md

**Would change:** 1 modified, 16 new, 0 removed
Run with `--apply-updates` to apply.

---

## Modified rules (1)

### SOL-010 — Naming conventions
**Current pinned description:**
> Contracts, libraries, structs, events, and enums must use CapWords. Functions, arguments, and variables must use mixedCase. Constants must use UPPER_CASE_WITH_UNDERSCORES.

**Upstream now specifies:**
> Modifiers are explicitly listed as a separate named category requiring mixedCase (e.g., `onlyBy`, `onlyAfter`). The pinned description omits modifiers from the mixedCase list.

**Proposed update:**
> Add "modifiers" to the mixedCase list: "Functions, modifiers, arguments, and variables must use mixedCase."

---

## New rules (16)

| Proposed ID | Title | Severity | Enforcement |
|-------------|-------|----------|-------------|
| SOL-016 | Indentation: 4 spaces; spaces over tabs; no mixing | WARN | tool |
| SOL-017 | Blank lines: 2 around top-level declarations; 1 between contract functions | WARN | tool |
| SOL-018 | Maximum line length: 120 characters with specified wrapping format | WARN | tool |
| SOL-019 | Source file encoding: UTF-8 or ASCII | INFO | manual |
| SOL-020 | Whitespace in expressions: no extraneous whitespace inside parens/brackets/braces | WARN | tool |
| SOL-021 | Whitespace: no whitespace before commas or semicolons; no alignment spaces | WARN | tool |
| SOL-022 | Control structures: opening brace on same line; `else` on same line as `}` | WARN | tool |
| SOL-023 | Mappings: no space between `mapping` keyword and its type | WARN | tool |
| SOL-024 | Array declarations: no space between type and brackets | WARN | tool |
| SOL-025 | Operator spacing: single space around operators; consistent on both sides | WARN | tool |
| SOL-026 | Within-contract layout order: type decls → state vars → events → errors → modifiers → functions | WARN | manual |
| SOL-027 | Names to avoid: never use `l`, `O`, or `I` as single-letter identifiers | WARN | ast |
| SOL-028 | Filename matching: contract/library name must match the filename | ERROR | manual |
| SOL-029 | Modifier naming: use mixedCase (e.g., `onlyBy`, `onlyAfter`) | WARN | ast |
| SOL-030 | Naming collision: use `name_` trailing underscore to avoid reserved word clashes | INFO | ast |
| SOL-031 | NatSpec: fully annotate all public interfaces with `///` or `/** */` | WARN | ast |

---

## Removed rules (0)

None.
