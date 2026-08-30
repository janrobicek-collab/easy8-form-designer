# EasyFormDesigner

Custom Forms Engine for Easy8 — implements the form-builder half of PRD
[#687043](https://es.easy8.com/issues/687043).

A no-code builder where an administrator picks a target project + task type,
lays out fields, maps **every** field to a real Easy8 task attribute, and
authors subject/description templates. On submission the engine compiles a
standard Easy8 task with all answers written to the correct native and custom
fields.

## Design rule

Every visible form field maps to a real task attribute — a native field, or a
custom field scoped to the selected project *and* tracker. There are no
unlinked "form-only" fields. Choice options are read from the mapped attribute
rather than authored on the field, so an unmapped field cannot render at all.

## Layout

This engine follows the `easy_automations` structure. Note that the builder's
Vue source does **not** live here: no Easy8 engine ships its own `app/frontend/`,
so it lives in core at `app/frontend/src/easy_form_designer/` with its Vite
entrypoint in `app/frontend/entrypoints/`. Those files are mirrored in this
repository under `frontend/`.

## Status

Pre-release. Guarded end-to-end by the `:easy_form_designer_enabled` feature flag.
