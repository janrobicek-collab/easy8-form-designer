<script setup lang="ts">
import dayjs, { type Dayjs } from "dayjs";
import { computed, ref } from "vue";
import { DSDatepicker, DSNumberField, DSSelect, DSSwitch } from "@/src/design_system";
import type { DateBoundMode, FormField, ValidationFormat } from "../types";
import { DATE_RANGE_WIDGETS, FILE_WIDGETS, RANGE_WIDGETS, VALIDATION_FORMAT_WIDGETS } from "../types";
import { useFormBuilderStore } from "../store/formBuilderStore";
import FieldPreset from "./FieldPreset.vue";

const props = defineProps<{ field: FormField }>();

const store = useFormBuilderStore();
const t = window.EasyLocale.getLocale;

function patch(changes: Partial<FormField>): void {
  store.patchField(props.field, changes);
}

const supportsValidationFormat = computed(() => VALIDATION_FORMAT_WIDGETS.includes(props.field.widget));
const supportsRange = computed(() => RANGE_WIDGETS.includes(props.field.widget));
const supportsDateRange = computed(() => DATE_RANGE_WIDGETS.includes(props.field.widget));
const isFileField = computed(() => FILE_WIDGETS.includes(props.field.widget));

function setValidationFormat(format: ValidationFormat | null): void {
  patch({ validationFormat: format });
}

function setBound(key: "minValue" | "maxValue", raw: string | number | null): void {
  const value = raw === null || raw === undefined || `${raw}`.trim() === "" ? null : `${raw}`;
  patch({ [key]: value } as Partial<FormField>);
}

interface DateBoundModeOption {
  label: string;
  value: DateBoundMode;
}

const dateBoundModeOptions = computed<DateBoundModeOption[]>(() => [
  { label: t("easy_form_designer.builder.option_date_mode_none"), value: "none" },
  { label: t("easy_form_designer.builder.option_date_mode_fixed"), value: "fixed" },
  { label: t("easy_form_designer.builder.option_date_mode_offset"), value: "offset" },
]);

function deriveDateBoundMode(date: string | null, offsetDays: number | null): DateBoundMode {
  if (offsetDays !== null) return "offset";
  if (date) return "fixed";
  return "none";
}

// A date bound is either a fixed date or a day offset from today — the model
// rejects both being set on the same side. "Mode" has to be tracked as
// local state rather than derived purely from the data: while the author is
// filling in a brand-new "Fixed date" bound, minDate is still null (nothing
// picked yet), and a purely-derived mode would read that back as "No limit"
// and the picker just opened would vanish under them. A fresh FieldAdvanced
// instance is mounted per field (FieldRow's `v-if="advancedOpen"`), so
// initializing once from the field's current data — with no watch to
// re-derive it later — is enough; unlike the old single-panel builder, this
// component is never handed a DIFFERENT field without being remounted.
const minDateMode = ref<DateBoundMode>(deriveDateBoundMode(props.field.minDate, props.field.minDateOffsetDays));
const maxDateMode = ref<DateBoundMode>(deriveDateBoundMode(props.field.maxDate, props.field.maxDateOffsetDays));

const minDateModeValue = computed(() => dateBoundModeOptions.value.find((o) => o.value === minDateMode.value) ?? null);
const maxDateModeValue = computed(() => dateBoundModeOptions.value.find((o) => o.value === maxDateMode.value) ?? null);

// Switching mode always clears both underlying columns for that side — a
// clean slate for whichever shape the author just picked, rather than
// resurrecting a stale value from whatever the other mode last held.
function setDateBoundMode(side: "min" | "max", option: DateBoundModeOption | null): void {
  const mode = option?.value ?? "none";

  if (side === "min") {
    minDateMode.value = mode;
    patch({ minDate: null, minDateOffsetDays: null });
  } else {
    maxDateMode.value = mode;
    patch({ maxDate: null, maxDateOffsetDays: null });
  }
}

function toDayjs(iso: string | null): Dayjs | null {
  return iso ? dayjs(iso) : null;
}

function setFixedDate(key: "minDate" | "maxDate", value: Dayjs | null): void {
  patch({ [key]: value ? value.format("YYYY-MM-DD") : null } as Partial<FormField>);
}

function setDateOffset(key: "minDateOffsetDays" | "maxDateOffsetDays", raw: string | number | null): void {
  const trimmed = raw === null || raw === undefined ? "" : `${raw}`.trim();
  if (trimmed === "") {
    patch({ [key]: null } as Partial<FormField>);
    return;
  }

  const parsed = Number(trimmed);
  patch({ [key]: Number.isNaN(parsed) ? null : parsed } as Partial<FormField>);
}

// "Hidden" and "Required" are mutually exclusive in the model
// (FormField#clear_required_when_hidden forces required back to false
// server-side) — patched together so the UI never shows a stale, silently
// ineffective Required switch after turning Hidden on.
function setHidden(value: boolean): void {
  patch({ hidden: value, required: value ? false : props.field.required });
}

const formatOptions = computed(() => [
  { label: t("easy_form_designer.builder.option_validation_none"), value: null as ValidationFormat | null },
  { label: t("easy_form_designer.builder.option_validation_email"), value: "email" as ValidationFormat | null },
  { label: t("easy_form_designer.builder.option_validation_url"), value: "url" as ValidationFormat | null },
]);

const formatValue = computed(
  () => formatOptions.value.find((o) => o.value === props.field.validationFormat) ?? null
);
</script>

<template>
  <div class="efd-advanced">
    <DSSwitch
      v-if="!isFileField"
      :model-value="field.hidden"
      name="hidden"
      :label="t('easy_form_designer.builder.label_hidden_from_requester')"
      @update:model-value="(v: boolean) => setHidden(v)"
    />

    <DSSelect
      v-if="supportsValidationFormat"
      name="validation_format"
      :model-value="formatValue"
      :options="formatOptions"
      :label="t('easy_form_designer.builder.label_validation')"
      @update:model-value="(v) => setValidationFormat((v as { value: ValidationFormat | null } | null)?.value ?? null)"
    />

    <template v-if="supportsRange">
      <div class="efd-advanced__row">
        <DSNumberField
          :model-value="field.minValue"
          name="min_value"
          :label="t('easy_form_designer.builder.label_minimum')"
          @update:model-value="(v: string | number | null) => setBound('minValue', v)"
        />
        <DSNumberField
          :model-value="field.maxValue"
          name="max_value"
          :label="t('easy_form_designer.builder.label_maximum')"
          @update:model-value="(v: string | number | null) => setBound('maxValue', v)"
        />
      </div>
      <p class="caption">{{ t("easy_form_designer.builder.caption_no_bound_limit") }}</p>
    </template>

    <template v-if="supportsDateRange">
      <div class="efd-advanced__row">
        <DSSelect
          name="min_date_mode"
          :model-value="minDateModeValue"
          :options="dateBoundModeOptions"
          :label="t('easy_form_designer.builder.label_earliest_date')"
          @update:model-value="(v) => setDateBoundMode('min', v as DateBoundModeOption | null)"
        />
        <DSDatepicker
          v-if="minDateMode === 'fixed'"
          name="min_date"
          :label="t('easy_form_designer.builder.label_from')"
          :model-value="toDayjs(field.minDate)"
          @update:model-value="(v: Dayjs | null) => setFixedDate('minDate', v)"
        />
        <DSNumberField
          v-if="minDateMode === 'offset'"
          :model-value="field.minDateOffsetDays"
          name="min_date_offset_days"
          :label="t('easy_form_designer.builder.label_days')"
          allow-negative
          @update:model-value="(v: string | number | null) => setDateOffset('minDateOffsetDays', v)"
        />
      </div>

      <div class="efd-advanced__row">
        <DSSelect
          name="max_date_mode"
          :model-value="maxDateModeValue"
          :options="dateBoundModeOptions"
          :label="t('easy_form_designer.builder.label_latest_date')"
          @update:model-value="(v) => setDateBoundMode('max', v as DateBoundModeOption | null)"
        />
        <DSDatepicker
          v-if="maxDateMode === 'fixed'"
          name="max_date"
          :label="t('easy_form_designer.builder.label_to')"
          :model-value="toDayjs(field.maxDate)"
          @update:model-value="(v: Dayjs | null) => setFixedDate('maxDate', v)"
        />
        <DSNumberField
          v-if="maxDateMode === 'offset'"
          :model-value="field.maxDateOffsetDays"
          name="max_date_offset_days"
          :label="t('easy_form_designer.builder.label_days')"
          allow-negative
          @update:model-value="(v: string | number | null) => setDateOffset('maxDateOffsetDays', v)"
        />
      </div>
    </template>

    <FieldPreset v-if="!isFileField" :field="field" />
  </div>
</template>

<style scoped lang="scss">
.efd-advanced {
  display: flex;
  flex-direction: column;
  gap: var(--Scale-Size-3, 12px);
  padding-top: var(--Scale-Size-3, 12px);
  margin-top: var(--Scale-Size-2, 8px);
  border-top: 1px solid var(--Colors-Greys-100, #f4f5f6);

  &__row {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
    gap: var(--Scale-Size-3, 12px);
  }
}
</style>
