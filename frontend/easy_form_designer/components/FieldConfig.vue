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
    <p class="caption">Every field must write to a real task attribute.</p>

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
