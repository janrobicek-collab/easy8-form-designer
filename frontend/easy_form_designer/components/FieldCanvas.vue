<script setup lang="ts">
import { DSBadge } from "@/src/design_system";
import type { FormField } from "../types";
import { tokenPlaceholder } from "../types";

defineProps<{ fields: FormField[]; selectedToken: string | null }>();
defineEmits<{ select: [field: FormField]; remove: [field: FormField] }>();
</script>

<template>
  <section class="efd-canvas">
    <p v-if="!fields.length" class="efd-canvas__empty">
      Add a field from the palette to start building this form.
    </p>

    <article
      v-for="field in fields"
      :key="field.token"
      class="efd-canvas__card"
      :class="{ 'is-selected': field.token === selectedToken }"
      :data-cy="`form-designer-canvas__${field.token}`"
      @click="$emit('select', field)"
    >
      <header class="efd-canvas__head">
        <span class="efd-canvas__label">
          {{ field.label }}
          <abbr v-if="field.required" title="Required">*</abbr>
        </span>

        <div class="efd-canvas__head-actions">
          <!-- An unmapped field blocks publishing, so surface it on the card
               itself rather than only in the config panel. -->
          <DSBadge
            :text="field.mappedAttribute || field.customFieldId ? 'Mapped' : 'Not mapped'"
            :state="field.mappedAttribute || field.customFieldId ? 'success' : 'error'"
          />

          <button type="button" class="efd-canvas__remove" @click.stop="$emit('remove', field)">
            Remove
          </button>
        </div>
      </header>

      <p v-if="field.helpText" class="efd-canvas__help">{{ field.helpText }}</p>
      <code class="efd-canvas__token">{{ tokenPlaceholder(field.token) }}</code>
    </article>
  </section>
</template>

<style scoped lang="scss">
.efd-canvas {
  display: flex;
  flex-direction: column;
  gap: var(--Scale-Size-3, 12px);

  &__empty {
    color: var(--Colors-Greys-500, #5c6268);
  }

  &__card {
    position: relative;
    padding: var(--Scale-Size-4, 16px);
    border: 1px solid var(--Colors-Greys-200, #dadee1);
    border-radius: var(--Scale-Radius-2, 6px);
    background: var(--Colors-Common-White, #fff);
    cursor: pointer;

    &.is-selected {
      border-color: var(--Colors-Primary-500, #0d65f2);
      box-shadow: 0 0 0 2px var(--Colors-Primary-200, #b4cffb);
    }
  }

  &__head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--Scale-Size-2, 8px);
  }

  // A sibling of the badge in the flex header, not absolutely positioned
  // over it — an earlier version stacked both in the same top-right corner,
  // so on hover "Remove" rendered directly on top of "Mapped"/"Not mapped".
  &__head-actions {
    display: flex;
    align-items: center;
    gap: var(--Scale-Size-2, 8px);
    flex-shrink: 0;
  }

  &__label {
    font-weight: 600;
  }

  &__help,
  &__token {
    display: block;
    margin-top: var(--Scale-Size-1, 4px);
    font-size: var(--Scale-FontSize-2, 12px);
    color: var(--Colors-Greys-500, #5c6268);
  }

  &__remove {
    border: none;
    background: none;
    color: var(--Colors-Danger-500, #ff1066);
    cursor: pointer;
    opacity: 0;
  }

  &__card:hover &__remove {
    opacity: 1;
  }
}
</style>
