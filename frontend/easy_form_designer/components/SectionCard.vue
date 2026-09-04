<script setup lang="ts">
import { DSBadge, DSFieldset, DSIcon, DSTextField } from "@/src/design_system";
import type { FormSection } from "../types";
import { useFormBuilderStore } from "../store/formBuilderStore";
import DragHandle from "./DragHandle.vue";
import FieldList from "./FieldList.vue";
import SectionVisibility from "./SectionVisibility.vue";

const props = defineProps<{ section: FormSection }>();

const store = useFormBuilderStore();
const t = window.EasyLocale.getLocale;

function toggleCollapsed(): void {
  store.patchSection(props.section, { collapsed: !props.section.collapsed });
}
</script>

<template>
  <div class="efd-section-card">
    <DragHandle :data-cy="`handle__drag--section-${section.token}`" />

    <DSFieldset
      :name="section.token"
      :removable="store.canRemoveSection"
      with-border
      :data-cy="`section__card--${section.token}`"
      @remove="store.removeSection(section)"
    >
      <template #actions>
        <DSBadge
          v-if="section.visibilityFieldId != null"
          :text="t('easy_form_designer.builder.label_conditional')"
          state="info"
        />
        <button
          type="button"
          class="efd-section-card__collapse-toggle"
          :data-cy="`toggle__expand--section-${section.token}`"
          @click="toggleCollapsed"
        >
          <DSIcon :icon="section.collapsed ? 'arrow-down' : 'arrow-up'" size="sm" />
        </button>
      </template>

      <DSTextField
        :model-value="section.name"
        required
        :label="t('easy_form_designer.builder.label_section_name')"
        @update:model-value="(v: string) => store.patchSection(section, { name: v })"
      />

      <template v-if="!section.collapsed">
        <SectionVisibility :section="section" />
        <FieldList :section="section" />
      </template>
    </DSFieldset>
  </div>
</template>

<style scoped lang="scss">
.efd-section-card {
  display: flex;
  align-items: flex-start;
  gap: var(--Scale-Size-1, 4px);

  &__collapse-toggle {
    display: flex;
    align-items: center;
    border: none;
    background: none;
    color: var(--Colors-Greys-500, #5c6268);
    cursor: pointer;

    &:hover {
      color: var(--Colors-Greys-700, #292f36);
    }
  }
}
</style>
