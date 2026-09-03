# DECISIONS

Append-only. Every ADR and design choice, one line of rationale.

## 2026-09-03

- **Skills are repo-scoped, not global.** Copied the emilkowalski set + `frontend-design` into
  `.claude/skills/` rather than `~/.claude/skills/`. They were only present inside an unrelated
  project (`Interview_Helper/.agents/skills/`), so this session could not see them. Repo-local keeps
  them versioned with the project and mutates nothing global.
- **graphify runs as one repo-wide graph, not per-directory.** `tree-sitter-swift` and
  `tree_sitter_python` are both in the installed extractor, and `.metal` is a recognized extension —
  a single map covers the Xcode target and the FastAPI service. Revisit only if cross-language noise
  makes queries worse.
