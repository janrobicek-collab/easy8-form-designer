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

/** Serialized so a native attribute and a custom field id can share one select. */
const mappingValue = computed<string>(() => {
  if (!props.field) return "";
  if (props.field.customFieldId) return `custom_field:${props.field.customFieldId}`;
  if (props.field.mappedAttribute) return `native:${props.field.mappedAttribute}`;
  return "";
});

const selectOptions = computed(() =>
  props.options.map((o) => ({ label: o.label, value: `${o.type}:${o.value}` }))
);

function patch(changes: Partial<FormField>): void {
  if (!props.field) return;
  emit("update", { ...props.field, ...changes });
}

function setMapping(raw: string): void {
  const [type, value] = raw.split(":");

  patch({
    mappedAttribute: type === "native" ? value : null,
    customFieldId: type === "custom_field" ? Number(value) : null,
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
      :model-value="mappingValue"
      :options="selectOptions"
      :loading="loading"
      label="Maps to"
      required
      helper-text="Every field must write to a real task attribute."
      @update:model-value="setMapping"
    />

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
