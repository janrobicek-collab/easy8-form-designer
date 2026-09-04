<script setup lang="ts">
import { DSIcon } from "@/src/design_system";

defineProps<{ dataCy?: string }>();
</script>

<template>
  <span class="efd-drag-handle" :data-cy="dataCy">
    <DSIcon icon="dragger" size="sm" />
  </span>
</template>

<style scoped lang="scss">
.efd-drag-handle {
  display: flex;
  align-items: center;
  justify-content: center;
  width: var(--Scale-Size-6, 24px);
  align-self: stretch;
  border-radius: var(--Scale-Radius-1, 4px);
  color: var(--Colors-Greys-400, #9aa0a6);
  cursor: grab;
  flex-shrink: 0;

  &:hover {
    background: var(--Colors-Greys-100, #f4f5f6);
    color: var(--Colors-Greys-600, #40474e);
  }

  &:active {
    cursor: grabbing;
  }
}
</style>
