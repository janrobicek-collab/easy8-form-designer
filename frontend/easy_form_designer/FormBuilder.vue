<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { DSAlert, DSButton, DSTabs } from "@/src/design_system";
import FieldPalette from "./components/FieldPalette.vue";
import FieldCanvas from "./components/FieldCanvas.vue";
import FieldConfig from "./components/FieldConfig.vue";
import TemplateEditor from "./components/TemplateEditor.vue";
import { useMappingOptions } from "./composables/useMappingOptions";
import type { ApiForm, BuilderContext, FormField, Widget } from "./types";
import { fieldFromApi, tokenPlaceholder } from "./types";

const props = defineProps<{ context: BuilderContext; initialForm: ApiForm | null }>();

// Hydrated from JSON the ERB view embeds (see edit.html.erb) — without this
// the canvas always starts blank on load or refresh, regardless of what is
// already saved, because there is no other path that tells the Vue app what
// already exists in the database.
const fields = ref<FormField[]>(props.initialForm?.fields.map(fieldFromApi) ?? []);
const selectedToken = ref<string | null>(null);
const subjectTemplate = ref(props.initialForm?.subject_template ?? "");
const descriptionTemplate = ref(props.initialForm?.description_template ?? "");
const activeTab = ref("fields");
const saving = ref(false);
const saveError = ref<string | null>(null);
const savedJustNow = ref(false);

const { options, loading, load } = useMappingOptions(props.context);

const selectedField = computed(
  () => fields.value.find((f) => f.token === selectedToken.value) ?? null
);

const unmappedCount = computed(
  () => fields.value.filter((f) => !f.mappedAttribute && !f.customFieldId).length
);

const tabs = [
  { label: "Fields", value: "fields" },
  { label: "Subject & description", value: "templates" },
];

watch(selectedField, (field) => {
  if (field) void load(field.widget);
});

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

// Rewrites every "{{ oldToken }}" in a template to the new token, tolerant
// of the same whitespace padding TemplateCompiler accepts server-side.
function renameTokenInTemplate(template: string, oldToken: string, newToken: string): string {
  const pattern = new RegExp(`\\{\\{\\s*${escapeRegExp(oldToken)}\\s*\\}\\}`, "g");
  return template.replace(pattern, tokenPlaceholder(newToken));
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
  };

  fields.value.push(field);
  selectedToken.value = field.token;
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
          fields_attributes: fields.value.map((f, i) => ({
            id: f.id,
            position: i + 1,
            label: f.label,
            help_text: f.helpText,
            token: f.token,
            widget: f.widget,
            required: f.required,
            mapped_attribute: f.mappedAttribute,
            custom_field_id: f.customFieldId,
          })),
        },
      }),
    });

    if (!response.ok) {
      const body = await response.json().catch(() => null);
      throw new Error(body?.errors?.join(", ") || `HTTP ${response.status}`);
    }

    // Re-sync from the server's own view of what was just saved — picks up
    // real ids for newly created fields — rather than a full page reload.
    const saved = (await response.json()) as ApiForm;
    fields.value = saved.fields.map(fieldFromApi);
    subjectTemplate.value = saved.subject_template ?? "";
    descriptionTemplate.value = saved.description_template ?? "";
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
      <FieldPalette @add="addField" />

      <FieldCanvas
        :fields="fields"
        :selected-token="selectedToken"
        @select="(f: FormField) => (selectedToken = f.token)"
        @remove="removeField"
      />

      <FieldConfig
        :field="selectedField"
        :options="options"
        :loading="loading"
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
