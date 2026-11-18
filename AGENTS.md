# Git Commit Guidelines for Coding Agents

When creating Git commits in this repository, strictly follow these staging and formatting rules to maintain a clean, readable history.

## 1. Workflow & Staging
* **Atomic Commits:** Group changes into single-purpose, logical units. Never bundle unrelated features, bug fixes, or refactors into one commit.
* **Selective Staging:** Inspect changes with `git status` and `git diff` before staging. Stage specific files or hunks (`git add <file>`) rather than blindly running `git add .`.
* **Pre-Commit Verification:** Run `git diff --staged` and execute relevant linters or tests before committing. Ensure no debug artifacts, temporary files, or secrets/API keys are staged.

## 2. Commit Message Format
Adhere to the **Conventional Commits** specification combined with the **50/72 formatting rule**:

```text
<type>(<optional scope>): <imperative description>

[optional body wrapped at 72 characters]

[optional footer(s)]
```

### Allowed Types
* `feat`: A new feature or capability
* `fix`: A bug fix
* `refactor`: Code restructuring without changing external behavior
* `docs`: Documentation updates only
* `test`: Adding or updating tests
* `chore`: Build scripts, dependencies, or routine maintenance

### Style Rules
* **Subject Line:** Keep under **50 characters**, use the **imperative mood** (e.g., `add`, `fix`, `update`—not `added` or `fixes`), and omit any trailing period.
* **Scope:** Include a short noun in parentheses when helpful to clarify the affected module (e.g., `fix(api): handle timeout errors`).
* **Body:** Separate from the subject with one blank line. Wrap lines at **72 characters**. Focus on *what* changed and *why*, not line-by-line implementation details.
* **Footers:** Reference related issues (e.g., `Refs #42`) or explicitly denote incompatible updates starting with `BREAKING CHANGE:`.
