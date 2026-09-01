<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { DSAlert, DSButton, DSTabs } from "@/src/design_system";
import FieldPalette from "./components/FieldPalette.vue";
import FieldCanvas from "./components/FieldCanvas.vue";
import FieldConfig from "./components/FieldConfig.vue";
import SectionConfig from "./components/SectionConfig.vue";
import TemplateEditor from "./components/TemplateEditor.vue";
import { useMappingOptions } from "./composables/useMappingOptions";
import { usePresetOptions } from "./composables/usePresetOptions";
import type { ApiForm, BuilderContext, FormField, FormSection, Widget } from "./types";
import {
  DATE_RANGE_WIDGETS,
  PRESET_OFFSET_WIDGETS,
  RANGE_WIDGETS,
  VALIDATION_FORMAT_WIDGETS,
  fieldFromApi,
  sectionFromApi,
  tokenPlaceholder,
} from "./types";

const props = defineProps<{ context: BuilderContext; initialForm: ApiForm | null }>();

// Hydrated from JSON the ERB view embeds (see edit.html.erb) — without this
// the canvas always starts blank on load or refresh, regardless of what is
// already saved, because there is no other path that tells the Vue app what
// already exists in the database.
const fields = ref<FormField[]>(props.initialForm?.fields.map(fieldFromApi) ?? []);
const sections = ref<FormSection[]>(props.initialForm?.sections?.map(sectionFromApi) ?? []);
const selectedToken = ref<string | null>(null);
// PRD M11. The config panel shows EITHER a field's settings or a section's,
// so selection has to say which kind is selected, not just which token.
const selectedSectionId = ref<number | string | null>(null);
const subjectTemplate = ref(props.initialForm?.subject_template ?? "");
const descriptionTemplate = ref(props.initialForm?.description_template ?? "");
const activeTab = ref("fields");
const saving = ref(false);
const saveError = ref<string | null>(null);
const savedJustNow = ref(false);

// Rails' accepts_nested_attributes_for only deletes a child record when it
// is explicitly present in fields_attributes with _destroy set — simply
// leaving a persisted field out of the array (which is all removeField did
// on its own) saves successfully and silently leaves it untouched in the
// database. Ids collected here get an explicit `_destroy: true` entry in
// the next save() call.
const pendingDestroyIds = ref<number[]>([]);
// Same reasoning for sections. Only real (numeric) ids need a _destroy entry —
// a section that never reached the server can simply be dropped.
const pendingSectionDestroyIds = ref<number[]>([]);

const { options, loading, load } = useMappingOptions(props.context);
const { options: presetOptions, loading: presetOptionsLoading, load: loadPresetOptions } =
  usePresetOptions(props.context);

// PRD M11. A section's rule value comes from the SAME endpoint as an M8
// preset value — both answer "what can this field legally hold?", so a second
// composable instance is all that's needed, not a second endpoint.
const {
  options: visibilityValueOptions,
  operators: visibilityOperatorOptions,
  filterType: visibilityFilterType,
  loading: visibilityValueOptionsLoading,
  load: loadVisibilityValueOptions,
} = usePresetOptions(props.context);

const selectedField = computed(
  () => fields.value.find((f) => f.token === selectedToken.value) ?? null
);

const selectedSection = computed(
  () => sections.value.find((s) => s.id === selectedSectionId.value) ?? null
);

const unmappedCount = computed(
  () => fields.value.filter((f) => !f.mappedAttribute && !f.customFieldId).length
);

const tabs = [
  { label: "Fields", value: "fields" },
  { label: "Subject & description", value: "templates" },
];

watch(selectedField, (field) => {
  if (!field) return;

  void load(field.widget);
  // Keyed by the whole mapping, not just widget — see usePresetOptions.
  // Cache-backed, so this is cheap even though it re-fires on every keystroke
  // (updateField replaces the field with a new object on any change).
  void loadPresetOptions(field);
});

// PRD M11. The rule's legal values depend on which field the rule reads, so
// they reload whenever that choice changes. Cache-backed like the preset
// options, so re-firing on unrelated edits to the section costs nothing.
watch(
  () => selectedSection.value?.visibilityFieldId ?? null,
  (fieldId) => {
    const field = fields.value.find((f) => f.id === fieldId);
    if (field) void loadVisibilityValueOptions(field);
  },
  { immediate: true }
);

// `excludeToken` lets a field's own current token be re-derived without
// colliding with itself — needed for the rename case below, not just for a
// brand-new field (which isn't in `fields.value` yet either way).
function tokenFor(label: string, excludeToken: string | null = null): string {
  const base = label.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "") || "field";
  let candidate = base;
  let n = 1;
  while (fields.value.some((f) => f.token === candidate && f.token !== excludeToken)) {
    n += 1;
    candidate = `${base}_${n}`;
  }
  return candidate;
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// Every "{{ token }}" occurrence in a template, tolerant of the same
// whitespace padding TemplateCompiler accepts server-side. The brace
// delimiters bound the match exactly, so a token that happens to be a
// substring of another (e.g. "email" inside "email_address") can't match
// by accident — nothing but the token's own characters is allowed between
// the braces.
function tokenPattern(token: string): RegExp {
  return new RegExp(`\\{\\{\\s*${escapeRegExp(token)}\\s*\\}\\}`, "g");
}

// Rewrites every occurrence of oldToken to the new token — used when a
// field is renamed (its token changes to match).
function renameTokenInTemplate(template: string, oldToken: string, newToken: string): string {
  return template.replace(tokenPattern(oldToken), tokenPlaceholder(newToken));
}

// Strips every occurrence of a token entirely — used when its field is
// removed. Left behind otherwise: TemplateCompiler raises UnknownToken for
// any template referencing a field that no longer exists, so a deleted
// field's dangling "{{ token }}" doesn't just look stale, it breaks every
// future submission of the form until someone notices and edits it out by
// hand. Surrounding literal text (e.g. a "Platform: " label) is left as-is
// — only the placeholder itself is removed, matching the rename behavior.
function removeTokenFromTemplate(template: string, token: string): string {
  return template.replace(tokenPattern(token), "");
}

// Any further edit invalidates the "Saved." banner from a previous save —
// otherwise it would keep claiming changes are saved that aren't yet.
function markDirty(): void {
  savedJustNow.value = false;
}

function addField(widget: Widget): void {
  markDirty();

  const label = "Untitled field";
  const field: FormField = {
    position: fields.value.length + 1,
    label,
    helpText: null,
    token: tokenFor(label),
    widget,
    required: false,
    mappedAttribute: null,
    customFieldId: null,
    validationFormat: null,
    minValue: null,
    maxValue: null,
    minDate: null,
    maxDate: null,
    minDateOffsetDays: null,
    maxDateOffsetDays: null,
    hidden: false,
    presetValue: null,
    presetOffsetDays: null,
    // A new field joins whichever section is currently selected, so "select
    // a section, add fields to it" works without any drag-and-drop. With no
    // section selected it lands at the top level, which is what every form
    // built before M11 consists of entirely.
    sectionId: selectedSectionId.value,
  };

  fields.value.push(field);
  selectField(field.token);
}

// PRD M11. A brand-new section has no real id until it is saved, so it
// carries a temporary key that fields can reference in the meantime; the
// controller swaps in the real id server-side.
let tempSectionCounter = 0;

function addSection(): void {
  markDirty();

  const name = "Untitled section";
  const section: FormSection = {
    id: `new-${(tempSectionCounter += 1)}`,
    position: sections.value.length + 1,
    name,
    token: sectionTokenFor(name),
    visibilityFieldId: null,
    visibilityOperator: null,
    visibilityValues: [],
  };

  sections.value.push(section);
  selectSection(section.id);
}

// Sections and fields share one token namespace only in the sense that each
// must be unique among its own kind — the template distinguishes them by the
// {{#...}} vs {{ ... }} shape, so a section and a field may share a name.
function sectionTokenFor(name: string, excludeId: number | string | null = null): string {
  const base = name.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "") || "section";
  let candidate = base;
  let n = 1;
  while (sections.value.some((s) => s.token === candidate && s.id !== excludeId)) {
    n += 1;
    candidate = `${base}_${n}`;
  }
  return candidate;
}

function selectField(token: string): void {
  selectedToken.value = token;
  selectedSectionId.value = null;
}

function selectSection(id: number | string): void {
  selectedSectionId.value = id;
  selectedToken.value = null;
}

function updateSection(updated: FormSection): void {
  markDirty();

  const index = sections.value.findIndex((s) => s.id === updated.id);
  if (index === -1) return;

  const previous = sections.value[index];

  // The token tracks the name, exactly as a field's token tracks its label —
  // and for the same reason: a section renamed from "Untitled section" would
  // otherwise stay {{#untitled_section}} in the template forever.
  if (updated.name !== previous.name) {
    const regenerated = sectionTokenFor(updated.name, updated.id);

    if (regenerated !== previous.token) {
      subjectTemplate.value = renameSectionInTemplate(subjectTemplate.value, previous.token, regenerated);
      descriptionTemplate.value = renameSectionInTemplate(
        descriptionTemplate.value, previous.token, regenerated
      );
      updated = { ...updated, token: regenerated };
    }
  }

  sections.value[index] = updated;
}

// Deleting a section deletes its member fields with it (confirmed product
// decision, and what the model does server-side) — so their tokens have to
// come out of the templates too, the same cleanup removeField already does
// for a single field.
function removeSection(section: FormSection): void {
  markDirty();

  if (typeof section.id === "number") pendingSectionDestroyIds.value.push(section.id);

  fields.value
    .filter((f) => f.sectionId === section.id)
    .forEach((f) => {
      if (f.id != null) pendingDestroyIds.value.push(f.id);
      subjectTemplate.value = removeTokenFromTemplate(subjectTemplate.value, f.token);
      descriptionTemplate.value = removeTokenFromTemplate(descriptionTemplate.value, f.token);
    });

  fields.value = fields.value.filter((f) => f.sectionId !== section.id);
  sections.value = sections.value.filter((s) => s.id !== section.id);

  subjectTemplate.value = removeSectionFromTemplate(subjectTemplate.value, section.token);
  descriptionTemplate.value = removeSectionFromTemplate(descriptionTemplate.value, section.token);

  if (selectedSectionId.value === section.id) selectedSectionId.value = null;
}

function sectionBlockPattern(token: string): RegExp {
  return new RegExp(`\\{\\{#\\s*${escapeRegExp(token)}\\s*\\}\\}([\\s\\S]*?)\\{\\{/\\s*${escapeRegExp(token)}\\s*\\}\\}`, "g");
}

function renameSectionInTemplate(template: string, oldToken: string, newToken: string): string {
  return template.replace(
    sectionBlockPattern(oldToken),
    (_match, inner: string) => `{{#${newToken}}}${inner}{{/${newToken}}}`
  );
}

// Removes the markers but KEEPS the block's text — the section is gone, so
// its content is now unconditional rather than something to silently delete
// along with whatever the author wrote around it.
function removeSectionFromTemplate(template: string, token: string): string {
  return template.replace(sectionBlockPattern(token), (_match, inner: string) => inner);
}

// Appends a field's token to a template if it isn't already referenced
// there — used to prefill Subject/Description when a field is mapped
// straight to one of them, so the author doesn't have to remember the
// field's token and hand-type "{{ token }}" themselves.
function withTokenPrefilled(template: string, token: string): string {
  const placeholder = tokenPlaceholder(token);
  if (template.includes(placeholder)) return template;

  return template.length ? `${template} ${placeholder}` : placeholder;
}

function updateField(updated: FormField): void {
  markDirty();

  const index = fields.value.findIndex((f) => f.token === selectedToken.value);
  if (index === -1) return;

  const previous = fields.value[index];

  // The token tracks the label, not something authored independently — a
  // field renamed from "Untitled field" to "Employee ID" would otherwise
  // keep showing as {{ untitled_field_3 }} everywhere forever, which stops
  // meaning anything once a form has more than a couple of fields. Any
  // template that already referenced the old token is rewritten to match,
  // so a rename never silently breaks the subject/description output.
  if (updated.label !== previous.label) {
    const regeneratedToken = tokenFor(updated.label, previous.token);

    if (regeneratedToken !== previous.token) {
      subjectTemplate.value = renameTokenInTemplate(subjectTemplate.value, previous.token, regeneratedToken);
      descriptionTemplate.value = renameTokenInTemplate(
        descriptionTemplate.value,
        previous.token,
        regeneratedToken
      );
      updated = { ...updated, token: regeneratedToken };
    }
  }

  // Only on the transition INTO subject/description — not on every edit of
  // an already-mapped field, or the token would keep re-appending.
  if (updated.mappedAttribute === "subject" && previous.mappedAttribute !== "subject") {
    subjectTemplate.value = withTokenPrefilled(subjectTemplate.value, updated.token);
  }
  if (updated.mappedAttribute === "description" && previous.mappedAttribute !== "description") {
    descriptionTemplate.value = withTokenPrefilled(descriptionTemplate.value, updated.token);
  }

  fields.value[index] = updated;
  selectedToken.value = updated.token;
}

function removeField(field: FormField): void {
  markDirty();

  // A field that was already saved needs an explicit _destroy on the next
  // save — one that only ever existed client-side can simply be dropped.
  if (field.id != null) pendingDestroyIds.value.push(field.id);

  // Clear the field's own token out of both templates — otherwise it's
  // left behind as a dangling reference nothing on the form provides
  // anymore (see removeTokenFromTemplate).
  subjectTemplate.value = removeTokenFromTemplate(subjectTemplate.value, field.token);
  descriptionTemplate.value = removeTokenFromTemplate(descriptionTemplate.value, field.token);

  fields.value = fields.value.filter((f) => f.token !== field.token);
  if (selectedToken.value === field.token) selectedToken.value = null;
}

function updateSubjectTemplate(value: string): void {
  markDirty();
  subjectTemplate.value = value;
}

function updateDescriptionTemplate(value: string): void {
  markDirty();
  descriptionTemplate.value = value;
}

function csrfToken(): string {
  return document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? "";
}

// FormField#preset_value_list is the model's single source of truth for how
// a multi_select preset is stored (newline-joined in one text column, the
// same idiom core uses for CustomField#possible_values=) — mirrored here so
// the payload this sends is exactly what the model would itself produce, not
// a second encoding that could drift from it.
function presetValueForSave(field: FormField): string | null {
  if (field.widget === "multi_select") {
    return Array.isArray(field.presetValue) && field.presetValue.length ? field.presetValue.join("\n") : null;
  }

  return typeof field.presetValue === "string" ? field.presetValue : null;
}

async function save(): Promise<void> {
  saving.value = true;
  saveError.value = null;
  savedJustNow.value = false;

  try {
    const response = await fetch(`/form-designer/forms/${props.context.formId}`, {
      method: "PATCH",
      credentials: "same-origin",
      // The controller answers this exact request with JSON directly, with
      // no redirect — deliberately. fetch() follows a same-origin redirect
      // automatically, and per the Fetch spec only downgrades POST to GET
      // on 301/302/303; a PATCH stays a PATCH. Redirecting to the (GET-only)
      // edit page would make the browser silently retry this same PATCH
      // against it and 404 — reporting a spurious failure for a save that
      // had already succeeded server-side.
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": csrfToken(),
      },
      body: JSON.stringify({
        easy_form_designer_form: {
          subject_template: subjectTemplate.value,
          description_template: descriptionTemplate.value,
          fields_attributes: [
            ...fields.value.map((f, i) => ({
              id: f.id,
              position: i + 1,
              label: f.label,
              help_text: f.helpText,
              token: f.token,
              widget: f.widget,
              required: f.required,
              mapped_attribute: f.mappedAttribute,
              custom_field_id: f.customFieldId,
              // Cleared for widgets that don't accept them, matching
              // FormField#validation_format_matches_widget / #range_matches_widget
              // exactly. The config panel already only offers a rule on a
              // supporting widget, so this is belt-and-braces — it keeps the
              // payload valid against the model rather than relying on the UI
              // being the only thing that ever builds it.
              validation_format: VALIDATION_FORMAT_WIDGETS.includes(f.widget)
                ? f.validationFormat
                : null,
              min_value: RANGE_WIDGETS.includes(f.widget) ? f.minValue : null,
              max_value: RANGE_WIDGETS.includes(f.widget) ? f.maxValue : null,
              min_date: DATE_RANGE_WIDGETS.includes(f.widget) ? f.minDate : null,
              max_date: DATE_RANGE_WIDGETS.includes(f.widget) ? f.maxDate : null,
              min_date_offset_days: DATE_RANGE_WIDGETS.includes(f.widget) ? f.minDateOffsetDays : null,
              max_date_offset_days: DATE_RANGE_WIDGETS.includes(f.widget) ? f.maxDateOffsetDays : null,
              // PRD M8. hidden applies to every widget. preset_offset_days is
              // cleared the same way the date-bound offsets above are, for a
              // widget that doesn't support it. preset_value is normalised to
              // the single scalar column FormField actually stores — a
              // multi_select preset is an array client-side (see
              // usePresetOptions/FieldConfig) but a newline-joined string on
              // the wire and in the database, matching #preset_value_list.
              hidden: f.hidden,
              preset_value: presetValueForSave(f),
              preset_offset_days: PRESET_OFFSET_WIDGETS.includes(f.widget) ? f.presetOffsetDays : null,
              // A temp key here is resolved to the real id server-side once
              // the sections below have been saved.
              section_id: f.sectionId,
            })),
            ...pendingDestroyIds.value.map((id) => ({ id, _destroy: true })),
          ],
          sections_attributes: [
            ...sections.value.map((s, i) => ({
              // A saved section sends its real id; a new one sends only
              // temp_key, which the controller strips before assigning.
              id: typeof s.id === "number" ? s.id : undefined,
              temp_key: typeof s.id === "string" ? s.id : undefined,
              position: i + 1,
              name: s.name,
              token: s.token,
              visibility_field_id: s.visibilityFieldId,
              visibility_operator: s.visibilityOperator,
              // The model JSON-encodes these into the column.
              visibility_values: s.visibilityValues,
            })),
            ...pendingSectionDestroyIds.value.map((id) => ({ id, _destroy: true })),
          ],
        },
      }),
    });

    if (!response.ok) {
      const body = await response.json().catch(() => null);
      throw new Error(body?.errors?.join(", ") || `HTTP ${response.status}`);
    }

    // Re-sync from the server's own view of what was just saved — picks up
    // real ids for newly created fields and sections — rather than a full
    // page reload. For sections this is what retires their temporary keys:
    // any field that referenced one now carries the real id the server
    // resolved it to.
    const saved = (await response.json()) as ApiForm;
    fields.value = saved.fields.map(fieldFromApi);
    sections.value = saved.sections?.map(sectionFromApi) ?? [];
    subjectTemplate.value = saved.subject_template ?? "";
    descriptionTemplate.value = saved.description_template ?? "";
    pendingDestroyIds.value = [];
    pendingSectionDestroyIds.value = [];
    // A selection pointing at a temp key no longer resolves after the swap.
    if (typeof selectedSectionId.value === "string") selectedSectionId.value = null;
    savedJustNow.value = true;
  } catch (e) {
    saveError.value = e instanceof Error ? e.message : String(e);
  } finally {
    saving.value = false;
  }
}
</script>

<template>
  <div class="efd-builder">
    <DSTabs v-model="activeTab" :items="tabs" />

    <DSAlert
      v-if="unmappedCount"
      variant="warning"
      :body="`${unmappedCount} field(s) are not mapped to a task attribute. The form cannot be published until every field is mapped.`"
    />
    <DSAlert v-if="saveError" variant="error" :body="saveError" />
    <DSAlert v-if="savedJustNow" variant="success" body="Saved." />

    <div v-if="activeTab === 'fields'" class="efd-builder__panels">
      <FieldPalette @add="addField" @add-section="addSection" />

      <FieldCanvas
        :fields="fields"
        :sections="sections"
        :selected-token="selectedToken"
        :selected-section-id="selectedSectionId"
        @select="(f: FormField) => selectField(f.token)"
        @remove="removeField"
        @select-section="(s: FormSection) => selectSection(s.id)"
        @remove-section="removeSection"
      />

      <!-- PRD M11. The right-hand panel shows whichever of the two kinds is
           selected — a section's own settings live in their own component
           rather than growing FieldConfig, which eslint's max-lines already
           flags. -->
      <SectionConfig
        v-if="selectedSection"
        :section="selectedSection"
        :fields="fields"
        :value-options="visibilityValueOptions"
        :operator-options="visibilityOperatorOptions"
        :filter-type="visibilityFilterType"
        :options-loading="visibilityValueOptionsLoading"
        @update="updateSection"
      />
      <FieldConfig
        v-else
        :field="selectedField"
        :options="options"
        :loading="loading"
        :preset-options="presetOptions"
        :preset-options-loading="presetOptionsLoading"
        :sections="sections"
        @update="updateField"
      />
    </div>

    <TemplateEditor
      v-else
      :subject-template="subjectTemplate"
      :description-template="descriptionTemplate"
      :fields="fields"
      @update:subject-template="updateSubjectTemplate"
      @update:description-template="updateDescriptionTemplate"
    />

    <footer class="efd-builder__footer">
      <DSButton variant="primary" :disabled="saving" @click="save">
        {{ saving ? "Saving…" : "Save" }}
      </DSButton>
    </footer>
  </div>
</template>

<style scoped lang="scss">
.efd-builder {
  display: flex;
  flex-direction: column;
  gap: var(--Scale-Size-4, 16px);

  &__panels {
    display: grid;
    grid-template-columns: 180px 1fr 280px;
    gap: var(--Scale-Size-4, 16px);
    align-items: start;
  }

  &__footer {
    display: flex;
    justify-content: flex-end;
  }
}

// PRD M12 — the builder is admin-side, but it still must not break the page.
@media (max-width: 900px) {
  .efd-builder__panels {
    grid-template-columns: 1fr;
  }
}
</style>
