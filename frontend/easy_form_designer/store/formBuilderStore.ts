import { defineStore } from "pinia";
import { computed, readonly, ref } from "vue";
import type { ApiForm, BuilderContext, FormField, FormSection, Widget } from "../types";
import { DEFAULT_WIDGET, sectionsFromApi } from "../types";
import { buildFieldsAttributes, buildSectionsAttributes } from "../utils/formPayload";
import {
  removeSectionTokenFromTemplate,
  removeTokenFromTemplate,
  renameSectionTokenInTemplate,
  renameTokenInTemplate,
  sectionTokenFor,
  tokenFor,
  withTokenPrefilled,
} from "../utils/templateTokens";

// REQ-16/REQ-17. Sections OWN their fields directly — a section's `fields`
// array is the single source of truth for membership, which is what lets
// vuedraggable move a field between sections as a plain array splice with
// nothing else to keep in sync afterward. Replaces FormBuilder.vue's local
// refs entirely, so the deeply-nested Section → Field → Advanced component
// tree isn't prop/emit-drilling the whole form through five layers.
export const useFormBuilderStore = defineStore("easyFormDesignerBuilder", () => {
  const sections = ref<FormSection[]>([]);
  const subjectTemplate = ref("");
  const descriptionTemplate = ref("");
  const saving = ref(false);
  const saveError = ref<string | null>(null);
  const savedJustNow = ref(false);

  // Rails' accepts_nested_attributes_for only deletes a child record when it
  // is explicitly present in fields_attributes/sections_attributes with
  // _destroy set — simply dropping a persisted row from the array saves
  // successfully and silently leaves it untouched in the database. Ids
  // collected here get an explicit `_destroy: true` entry in the next save().
  const pendingDestroyIds = ref<number[]>([]);
  const pendingSectionDestroyIds = ref<number[]>([]);

  let tempSectionCounter = 0;

  const allFields = computed<FormField[]>(() => sections.value.flatMap((s) => s.fields));
  const unmappedCount = computed(
    () => allFields.value.filter((f) => !f.mappedAttribute && !f.customFieldId).length
  );
  // A field can only ever be added inside an existing section (see FieldList's
  // "+ Add field"), so the invariant every field needs — REQ-16 — depends on
  // there always being at least one to add it to.
  const canRemoveSection = computed(() => sections.value.length > 1);

  function initialize(initialForm: ApiForm | null): void {
    if (!initialForm) return;

    sections.value = sectionsFromApi(initialForm);
    subjectTemplate.value = initialForm.subject_template ?? "";
    descriptionTemplate.value = initialForm.description_template ?? "";
  }

  // Any further edit invalidates the "Saved." banner from a previous save —
  // otherwise it would keep claiming changes are saved that aren't yet.
  function markDirty(): void {
    savedJustNow.value = false;
  }

  function addSection(): void {
    markDirty();

    const name = "Untitled section";
    const section: FormSection = {
      id: `new-${(tempSectionCounter += 1)}`,
      position: sections.value.length + 1,
      name,
      token: sectionTokenFor(sections.value.map((s) => s.token), name),
      visibilityFieldId: null,
      visibilityOperator: null,
      visibilityValues: [],
      fields: [],
      collapsed: false,
    };

    sections.value.push(section);
  }

  function removeSection(section: FormSection): void {
    if (!canRemoveSection.value) return;
    markDirty();

    if (typeof section.id === "number") pendingSectionDestroyIds.value.push(section.id);

    // Deleting a section deletes its member fields with it (confirmed
    // product decision, and what the model does server-side) — so their
    // tokens have to come out of the templates too.
    section.fields.forEach((f) => {
      if (f.id != null) pendingDestroyIds.value.push(f.id);
      stripFieldToken(f.token);
    });

    sections.value = sections.value.filter((s) => s.id !== section.id);
    subjectTemplate.value = removeSectionTokenFromTemplate(subjectTemplate.value, section.token);
    descriptionTemplate.value = removeSectionTokenFromTemplate(descriptionTemplate.value, section.token);
  }

  function stripFieldToken(token: string): void {
    subjectTemplate.value = removeTokenFromTemplate(subjectTemplate.value, token);
    descriptionTemplate.value = removeTokenFromTemplate(descriptionTemplate.value, token);
  }

  // The token tracks the name, exactly as a field's token tracks its label —
  // a section renamed from "Untitled section" would otherwise keep
  // referencing {{#untitled_section}} in the template forever.
  function withRenamedSectionToken(previous: FormSection, updated: FormSection): FormSection {
    if (updated.name === previous.name) return updated;

    const regenerated = sectionTokenFor(sections.value.map((s) => s.token), updated.name, previous.token);
    if (regenerated === previous.token) return updated;

    subjectTemplate.value = renameSectionTokenInTemplate(subjectTemplate.value, previous.token, regenerated);
    descriptionTemplate.value = renameSectionTokenInTemplate(descriptionTemplate.value, previous.token, regenerated);
    return { ...updated, token: regenerated };
  }

  function patchSection(section: FormSection, changes: Partial<FormSection>): void {
    markDirty();

    const index = sections.value.findIndex((s) => s.id === section.id);
    if (index === -1) return;

    sections.value[index] = withRenamedSectionToken(section, { ...section, ...changes });
  }

  function addField(section: FormSection, widget: Widget = DEFAULT_WIDGET): FormField {
    markDirty();

    const label = "Untitled field";
    const field: FormField = {
      position: section.fields.length + 1,
      label,
      helpText: null,
      token: tokenFor(allFields.value.map((f) => f.token), label),
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
    };

    section.fields.push(field);
    return field;
  }

  function removeField(section: FormSection, field: FormField): void {
    markDirty();

    if (field.id != null) pendingDestroyIds.value.push(field.id);
    stripFieldToken(field.token);

    section.fields = section.fields.filter((f) => f !== field);
  }

  // The token tracks the label — a field renamed from "Untitled field" to
  // "Employee ID" would otherwise keep showing as {{ untitled_field_3 }}
  // everywhere forever. Any template that already referenced the old token
  // is rewritten to match, so a rename never silently breaks the
  // subject/description output.
  function withRenamedFieldToken(previous: FormField, updated: FormField): FormField {
    if (updated.label === previous.label) return updated;

    const regeneratedToken = tokenFor(allFields.value.map((f) => f.token), updated.label, previous.token);
    if (regeneratedToken === previous.token) return updated;

    subjectTemplate.value = renameTokenInTemplate(subjectTemplate.value, previous.token, regeneratedToken);
    descriptionTemplate.value = renameTokenInTemplate(descriptionTemplate.value, previous.token, regeneratedToken);
    return { ...updated, token: regeneratedToken };
  }

  // Only on the transition INTO subject/description — not on every edit of
  // an already-mapped field, or the token would keep re-appending.
  function withMappingPrefill(previous: FormField, updated: FormField): FormField {
    if (updated.mappedAttribute === "subject" && previous.mappedAttribute !== "subject") {
      subjectTemplate.value = withTokenPrefilled(subjectTemplate.value, updated.token);
    }
    if (updated.mappedAttribute === "description" && previous.mappedAttribute !== "description") {
      descriptionTemplate.value = withTokenPrefilled(descriptionTemplate.value, updated.token);
    }
    return updated;
  }

  function patchField(field: FormField, changes: Partial<FormField>): void {
    markDirty();

    const section = sections.value.find((s) => s.fields.includes(field));
    if (!section) return;

    const index = section.fields.indexOf(field);
    const renamed = withRenamedFieldToken(field, { ...field, ...changes });
    section.fields[index] = withMappingPrefill(field, renamed);
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

  // The controller answers this exact request with JSON directly, with no
  // redirect. fetch() follows a same-origin redirect automatically and, per
  // the Fetch spec, preserves the method only for a PATCH — but a redirect
  // to the (GET-only) edit route would have the browser silently re-issue
  // this PATCH against it and 404.
  async function postForm(context: BuilderContext): Promise<Response> {
    return fetch(`/form-designer/forms/${context.formId}`, {
      method: "PATCH",
      credentials: "same-origin",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": csrfToken(),
      },
      body: JSON.stringify({
        easy_form_designer_form: {
          subject_template: subjectTemplate.value,
          description_template: descriptionTemplate.value,
          fields_attributes: buildFieldsAttributes(sections.value, pendingDestroyIds.value),
          sections_attributes: buildSectionsAttributes(sections.value, pendingSectionDestroyIds.value),
        },
      }),
    });
  }

  async function parseFormResponse(response: Response): Promise<ApiForm> {
    if (!response.ok) {
      const body = await response.json().catch(() => null);
      throw new Error(body?.errors?.join(", ") || `HTTP ${response.status}`);
    }

    return (await response.json()) as ApiForm;
  }

  // Re-syncs from the server's own view of what was just saved — picks up
  // real ids for newly created fields/sections — rather than a full page
  // reload. This is what retires a section's temporary key: any field that
  // referenced one now carries the real id the server resolved it to.
  function applySavedForm(saved: ApiForm): void {
    sections.value = sectionsFromApi(saved);
    subjectTemplate.value = saved.subject_template ?? "";
    descriptionTemplate.value = saved.description_template ?? "";
    pendingDestroyIds.value = [];
    pendingSectionDestroyIds.value = [];
    savedJustNow.value = true;
  }

  async function save(context: BuilderContext): Promise<void> {
    saving.value = true;
    saveError.value = null;
    savedJustNow.value = false;

    try {
      applySavedForm(await parseFormResponse(await postForm(context)));
    } catch (e) {
      saveError.value = e instanceof Error ? e.message : String(e);
    } finally {
      saving.value = false;
    }
  }

  return {
    sections,
    subjectTemplate,
    descriptionTemplate,
    saving: readonly(saving),
    saveError: readonly(saveError),
    savedJustNow: readonly(savedJustNow),
    allFields,
    unmappedCount,
    canRemoveSection,
    initialize,
    addSection,
    removeSection,
    patchSection,
    addField,
    removeField,
    patchField,
    updateSubjectTemplate,
    updateDescriptionTemplate,
    save,
  };
});
