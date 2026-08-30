<script setup lang="ts">
import { computed } from "vue";
import { DSTextarea, DSTextField } from "@/src/design_system";
import type { FormField } from "../types";

const props = defineProps<{
  fields: FormField[];
  subjectTemplate: string;
  descriptionTemplate: string;
}>();

const emit = defineEmits<{
  "update:subjectTemplate": [value: string];
  "update:descriptionTemplate": [value: string];
}>();

const tokens = computed(() => props.fields.map((f) => ({ token: f.token, label: f.label })));

/** Rough preview using the field labels as stand-in answers. */
const preview = computed(() =>
  props.descriptionTemplate.replace(/\{\{\s*([a-zA-Z0-9_-]+)\s*\}\}/g, (match, token: string) => {
    const field = props.fields.find((f) => f.token === token);
    return field ? `<${field.label}>` : match;
  })
);

function insert(token: string): void {
  emit("update:descriptionTemplate", `${props.descriptionTemplate}{{ ${token} }}`);
}
</script>

<template>
  <div class="efd-templates">
    <DSTextField
      :model-value="subjectTemplate"
      label="Task subject"
      helper-text="Use {{ token }} to insert an answer."
      @update:model-value="(v: string) => emit('update:subjectTemplate', v)"
    />

    <DSTextarea
      :model-value="descriptionTemplate"
      label="Task description"
      :rows="8"
      @update:model-value="(v: string) => emit('update:descriptionTemplate', v)"
    />

    <div class="efd-templates__tokens">
      <span class="efd-templates__tokens-title">Insert a field</span>
      <button
        v-for="t in tokens"
        :key="t.token"
        type="button"
        class="efd-templates__chip"
        @click="insert(t.token)"
      >
        {{ `{{ ${t.token} }}` }} &mdash; {{ t.label }}
      </button>
    </div>

    <section class="efd-templates__preview">
      <h4>Preview</h4>
      <pre>{{ preview }}</pre>
    </section>
  </div>
</template>

<style scoped lang="scss">
.efd-templates {
  display: flex;
  flex-direction: column;
  gap: var(--Scale-Size-3, 12px);

  &__tokens {
    display: flex;
    flex-wrap: wrap;
    gap: var(--Scale-Size-2, 8px);
    align-items: center;
  }

  &__tokens-title {
    font-size: var(--Scale-FontSize-2, 12px);
    color: var(--Colors-Greys-500, #5c6268);
  }

  &__chip {
    padding: var(--Scale-Size-1, 4px) var(--Scale-Size-2, 8px);
    border: 1px solid var(--Colors-Greys-200, #dadee1);
    border-radius: var(--Scale-Radius-1, 4px);
    background: var(--Colors-Common-White, #fff);
    font-size: var(--Scale-FontSize-2, 12px);
    cursor: pointer;

    &:hover {
      background: var(--Colors-Primary-100, #f4f9ff);
    }
  }

  &__preview {
    padding: var(--Scale-Size-3, 12px);
    border: 1px solid var(--Colors-Greys-200, #dadee1);
    border-radius: var(--Scale-Radius-2, 6px);
    background: var(--Colors-Greys-100, #f4f5f6);

    h4 {
      margin: 0 0 var(--Scale-Size-2, 8px);
      font-size: var(--Scale-FontSize-2, 12px);
    }

    pre {
      margin: 0;
      white-space: pre-wrap;
    }
  }
}
</style>
