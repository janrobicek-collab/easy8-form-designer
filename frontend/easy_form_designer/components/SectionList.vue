<script setup lang="ts">
import Draggable from "vuedraggable";
import { DSButton } from "@/src/design_system";
import { useFormBuilderStore } from "../store/formBuilderStore";
import SectionCard from "./SectionCard.vue";

const store = useFormBuilderStore();
const t = window.EasyLocale.getLocale;
</script>

<template>
  <div class="efd-section-list">
    <p v-if="!store.sections.length" class="efd-section-list__empty">
      {{ t("easy_form_designer.builder.empty_no_sections") }}
    </p>

    <Draggable
      :list="store.sections"
      item-key="id"
      handle=".efd-drag-handle"
      ghost-class="efd-section-list__ghost"
      class="efd-section-list__items"
      data-cy="section__list"
    >
      <template #item="{ element }">
        <SectionCard :section="element" />
      </template>
    </Draggable>

    <DSButton variant="secondary" prefix-icon="plus" data-cy="button__add--section" @click="store.addSection">
      {{ t("easy_form_designer.builder.button_add_section") }}
    </DSButton>
  </div>
</template>

<style scoped lang="scss">
.efd-section-list {
  display: flex;
  flex-direction: column;
  gap: var(--Scale-Size-4, 16px);

  &__empty {
    color: var(--Colors-Greys-500, #5c6268);
  }

  &__items {
    display: flex;
    flex-direction: column;
    gap: var(--Scale-Size-4, 16px);
  }

  &__ghost {
    opacity: 0.4;
  }
}
</style>
