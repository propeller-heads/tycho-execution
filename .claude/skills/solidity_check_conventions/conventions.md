# Solidity Conventions

Derived from:
- [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html)
- [OpenZeppelin Engineering Guidelines](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/GUIDELINES.md)

Last updated: 2026-03-02

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
| SOL-016 | WARN | tool | Indentation: 4 spaces; spaces over tabs; no mixing |
| SOL-017 | WARN | tool | Blank lines: 2 around top-level declarations; 1 between contract functions |
| SOL-018 | WARN | tool | Maximum line length: 120 characters with specified wrapping format |
| SOL-019 | INFO | manual | Source file encoding: UTF-8 or ASCII |
| SOL-020 | WARN | tool | Whitespace in expressions: no extraneous whitespace inside parens/brackets/braces |
| SOL-021 | WARN | tool | Whitespace: no whitespace before commas or semicolons; no alignment spaces |
| SOL-022 | WARN | tool | Control structures: opening brace on same line; `else` on same line as `}` |
| SOL-023 | WARN | tool | Mappings: no space between `mapping` keyword and its type |
| SOL-024 | WARN | tool | Array declarations: no space between type and brackets |
| SOL-025 | WARN | tool | Operator spacing: single space around operators; consistent on both sides |
| SOL-026 | WARN | manual | Within-contract layout order: type decls → state vars → events → errors → modifiers → functions |
| SOL-027 | WARN | ast | Names to avoid: never use `l`, `O`, or `I` as single-letter identifiers |
| SOL-028 | ERROR | manual | Filename matching: contract/library name must match the filename |
| SOL-029 | WARN | ast | Modifier naming: use mixedCase (e.g., `onlyBy`, `onlyAfter`) |
| SOL-030 | INFO | ast | Naming collision: use `name_` trailing underscore to avoid reserved word clashes |
| SOL-031 | WARN | ast | NatSpec: fully annotate all public interfaces with `///` or `/** */` |
| SOL-032 | WARN | ast | Numeric literals: hex for memory operations, decimal for bit operations |
| SOL-033 | INFO | manual | Return values generally not named |
| SOL-034 | WARN | ast | Custom error names must not be duplicated across the inheritance chain |

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
Every `unchecked` block must have a comment explaining why overflow cannot happen. The comment may be omitted if the reason is immediately apparent from the line above the unchecked block.
*Source: OpenZeppelin GUIDELINES.md*

### SOL-006 — Custom errors should follow descriptive naming (no redundant `Error` suffix)
Custom error names should follow EIP-6093. Domain prefix order: (1) `ERC<number>` if violating an ERC spec, (2) component name (e.g. `Governor`, `ECDSA`). Avoid a generic `Error` suffix. Declare errors in: the underlying ERC if already defined there, else the interface/library, else the implementation, else the extension. Do not declare the same custom error name twice across the inheritance chain.
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
Contracts, libraries, structs, events, and enums use CapWords. Functions, modifiers, arguments, and variables use mixedCase. Constants use UPPER_CASE_WITH_UNDERSCORES.
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

### SOL-016 — Indentation: 4 spaces; spaces over tabs; no mixing
Use 4 spaces per indentation level. Spaces only — no tabs, no mixing tabs and spaces.
*Source: Solidity Style Guide*

### SOL-017 — Blank lines: 2 around top-level declarations; 1 between contract functions
Surround top-level declarations with 2 blank lines. Between functions within a contract, use 1 blank line.
*Source: Solidity Style Guide*

### SOL-018 — Maximum line length: 120 characters with specified wrapping format
Maximum line length is 120 characters. Long lines must be wrapped at specified break points.
*Source: Solidity Style Guide*

### SOL-019 — Source file encoding: UTF-8 or ASCII
Source files must be encoded in UTF-8 or ASCII.
*Source: Solidity Style Guide*

### SOL-020 — Whitespace in expressions: no extraneous whitespace inside parens/brackets/braces
No extraneous whitespace immediately inside parentheses, brackets, or braces.
*Source: Solidity Style Guide*

### SOL-021 — Whitespace: no whitespace before commas or semicolons; no alignment spaces
No whitespace before a comma or semicolon. No extra spaces for alignment.
*Source: Solidity Style Guide*

### SOL-022 — Control structures: opening brace on same line; `else` on same line as `}`
Opening brace of control structures goes on the same line as the declaration. The `else` keyword goes on the same line as the closing brace of the `if` block.
*Source: Solidity Style Guide*

### SOL-023 — Mappings: no space between `mapping` keyword and its type
No space between the `mapping` keyword and its type (e.g., `mapping(address => uint256)`, not `mapping (address => uint256)`).
*Source: Solidity Style Guide*

### SOL-024 — Array declarations: no space between type and brackets
No space between a type and its array brackets (e.g., `uint256[]`, not `uint256 []`).
*Source: Solidity Style Guide*

### SOL-025 — Operator spacing: single space around operators; consistent on both sides
Single space on both sides of binary and assignment operators. Spacing must be consistent on both sides.
*Source: Solidity Style Guide*

### SOL-026 — Within-contract layout order: type decls → state vars → events → errors → modifiers → functions
Within a contract, declare elements in order: type declarations, state variables, events, errors, modifiers, functions.
*Source: Solidity Style Guide*

### SOL-027 — Names to avoid: never use `l`, `O`, or `I` as single-letter identifiers
Never use `l` (lowercase L), `O` (uppercase O), or `I` (uppercase I) as single-character identifiers — they are visually ambiguous.
*Source: Solidity Style Guide*

### SOL-028 — Filename matching: contract/library name must match the filename
The filename must match the name of the contract or library it defines (e.g., `Foo.sol` for `contract Foo`).
*Source: Solidity Style Guide*

### SOL-029 — Modifier naming: use mixedCase (e.g., `onlyBy`, `onlyAfter`)
Modifier names must use mixedCase (e.g., `onlyBy`, `onlyAfter`).
*Source: Solidity Style Guide*

### SOL-030 — Naming collision: use `name_` trailing underscore to avoid reserved word clashes
When a name would clash with a reserved word, append a trailing underscore (e.g., `class_`).
*Source: Solidity Style Guide*

### SOL-031 — NatSpec: fully annotate all public interfaces with `///` or `/** */`
All public interfaces must be fully annotated with NatSpec using `///` single-line or `/** */` multi-line style.
*Source: Solidity Style Guide*

### SOL-032 — Numeric literals: hex for memory operations, decimal for bit operations
In assembly/Yul, use hexadecimal for memory locations, offsets, and lengths (e.g. `mload(0x40)`, `mstore(add(ptr, 0x20), value)`). Use decimal for shift amounts and bit positions (e.g. `shl(128, value)`). Trivially small values (1, 2) may use decimal even in memory operations.
*Source: OpenZeppelin GUIDELINES.md*

### SOL-033 — Return values generally not named
Return values should not be named unless they are not immediately clear from context or there are multiple return values that need disambiguation.
*Source: OpenZeppelin GUIDELINES.md*

### SOL-034 — Custom error names must not be duplicated across the inheritance chain
Do not declare the same custom error name more than once across contracts in an inheritance hierarchy, as this causes duplicated identifier errors when inheriting from multiple contracts.
*Source: OpenZeppelin GUIDELINES.md*
