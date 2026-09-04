# Core changes required by this engine

Everything the Form Designer needs lives in `easy_form_designer/` **except** the
items below. They sit in Easy8 core because no Easy8 engine or plugin ships its
own `app/frontend/` — `easy_automations`, the closest analog, has exactly the
same split.

This is an acknowledged exception to the extension-first policy in the root
`AGENTS.md`, which asks for a tradeoff note when core is touched:

> **Why not in the engine:** Vite resolves entrypoints from
> `app/frontend/entrypoints/` and modules from `app/frontend/src/` in the host
> app only. An engine cannot contribute to either. Placing the builder's Vue in
> the engine would mean adding engine paths to the Vite config — a deeper and
> more fragile core change than the three additive edits below.
>
> **Risk:** low. All three are additive; none modifies existing behaviour.

| # | Core file | Change |
|---|---|---|
| 1 | `app/frontend/src/easy_form_designer/` | New directory — the builder's Vue source. Tracked here at `repo/frontend/easy_form_designer/`. |
| 2 | `app/frontend/entrypoints/easy_form_designer.ts` | New Vite entrypoint exposing `window.EasyFormDesigner.createBuilderApp`. Tracked here at `repo/frontend/entrypoints/`. |
| 3 | `app/frontend/src/shared/types/global.d.ts` | One added line — `EasyFormDesigner: UnknownObject;` directly after the existing `EasyAutomations` line. |
| 4 | `easy_engines/Gemfile` | One added line — `gem "easy_form_designer", path: "./easy_form_designer"`. |
| 5 | `app/frontend/entrypoints/application.js` | One added line — `import "./easy_form_designer";`, next to the existing `import "./automation";`. Discovered by testing: entrypoints aren't wired into a page by their own view — `application.js` is loaded on every page via the base layout and statically imports every feature's entrypoint so its `window.*` global exists everywhere. |
| 6 | `playwright/pages/easy_form_designer/`, `playwright/tests/easy_form_designer/` | New directories — the REQ-19 smoke tests. Same rationale as items 1–2: `playwright/` is the host app's own E2E suite (`testDir: "./tests"` in the root `playwright.config.ts`), not something an engine can contribute a subtree to. Tracked here at `repo/playwright/`. |

## Local development

`repo/` is the git-tracked source of truth. `repo/sync_overlay.sh` copies it
into a WSL-native checkout of Easy8 (deliberately a copy, not a symlink — see
that script's own comment on why a symlink onto `/mnt/c` is too slow for
Rails' constant path scanning):

```
easy_engines/easy_form_designer                -> repo/easy_form_designer
app/frontend/src/easy_form_designer            -> repo/frontend/easy_form_designer
app/frontend/entrypoints/easy_form_designer.ts -> repo/frontend/entrypoints/easy_form_designer.ts
playwright/pages/easy_form_designer            -> repo/playwright/pages/easy_form_designer
playwright/tests/easy_form_designer            -> repo/playwright/tests/easy_form_designer
```

Items 3 and 4 are edits to existing core files and must be applied by hand.
