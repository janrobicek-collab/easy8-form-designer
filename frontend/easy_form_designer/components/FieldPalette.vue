<script setup lang="ts">
import { DSButton } from "@/src/design_system";
import { WIDGETS, type Widget } from "../types";

defineEmits<{ add: [widget: Widget]; addSection: [] }>();

const LABELS: Record<Widget, string> = {
  text: "Text",
  long_text: "Long text",
  select: "Dropdown",
  date: "Date",
  number: "Number",
  radio: "Radio buttons",
  multi_select: "Multi-select",
  checkbox: "Checkbox",
  user: "User lookup",
  file: "File upload",
};
</script>

<template>
  <aside class="efd-palette">
    <h3 class="efd-palette__title">Add field</h3>
    <DSButton
      v-for="widget in WIDGETS"
      :key="widget"
      variant="secondary"
      class="efd-palette__item"
      :data-cy="`form-designer-palette__${widget}`"
      @click="$emit('add', widget)"
    >
      {{ LABELS[widget] }}
    </DSButton>

    <!-- PRD M11. A new field joins whichever section is selected, so adding
         a section then adding fields is the whole grouping workflow — no
         drag-and-drop needed. -->
    <h3 class="efd-palette__title">Add group</h3>
    <DSButton
      variant="secondary"
      class="efd-palette__item"
      data-cy="form-designer-palette__section"
      @click="$emit('addSection')"
    >
      Section
    </DSButton>
  </aside>
</template>

<style scoped lang="scss">
.efd-palette {
  display: flex;
  flex-direction: column;
  gap: var(--Scale-Size-2, 8px);

  &__title {
    margin: 0 0 var(--Scale-Size-2, 8px);
    font-size: var(--Scale-FontSize-3, 14px);
  }

  &__item {
    width: 100%;
  }
}
</style>
