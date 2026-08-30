<script setup lang="ts">
import { computed } from "vue";
import { DSSelect, DSSwitch, DSTextField } from "@/src/design_system";
import type { FormField, MappingOption } from "../types";

const props = defineProps<{
  field: FormField | null;
  options: MappingOption[];
  loading: boolean;
}>();

const emit = defineEmits<{ update: [field: FormField] }>();

// DSSelect's v-model is the selected OPTION OBJECT itself, matched by
// reference/value against the `options` array — not a plain string. Passing
// a string here (as an earlier version of this file did) makes the select
// silently unresponsive: nothing ever matches, and the object DSSelect emits
// back on @update:model-value has no .split() method, so the handler throws.
// A unique `value` per option is still needed for DSOptionList's internal
// selection bookkeeping, so it's kept as the same "type:rawValue" string;
// `type`/`rawValue` travel alongside it as plain extra keys on the option.
interface SelectOption {
  label: string;
  value: string;
  type: MappingOption["type"];
  rawValue: MappingOption["value"];
}

const selectOptions = computed<SelectOption[]>(() =>
  props.options.map((o) => ({
    label: o.label,
    value: `${o.type}:${o.value}`,
    type: o.type,
    rawValue: o.value,
  }))
);

const mappingValue = computed<SelectOption | null>(() => {
  if (!props.field) return null;

  return (
    selectOptions.value.find((o) =>
      props.field?.customFieldId
        ? o.type === "custom_field" && o.rawValue === props.field.customFieldId
        : o.type === "native" && o.rawValue === props.field?.mappedAttribute
    ) ?? null
  );
});

function patch(changes: Partial<FormField>): void {
  if (!props.field) return;
  emit("update", { ...props.field, ...changes });
}

function setMapping(option: SelectOption | null): void {
  patch({
    mappedAttribute: option?.type === "native" ? String(option.rawValue) : null,
    customFieldId: option?.type === "custom_field" ? Number(option.rawValue) : null,
  });
}

// Each widget maps to a semantically-matching native attribute only — a
// single-line Text field to Subject, a multi-line Long text field to
// Description, and so on — never both. Nothing else in the UI explains
// this, so a field author who only ever tries "Text" fields sees just
// "Subject" on offer and has no way to tell that's by design rather than
// a bug (reported exactly this way).
const widgetHint = computed<string | null>(() => {
  switch (props.field?.widget) {
    case "text":
      return "A Text field maps to Subject or a matching custom field. To map to Description, use a Long text field instead.";
    case "long_text":
      return "A Long text field maps to Description or a matching custom field.";
    case "select":
      return "A Dropdown field maps to Priority or a matching custom field.";
    case "date":
      return "A Date field maps to Due date, Start date, or a matching custom field.";
    case "number":
      return "A Number field maps to Estimated time or a matching custom field.";
    case "radio":
      return "A Radio buttons field maps to Priority or a matching custom field.";
    case "multi_select":
      return "A Multi-select field maps to a matching custom field only — no native attribute takes multiple values.";
    case "checkbox":
      return "A Checkbox field maps to a matching custom field only — no native attribute is boolean today.";
    case "user":
      return "A User lookup field maps to Assignee or a matching custom field.";
    default:
      return null;
  }
});
</script>

<template>
  <aside v-if="field" class="efd-config">
    <h3 class="efd-config__title">Field settings</h3>

    <DSTextField
      :model-value="field.label"
      label="Label"
      required
      @update:model-value="(v: string) => patch({ label: v })"
    />

    <DSTextField
      :model-value="field.helpText ?? ''"
      label="Help text"
      @update:model-value="(v: string) => patch({ helpText: v })"
    />

    <DSSwitch
      :model-value="field.required"
      name="required"
      label="Required"
      @update:model-value="(v: boolean) => patch({ required: v })"
    />

    <!-- Mandatory. A field with no mapping cannot be published, and its
         options would be empty anyway — the list comes from the mapped
         attribute, never from field-local config. -->
    <DSSelect
      name="mapped_attribute"
      :model-value="mappingValue"
      :options="selectOptions"
      :loading="loading"
      label="Maps to"
      required
      @update:model-value="(v) => setMapping(v as SelectOption | null)"
    />
    <p class="caption">
      Every field must write to a real task attribute.<template v-if="widgetHint"> {{ widgetHint }}</template>
    </p>

    <p v-if="!loading && !options.length" class="efd-config__warning">
      No attributes of this type exist for the selected project and task type.
    </p>
  </aside>

  <aside v-else class="efd-config efd-config--empty">
    <p>Select a field to configure it.</p>
  </aside>
</template>

<style scoped lang="scss">
.efd-config {
  display: flex;
  flex-direction: column;
  gap: var(--Scale-Size-3, 12px);

  &__title {
    margin: 0;
    font-size: var(--Scale-FontSize-3, 14px);
  }

  &__warning {
    color: var(--Colors-Danger-500, #ff1066);
    font-size: var(--Scale-FontSize-2, 12px);
  }

  &--empty {
    color: var(--Colors-Greys-500, #5c6268);
  }
}
</style>
