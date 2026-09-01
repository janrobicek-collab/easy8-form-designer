<script setup lang="ts">
import { computed } from "vue";
import dayjs, { Dayjs } from "dayjs";
import { DSDatepicker, DSNumberField, DSSelect, DSTextField } from "@/src/design_system";
import { BE_DATE_FORMAT } from "@/src/shared/constants/date";
import type { FormField, FormSection, OperatorOption, PresetOption } from "../types";
import { DAY_COUNT_OPERATORS, DATE_FILTER_TYPES, RANGE_OPERATORS } from "../types";

const props = defineProps<{
  section: FormSection | null;
  // Every field on the form, so the rule can pick which one it reads.
  fields: FormField[];
  // Both served together for the chosen field: what it can hold, and how it
  // may be compared. The operator list is EasyQuery's own, already
  // translated — a date field offers periods, a list field offers is/is not,
  // exactly as the same field does in any other Easy8 filter.
  valueOptions: PresetOption[];
  operatorOptions: OperatorOption[];
  // The field's EasyQuery filter type. Which operators exist is answered by
  // operatorOptions; this decides what a VALUE for one looks like — a date
  // rule's "is" and "between" are picked from a calendar, while its offset
  // operators ("less than days ago") take a plain number of days.
  filterType: string | null;
  optionsLoading: boolean;
}>();

const emit = defineEmits<{ update: [section: FormSection] }>();

function patch(changes: Partial<FormSection>): void {
  if (!props.section) return;
  emit("update", { ...props.section, ...changes });
}

// Same DSSelect object-model-value contract used throughout this builder.
interface RuleFieldOption {
  label: string;
  value: string;
  fieldId: number | null;
}

// An unsaved field has no id to reference yet. A file field is excluded
// because its answer is uploads — FormField#filter_type returns nil for it,
// so the model would reject the rule anyway.
const ruleFieldOptions = computed<RuleFieldOption[]>(() => [
  { label: "Always visible", value: "none", fieldId: null },
  ...props.fields
    .filter((f) => f.id != null && f.widget !== "file")
    .map((f) => ({ label: f.label, value: String(f.id), fieldId: f.id as number })),
]);

const ruleFieldValue = computed<RuleFieldOption | null>(() => {
  const id = props.section?.visibilityFieldId ?? null;
  return ruleFieldOptions.value.find((o) => o.fieldId === id) ?? null;
});

// Clearing the field clears the whole rule — the model rejects a
// half-specified one, so leaving an operator behind would only produce a
// save that fails.
function setRuleField(option: RuleFieldOption | null): void {
  const fieldId = option?.fieldId ?? null;

  patch(
    fieldId === null
      ? { visibilityFieldId: null, visibilityOperator: null, visibilityValues: [] }
      : { visibilityFieldId: fieldId, visibilityOperator: null, visibilityValues: [] }
  );
}

const hasRule = computed(() => props.section?.visibilityFieldId != null);

const operatorValue = computed<OperatorOption | null>(
  () => props.operatorOptions.find((o) => o.value === props.section?.visibilityOperator) ?? null
);

// Switching operator clears the value: the shapes aren't interchangeable
// (one value, two, a day count, or none), so carrying the old one over would
// leave something the new operator can't read.
function setOperator(option: OperatorOption | null): void {
  patch({ visibilityOperator: option?.value ?? null, visibilityValues: [] });
}

function setValueAt(index: number, raw: string | number | null): void {
  const next = [...(props.section?.visibilityValues ?? [])];
  next[index] = raw === null || raw === undefined ? "" : `${raw}`;

  patch({ visibilityValues: next });
}

function valueAt(index: number): string {
  return props.section?.visibilityValues?.[index] ?? "";
}

// Which value control the chosen operator calls for. Driven by the server's
// own `needs_value` flag (EasyQuery.hidden_values_by_operator) rather than a
// second copy of that list here.
type ValueShape = "none" | "pick" | "text" | "range" | "days" | "date" | "dateRange";

// Absent options (not loaded yet) mean "assume a value is needed" — the same
// reading the previous version had, and the safe one: showing an input that
// turns out to be unnecessary is better than hiding one that is.
const takesValue = computed(() => hasRule.value && operatorValue.value?.needs_value !== false);

const isDateRule = computed(() => DATE_FILTER_TYPES.includes(props.filterType ?? ""));

const valueShape = computed<ValueShape>(() => {
  const operator = props.section?.visibilityOperator;
  if (!operator || !takesValue.value) return "none";

  return isDateRule.value ? dateShape(operator) : plainShape(operator);
});

// A date rule's value is a date — except for the offset operators, whose
// value is a count of days rather than a point in time.
function dateShape(operator: string): ValueShape {
  if (DAY_COUNT_OPERATORS.includes(operator)) return "days";

  return RANGE_OPERATORS.includes(operator) ? "dateRange" : "date";
}

function plainShape(operator: string): ValueShape {
  if (RANGE_OPERATORS.includes(operator)) return "range";
  if (DAY_COUNT_OPERATORS.includes(operator)) return "days";

  // A field with a fixed option list is picked from; anything else is typed.
  // "Contains" on a list field is still typed, which is why this keys off the
  // operator as well as the options.
  return props.valueOptions.length && !isTextOperator(operator) ? "pick" : "text";
}

function isTextOperator(operator: string): boolean {
  return ["~", "!~", "^~", "$~"].includes(operator);
}

const pickedValue = computed<PresetOption | null>(
  () => props.valueOptions.find((o) => o.value === valueAt(0)) ?? null
);

// Stored as the same ISO string the requester's answer arrives as, so
// RuleEvaluator compares like with like; DSDatepicker works in Dayjs.
function dateAt(index: number): Dayjs | null {
  const raw = valueAt(index);
  if (!raw) return null;

  const parsed = dayjs(raw);

  return parsed.isValid() ? parsed : null;
}

function setDateAt(index: number, value: Dayjs | null): void {
  setValueAt(index, value ? value.format(BE_DATE_FORMAT) : "");
}

// Built here rather than written inline: a literal "{{" in a Vue template is
// parsed as an interpolation delimiter and breaks the SFC compiler — the same
// reason tokenPlaceholder() exists for field tokens.
const sectionOpenMarker = computed(() => `{{#${props.section?.token ?? "token"}}}`);
const sectionCloseMarker = computed(() => `{{/${props.section?.token ?? "token"}}}`);
</script>

<template>
  <aside v-if="section" class="efd-config">
    <h3 class="efd-config__title">Section settings</h3>

    <DSTextField
      :model-value="section.name"
      label="Name"
      required
      @update:model-value="(v: string) => patch({ name: v })"
    />

    <!-- PRD M11. With no rule the section is simply a visual group; with one
         it is asked only when the rule holds. -->
    <DSSelect
      name="visibility_field"
      :model-value="ruleFieldValue"
      :options="ruleFieldOptions"
      label="Show this section when"
      @update:model-value="(v) => setRuleField(v as RuleFieldOption | null)"
    />

    <template v-if="hasRule">
      <DSSelect
        name="visibility_operator"
        :model-value="operatorValue"
        :options="operatorOptions"
        :loading="optionsLoading"
        label="Operator"
        @update:model-value="(v) => setOperator(v as OperatorOption | null)"
      />

      <DSSelect
        v-if="valueShape === 'pick'"
        name="visibility_value"
        :model-value="pickedValue"
        :options="valueOptions"
        :loading="optionsLoading"
        label="Value"
        @update:model-value="(v) => setValueAt(0, (v as PresetOption | null)?.value ?? null)"
      />

      <DSTextField
        v-else-if="valueShape === 'text'"
        :model-value="valueAt(0)"
        label="Value"
        @update:model-value="(v: string) => setValueAt(0, v)"
      />

      <DSDatepicker
        v-else-if="valueShape === 'date'"
        :model-value="dateAt(0)"
        name="visibility_date"
        label="Value"
        @update:model-value="(v: Dayjs | null) => setDateAt(0, v)"
      />

      <DSNumberField
        v-else-if="valueShape === 'days'"
        :model-value="valueAt(0)"
        name="visibility_days"
        label="Days"
        @update:model-value="(v: string | number | null) => setValueAt(0, v)"
      />

      <template v-else-if="valueShape === 'dateRange'">
        <DSDatepicker
          :model-value="dateAt(0)"
          name="visibility_date_from"
          label="From"
          @update:model-value="(v: Dayjs | null) => setDateAt(0, v)"
        />
        <DSDatepicker
          :model-value="dateAt(1)"
          name="visibility_date_to"
          label="To"
          @update:model-value="(v: Dayjs | null) => setDateAt(1, v)"
        />
      </template>

      <template v-else-if="valueShape === 'range'">
        <DSTextField
          :model-value="valueAt(0)"
          label="From"
          @update:model-value="(v: string) => setValueAt(0, v)"
        />
        <DSTextField
          :model-value="valueAt(1)"
          label="To"
          @update:model-value="(v: string) => setValueAt(1, v)"
        />
      </template>

      <p class="caption">
        Fields in this section are only asked — and their block of the task description is only
        included — when the rule holds. A rule can't read a field that is itself inside a
        conditional section.
      </p>
    </template>

    <p class="caption">
      Reference this section in the task description as
      <code>{{ sectionOpenMarker }}</code> … <code>{{ sectionCloseMarker }}</code>.
    </p>
  </aside>

  <aside v-else class="efd-config efd-config--empty">
    <p>Select a section to configure it.</p>
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

  &--empty {
    color: var(--Colors-Greys-500, #5c6268);
  }
}
</style>
