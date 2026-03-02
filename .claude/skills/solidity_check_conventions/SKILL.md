# Skill Spec: Solidity Conventions — Compare/Update/Enforce

## Bootstrap (one-time, NOT part of the skill)
Command: conventions_bootstrap
- Fetch:
  - https://docs.soliditylang.org/en/latest/style-guide.html
  - https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/master/GUIDELINES.md
  - https://github.com/Aboudjem/solidity-style-guide?tab=readme-ov-file#constants
- Extract into:
  - conventions.rules.json
  - conventions.md (rendered from rules)
  - conventions.sources.json (fingerprints + metadata)

Bootstrap is run once to establish a pinned baseline.

---

## Skill (runs repeatedly)
Command: conventions_skill

### Step 1: Compare upstream sources to pinned fingerprints
Inputs:
- conventions.sources.json
- upstream sources listed above

Behavior:
- Fetch all sources
- Normalize content
- Compute sha256 fingerprints
- If fingerprints unchanged:
  - Do NOT re-ingest
  - Proceed directly to enforcement
- If fingerprints changed:
  - Apply updates immediately (default)

### Step 2: Re-ingestion (only if changed)
Default: apply updates

Apply (default):
- Update conventions.rules.json
- Regenerate conventions.md
- Update conventions.sources.json fingerprints
- Write conventions.diff.md

Dry run mode (--dry-run):
- conventions.diff.md (new/changed/removed rules)
- summary of how many rules would change
- No repo changes

Precedence:
- Local overrides in conventions.rules.json win over upstream.
- New upstream rules are added with default severity + enforcement mapping.

### Step 3: Enforce conventions against codebase
Always runs after compare (and after apply when changes were made).

Pipeline:
1) Formatting: forge fmt --check
2) Lint/static analysis: repo-standard tools (if configured)
3) Custom AST checks for rules not covered by tools:
   - private state vars
   - underscore prefix for internal/private
   - constants must use _SCREAMING_SNAKE_CASE (underscore prefix + all caps, e.g. _MAX_SUPPLY, not MAX_SUPPLY or maxSupply)
   - interface I-prefix
   - abstract non-standalone contracts
   - unchecked blocks must have justification comment
   - custom error naming guidance
   - function virtual rule (with exceptions, if enabled)

Output:
- conventions.report.md with "Confirmed findings"
Each finding includes:
- Severity (ERROR/WARN/INFO)
- Rule ID + title
- File:line
- Code snippet
- Fix recommendation

---

## Artifact Paths

All convention artifacts live in `.claude/skills/solidity_check_conventions/` (co-located with this skill):
- `.claude/skills/solidity_check_conventions/conventions.md`
- `.claude/skills/solidity_check_conventions/conventions.rules.json`
- `.claude/skills/solidity_check_conventions/conventions.sources.json`
- `.claude/skills/solidity_check_conventions/conventions.diff.md` (only when upstream changed)

The enforcement report is written to the project root's `.claude/` directory:
- `.claude/conventions.report.md` (every run)

Always read `conventions.rules.json` and `conventions.sources.json` from `.claude/skills/solidity_check_conventions/` before running any steps. Do NOT create or look for these files in the project source directories (e.g., `foundry/`, `src/`).