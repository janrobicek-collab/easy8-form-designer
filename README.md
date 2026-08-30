# easy8-form-designer

Custom Forms Engine for Easy8 — a no-code form builder that compiles each
submission into a correctly-fielded Easy8 task.

Implements the engine half of PRD
[#687043](https://es.easy8.com/issues/687043). The Service Portal Widget (the
visual catalog that links *to* these forms) is a separate project.

## The design rule everything hangs on

Every visible form field maps to a real Easy8 task attribute — a native issue
attribute, or a custom field valid for the form's project **and** tracker. There
are no unlinked "form-only" fields.

This is enforced structurally rather than by validation alone: choice options
are read from the *mapped attribute* (`custom_field.possible_values`,
`IssuePriority.active`), never authored on the field. An unmapped field
therefore has nothing to render, and publishing is blocked while any field is
unmapped.

## Layout

```
repo/
├── easy_form_designer/        # the rys engine — models, services, controllers, views, specs
├── frontend/
│   ├── easy_form_designer/    # builder Vue app  → overlays app/frontend/src/
│   └── entrypoints/           # Vite entrypoint  → overlays app/frontend/entrypoints/
├── CORE_CHANGES.md            # the four things that must live outside the engine
└── easy8_source_code/         # local Easy8 checkout (gitignored, not part of this repo)
```

## Pipeline

| Service | Responsibility |
|---|---|
| `AvailableAttributes` | What a field may map to, for one project + tracker pair. Custom fields are the **intersection** of `IssueCustomField`, `project.all_issue_custom_fields` and `tracker.custom_fields` — trusting either list alone is wrong. Also enforces widget↔format compatibility. |
| `TemplateCompiler` | Resolves `{{ token }}` in the subject and description templates. An unknown token raises rather than silently blanking. |
| `IssueBuilder` | Creates the task. Assigns project and tracker **before** any custom value (Redmine defect #19368 drops them otherwise) and uses the `custom_field_values=` hash form. Transactional with the submission record. |

## Status

Pre-release, behind the `:easy_form_designer_enabled` feature flag. First slice
covers PRD M1, M3–M6, M9 and part of M2/M7 — four widget types
(text, long text, dropdown, date). Deferred to the next slice: the remaining six
field types, URL/number-range validation, hidden/preset fields, group access control.

## Development

See `CORE_CHANGES.md` for the overlay symlinks. Run specs with:

```bash
bundle exec rspec easy_engines/easy_form_designer/spec
```
