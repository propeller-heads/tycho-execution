# Solidity Conventions

Derived from:
- [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html)
- [OpenZeppelin Engineering Guidelines](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/GUIDELINES.md)

Last updated: 2026-02-27

---

## Rules

| ID | Severity | Enforcement | Title |
|----|----------|-------------|-------|
| SOL-001 | WARN | ast | Private state variables must have a leading underscore |
| SOL-002 | WARN | ast | Internal functions and variables must have a leading underscore |
| SOL-003 | ERROR | ast | Interfaces must be prefixed with `I` |
| SOL-004 | WARN | manual | Non-standalone abstract contracts must use the `abstract` keyword |
| SOL-005 | WARN | ast | Unchecked blocks must be preceded by a safety comment |
| SOL-006 | INFO | ast | Custom errors should follow descriptive naming (no redundant `Error` suffix) |
| SOL-007 | INFO | manual | Overridable functions should be marked `virtual` |
| SOL-008 | WARN | manual | Order of functions within a contract |
| SOL-009 | WARN | tool | Modifier order on function declarations |
| SOL-010 | WARN | tool | Naming conventions (CapWords, mixedCase, UPPER_CASE) |
| SOL-011 | WARN | tool | All import statements at top of file after pragma |
| SOL-012 | WARN | manual | File-level layout order |
| SOL-013 | WARN | manual | Events emitted immediately after state changes, past tense naming |
| SOL-014 | WARN | ast | All state variables must be private |
| SOL-015 | WARN | tool | Use double quotes for strings |

---

## Rule Details

### SOL-001 — Private state variables must have a leading underscore
Private state variables must be named with a leading underscore (`_varName`).
*Source: OpenZeppelin GUIDELINES.md*

### SOL-002 — Internal functions and variables must have a leading underscore
Internal functions and state variables must be named with a leading underscore (`_funcName`, `_varName`).
*Source: OpenZeppelin GUIDELINES.md*

### SOL-003 — Interfaces must be prefixed with `I`
Interface names must use a capital `I` prefix (e.g., `IFoo`, `IERC20`).
*Source: OpenZeppelin GUIDELINES.md*

### SOL-004 — Non-standalone abstract contracts must use the `abstract` keyword
Contracts not intended to be deployed directly must be declared with the `abstract` keyword.
*Source: OpenZeppelin GUIDELINES.md*

### SOL-005 — Unchecked blocks must be preceded by a safety comment
Every `unchecked` block must have a comment explaining why overflow cannot happen, either immediately before the block or as the first line inside it.
*Source: OpenZeppelin GUIDELINES.md*

### SOL-006 — Custom errors should follow descriptive naming (no redundant `Error` suffix)
Custom error names should be descriptive. Avoid a generic `Error` suffix unless domain-qualified per EIP-6093 (e.g., `ERC20InsufficientBalance` is acceptable).
*Source: OpenZeppelin GUIDELINES.md*

### SOL-007 — Overridable functions should be marked `virtual`
Functions intended to be overridden should be marked `virtual`. Exception: if function A is purely an alias for function B, only B needs `virtual`.
*Source: OpenZeppelin GUIDELINES.md*

### SOL-008 — Order of functions within a contract
Functions must follow the order: constructor, receive, fallback, external, public, internal, private. Within each group, view and pure functions go last.
*Source: Solidity Style Guide*

### SOL-009 — Modifier order on function declarations
Modifiers on function declarations must appear in order: visibility, mutability, virtual, override, custom modifiers.
*Source: Solidity Style Guide*

### SOL-010 — Naming conventions
Contracts, libraries, structs, events, and enums use CapWords. Functions, arguments, and variables use mixedCase. Constants use UPPER_CASE_WITH_UNDERSCORES.
*Source: Solidity Style Guide*

### SOL-011 — All import statements at top of file after pragma
Import statements must appear at the top of the file, after pragma statements.
*Source: Solidity Style Guide*

### SOL-012 — File-level layout order
File-level elements must appear in order: pragma, imports, events, errors, interfaces, libraries, contracts.
*Source: Solidity Style Guide*

### SOL-013 — Events emitted immediately after state changes, past tense naming
Events should be emitted immediately after the state change they represent and named in past tense. Exception: ERC standards using present tense (Transfer, Approval).
*Source: OpenZeppelin GUIDELINES.md*

### SOL-014 — All state variables must be private
State variables must be private; state changes go through setters that emit events.
*Source: OpenZeppelin GUIDELINES.md*

### SOL-015 — Use double quotes for strings
String literals must use double quotes, not single quotes.
*Source: Solidity Style Guide*
