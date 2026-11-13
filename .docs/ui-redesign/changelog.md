# Changelog

- 2026-11-12: Built the spike: 3 directions, 18 screenshots. The owner chose B.
- 2026-11-12: Spec written. A builder check raised 6 questions, all settled as defaults (see "Decided here").
- 2026-11-12: Phase 0–1 plan written.
- 2026-11-12: Phase 0 done (PR #118, awaiting owner OK). Phase 1 tasks 7-9 done on feature/ui-shell. Phases 2-6 plan written (17 tasks).
- 2026-11-12: Phase 1 (shell) done on feature/ui-shell.
- 2026-11-12: Phases 2-6 plan written and executed (phases 2-5 desktop, phase 6 mobile); Task 17 token sweep, lint gate and docs done.
- 2026-11-13: Final review fix round (P30): host editor remounts per edit target (data-loss fix), mail catcher skips the ESMTP options preamble, confirms for dashboard host Delete and Known Hosts Remove, terminal header and status bar follow host edits, proxy port range check, discovery and monitor sheets plus inline rename and fallback editor on forui, lint gate extended, `yourssh_web_tools` in the plugin CI matrix, watch banner cue restored, docs completed.
- 2026-11-13: Docs user-journey harness (app/integration_test/docs/) drove the final app against demo containers and captured 208 screenshots (untracked, screenshots/docs/). Its findings plus a controller review of every shot gave 22 fixes in 4 parallel worktrees (P31), incl. a pre-existing snippets data-loss bug from the half-migrated bundled JS Snippets plugin (P32). Journey re-run clean; README screenshots refreshed from it.
