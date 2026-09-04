<script setup lang="ts">
import Draggable from "vuedraggable";
import { DSButton } from "@/src/design_system";
import type { FormSection } from "../types";
import { useFormBuilderStore } from "../store/formBuilderStore";
import FieldRow from "./FieldRow.vue";

const props = defineProps<{ section: FormSection }>();

const store = useFormBuilderStore();
const t = window.EasyLocale.getLocale;

function addField(): void {
  store.addField(props.section);
}
</script>

<template>
  <div class="efd-field-list">
    <p v-if="!section.fields.length" class="efd-field-list__empty">
      {{ t("easy_form_designer.builder.empty_no_fields") }}
    </p>

    <!-- REQ-17. `group` is shared across every section's list, which is what
         lets vuedraggable move a field FROM one section's array INTO
         another's — a plain splice on `section.fields`, nothing else to
         reconcile afterward since a field's membership IS which array it's
         currently in (see types/index.ts's FormSection doc comment). -->
    <Draggable
      :list="section.fields"
      item-key="token"
      group="efd-form-designer-fields"
      handle=".efd-drag-handle"
      ghost-class="efd-field-list__ghost"
      class="efd-field-list__items"
      :data-cy="`field__list--${section.token}`"
    >
      <template #item="{ element }">
        <FieldRow :section="section" :field="element" />
      </template>
    </Draggable>

    <DSButton
      variant="secondary"
      size="sm"
      prefix-icon="plus"
      :data-cy="`button__add--field-${section.token}`"
      @click="addField"
    >
      {{ t("easy_form_designer.builder.button_add_field") }}
    </DSButton>
  </div>
</template>

<style scoped lang="scss">
.efd-field-list {
  display: flex;
  flex-direction: column;
  gap: var(--Scale-Size-3, 12px);

  &__empty {
    color: var(--Colors-Greys-500, #5c6268);
    font-size: var(--Scale-FontSize-2, 12px);
  }

  &__items {
    display: flex;
    flex-direction: column;
    gap: var(--Scale-Size-3, 12px);
    // A shared group needs a non-zero drop target even when this section
    // has no fields of its own yet — otherwise a field dragged from
    // elsewhere has nowhere visible to land.
    min-height: var(--Scale-Size-6, 24px);
  }

  &__ghost {
    opacity: 0.4;
  }
}
</style>
