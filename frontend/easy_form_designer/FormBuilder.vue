<script setup lang="ts">
import { computed, onMounted, provide, ref } from "vue";
import { DSAlert, DSButton, DSTabs } from "@/src/design_system";
import SectionList from "./components/SectionList.vue";
import TemplateEditor from "./components/TemplateEditor.vue";
import { LOCALIZATION_KEYS } from "./constants/localeKeys";
import { BUILDER_CONTEXT_KEY } from "./constants/injectionKeys";
import { useFormBuilderStore } from "./store/formBuilderStore";
import type { ApiForm, BuilderContext } from "./types";

const props = defineProps<{ context: BuilderContext; initialForm: ApiForm | null }>();

provide(BUILDER_CONTEXT_KEY, props.context);

const store = useFormBuilderStore();
store.initialize(props.initialForm);

const t = window.EasyLocale.getLocale;
const ready = ref(false);
const activeTab = ref("fields");

onMounted(async () => {
  await window.EasyLocale.fetchLocales([...LOCALIZATION_KEYS]);
  ready.value = true;
});

const tabs = computed(() => [
  { label: t("easy_form_designer.builder.tab_fields"), value: "fields" },
  { label: t("easy_form_designer.builder.tab_templates"), value: "templates" },
]);

async function save(): Promise<void> {
  await store.save(props.context);
}
</script>

<template>
  <div v-if="ready" class="efd-builder">
    <DSTabs v-model="activeTab" :items="tabs" />

    <DSAlert
      v-if="store.unmappedCount"
      variant="warning"
      :body="t('easy_form_designer.builder.alert_unmapped_fields', { count: store.unmappedCount })"
    />
    <DSAlert v-if="store.saveError" variant="error" :body="store.saveError" />
    <DSAlert v-if="store.savedJustNow" variant="success" :body="t('easy_form_designer.builder.alert_saved')" />

    <SectionList v-if="activeTab === 'fields'" />

    <TemplateEditor
      v-else
      :fields="store.allFields"
      :subject-template="store.subjectTemplate"
      :description-template="store.descriptionTemplate"
      @update:subject-template="store.updateSubjectTemplate"
      @update:description-template="store.updateDescriptionTemplate"
    />

    <footer class="efd-builder__footer">
      <DSButton variant="primary" :disabled="store.saving" data-cy="button__save--form" @click="save">
        {{ store.saving ? t("easy_form_designer.builder.label_saving") : t("easy_form_designer.builder.button_save") }}
      </DSButton>
    </footer>
  </div>
</template>

<style scoped lang="scss">
.efd-builder {
  display: flex;
  flex-direction: column;
  gap: var(--Scale-Size-4, 16px);

  &__footer {
    display: flex;
    justify-content: flex-end;
  }
}
</style>
