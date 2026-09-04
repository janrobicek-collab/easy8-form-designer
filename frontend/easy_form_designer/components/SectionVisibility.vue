<script setup lang="ts">
import dayjs, { type Dayjs } from "dayjs";
import { computed, inject, watch } from "vue";
import { DSDatepicker, DSNumberField, DSSelect, DSTextField } from "@/src/design_system";
import { BE_DATE_FORMAT } from "@/src/shared/constants/date";
import type { FormSection } from "../types";
import { DATE_FILTER_TYPES, DAY_COUNT_OPERATORS, RANGE_OPERATORS } from "../types";
import { BUILDER_CONTEXT_KEY } from "../constants/injectionKeys";
import { usePresetOptions } from "../composables/usePresetOptions";
import { useFormBuilderStore } from "../store/formBuilderStore";

const props = defineProps<{ section: FormSection }>();

const store = useFormBuilderStore();
const context = inject(BUILDER_CONTEXT_KEY);
const t = window.EasyLocale.getLocale;

function patch(changes: Partial<FormSection>): void {
  store.patchSection(props.section, changes);
}

// PRD M11. A rule's legal values come from the SAME "what can this field
// legally hold?" endpoint M8's preset picker uses — reused here rather than
// a second implementation. Reloads whenever the DRIVING field changes.
const {
  options: valueOptions,
  operators: operatorOptions,
  filterType,
  loading: optionsLoading,
  load: loadValueOptions,
} = usePresetOptions(context!);

interface RuleFieldOption {
  label: string;
  value: string;
  fieldId: number | null;
}

// An unsaved field has no id to reference yet. A file field is excluded
// because its answer is uploads — FormField#filter_type returns nil for it,
// so the model would reject the rule anyway.
const ruleFieldOptions = computed<RuleFieldOption[]>(() => [
  { label: t("easy_form_designer.builder.label_always_visible"), value: "none", fieldId: null },
  ...store.allFields
    .filter((f) => f.id != null && f.widget !== "file")
    .map((f) => ({ label: f.label, value: String(f.id), fieldId: f.id as number })),
]);

const ruleFieldValue = computed<RuleFieldOption | null>(() => {
  const id = props.section.visibilityFieldId;
  return ruleFieldOptions.value.find((o) => o.fieldId === id) ?? null;
});

watch(
  () => props.section.visibilityFieldId,
  (fieldId) => {
    const field = store.allFields.find((f) => f.id === fieldId);
    if (field) void loadValueOptions(field);
  },
  { immediate: true }
);

// Clearing the field clears the whole rule — the model rejects a
// half-specified one.
function setRuleField(option: RuleFieldOption | null): void {
  const fieldId = option?.fieldId ?? null;

  patch(
    fieldId === null
      ? { visibilityFieldId: null, visibilityOperator: null, visibilityValues: [] }
      : { visibilityFieldId: fieldId, visibilityOperator: null, visibilityValues: [] }
  );
}

const hasRule = computed(() => props.section.visibilityFieldId != null);

const operatorValue = computed(
  () => operatorOptions.value.find((o) => o.value === props.section.visibilityOperator) ?? null
);

// Switching operator clears the value: the shapes aren't interchangeable.
function setOperator(option: (typeof operatorOptions.value)[number] | null): void {
  patch({ visibilityOperator: option?.value ?? null, visibilityValues: [] });
}

function setValueAt(index: number, raw: string | number | null): void {
  const next = [...props.section.visibilityValues];
  next[index] = raw === null || raw === undefined ? "" : `${raw}`;

  patch({ visibilityValues: next });
}

function valueAt(index: number): string {
  return props.section.visibilityValues[index] ?? "";
}

type ValueShape = "none" | "pick" | "text" | "range" | "days" | "date" | "dateRange";

const takesValue = computed(() => hasRule.value && operatorValue.value?.needs_value !== false);
const isDateRule = computed(() => DATE_FILTER_TYPES.includes(filterType.value ?? ""));

const valueShape = computed<ValueShape>(() => {
  const operator = props.section.visibilityOperator;
  if (!operator || !takesValue.value) return "none";

  return isDateRule.value ? dateShape(operator) : plainShape(operator);
});

function dateShape(operator: string): ValueShape {
  if (DAY_COUNT_OPERATORS.includes(operator)) return "days";
  return RANGE_OPERATORS.includes(operator) ? "dateRange" : "date";
}

function plainShape(operator: string): ValueShape {
  if (RANGE_OPERATORS.includes(operator)) return "range";
  if (DAY_COUNT_OPERATORS.includes(operator)) return "days";

  return valueOptions.value.length && !isTextOperator(operator) ? "pick" : "text";
}

function isTextOperator(operator: string): boolean {
  return ["~", "!~", "^~", "$~"].includes(operator);
}

const pickedValue = computed(() => valueOptions.value.find((o) => o.value === valueAt(0)) ?? null);

function dateAt(index: number): Dayjs | null {
  const raw = valueAt(index);
  if (!raw) return null;

  const parsed = dayjs(raw);
  return parsed.isValid() ? parsed : null;
}

function setDateAt(index: number, value: Dayjs | null): void {
  setValueAt(index, value ? value.format(BE_DATE_FORMAT) : "");
}
</script>

<template>
  <div class="efd-visibility">
    <DSSelect
      name="visibility_field"
      :model-value="ruleFieldValue"
      :options="ruleFieldOptions"
      :label="t('easy_form_designer.builder.label_show_section_when')"
      @update:model-value="(v) => setRuleField(v as RuleFieldOption | null)"
    />

    <div v-if="hasRule" class="efd-visibility__rule">
      <DSSelect
        name="visibility_operator"
        :model-value="operatorValue"
        :options="operatorOptions"
        :loading="optionsLoading"
        :label="t('easy_form_designer.builder.label_operator')"
        @update:model-value="(v) => setOperator(v as (typeof operatorOptions)[number] | null)"
      />

      <DSSelect
        v-if="valueShape === 'pick'"
        name="visibility_value"
        :model-value="pickedValue"
        :options="valueOptions"
        :loading="optionsLoading"
        :label="t('easy_form_designer.builder.label_value')"
        @update:model-value="(v) => setValueAt(0, (v as { value: string } | null)?.value ?? null)"
      />

      <DSTextField
        v-else-if="valueShape === 'text'"
        :model-value="valueAt(0)"
        :label="t('easy_form_designer.builder.label_value')"
        @update:model-value="(v: string) => setValueAt(0, v)"
      />

      <DSDatepicker
        v-else-if="valueShape === 'date'"
        :model-value="dateAt(0)"
        name="visibility_date"
        :label="t('easy_form_designer.builder.label_value')"
        @update:model-value="(v: Dayjs | null) => setDateAt(0, v)"
      />

      <DSNumberField
        v-else-if="valueShape === 'days'"
        :model-value="valueAt(0)"
        name="visibility_days"
        :label="t('easy_form_designer.builder.label_days')"
        @update:model-value="(v: string | number | null) => setValueAt(0, v)"
      />

      <template v-else-if="valueShape === 'dateRange'">
        <DSDatepicker
          :model-value="dateAt(0)"
          name="visibility_date_from"
          :label="t('easy_form_designer.builder.label_from')"
          @update:model-value="(v: Dayjs | null) => setDateAt(0, v)"
        />
        <DSDatepicker
          :model-value="dateAt(1)"
          name="visibility_date_to"
          :label="t('easy_form_designer.builder.label_to')"
          @update:model-value="(v: Dayjs | null) => setDateAt(1, v)"
        />
      </template>

      <template v-else-if="valueShape === 'range'">
        <DSTextField
          :model-value="valueAt(0)"
          :label="t('easy_form_designer.builder.label_from')"
          @update:model-value="(v: string) => setValueAt(0, v)"
        />
        <DSTextField
          :model-value="valueAt(1)"
          :label="t('easy_form_designer.builder.label_to')"
          @update:model-value="(v: string) => setValueAt(1, v)"
        />
      </template>

      <p class="caption">{{ t("easy_form_designer.builder.caption_rule_effect") }}</p>
    </div>

    <p class="caption">
      {{
        t("easy_form_designer.builder.caption_section_template_reference", { token: section.token })
      }}
    </p>
  </div>
</template>

<style scoped lang="scss">
.efd-visibility {
  display: flex;
  flex-direction: column;
  gap: var(--Scale-Size-3, 12px);
  padding-top: var(--Scale-Size-2, 8px);
  border-top: 1px solid var(--Colors-Greys-100, #f4f5f6);

  &__rule {
    display: flex;
    flex-direction: column;
    gap: var(--Scale-Size-3, 12px);
  }
}
</style>
