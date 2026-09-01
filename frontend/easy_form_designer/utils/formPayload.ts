import type { FormField, FormSection } from "../types";

// The PATCH body EasyFormDesignerFormsController#update expects. Pulled out
// of formBuilderStore.ts's save() as pure functions — nothing here reads
// reactive state — so that function stays a thin fetch/error-handling
// wrapper instead of also carrying the whole payload shape inline.

// FormField#preset_value_list is the model's single source of truth for how
// a multi_select preset is stored (newline-joined in one text column) —
// mirrored here so the payload sent is exactly what the model would itself
// produce, not a second encoding that could drift from it.
function presetValueForSave(field: FormField): string | null {
  if (field.widget === "multi_select") {
    return Array.isArray(field.presetValue) && field.presetValue.length
      ? field.presetValue.join("\n")
      : null;
  }

  return typeof field.presetValue === "string" ? field.presetValue : null;
}

function fieldAttributes(field: FormField, position: number, sectionId: number | string) {
  return {
    id: field.id,
    position,
    label: field.label,
    help_text: field.helpText,
    token: field.token,
    widget: field.widget,
    required: field.required,
    mapped_attribute: field.mappedAttribute,
    custom_field_id: field.customFieldId,
    validation_format: field.validationFormat,
    min_value: field.minValue,
    max_value: field.maxValue,
    min_date: field.minDate,
    max_date: field.maxDate,
    min_date_offset_days: field.minDateOffsetDays,
    max_date_offset_days: field.maxDateOffsetDays,
    hidden: field.hidden,
    preset_value: presetValueForSave(field),
    preset_offset_days: field.presetOffsetDays,
    // A temp key here is resolved to the real id server-side once the
    // sections below have been saved.
    section_id: sectionId,
  };
}

function sectionAttributes(section: FormSection, position: number) {
  return {
    // A saved section sends its real id; a new one sends only temp_key,
    // which the controller strips before assigning.
    id: typeof section.id === "number" ? section.id : undefined,
    temp_key: typeof section.id === "string" ? section.id : undefined,
    position,
    name: section.name,
    token: section.token,
    visibility_field_id: section.visibilityFieldId,
    visibility_operator: section.visibilityOperator,
    visibility_values: section.visibilityValues,
  };
}

export function buildFieldsAttributes(sections: FormSection[], pendingDestroyIds: number[]) {
  return [
    ...sections.flatMap((section) =>
      section.fields.map((field, i) => fieldAttributes(field, i + 1, section.id))
    ),
    ...pendingDestroyIds.map((id) => ({ id, _destroy: true })),
  ];
}

export function buildSectionsAttributes(sections: FormSection[], pendingSectionDestroyIds: number[]) {
  return [
    ...sections.map((section, i) => sectionAttributes(section, i + 1)),
    ...pendingSectionDestroyIds.map((id) => ({ id, _destroy: true })),
  ];
}
