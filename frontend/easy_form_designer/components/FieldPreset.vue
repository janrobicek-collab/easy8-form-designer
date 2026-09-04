<script setup lang="ts">
import dayjs, { type Dayjs } from "dayjs";
import { computed, inject, ref, watch } from "vue";
import { DSDatepicker, DSNumberField, DSSelect, DSTextField } from "@/src/design_system";
import type { DateBoundMode, FormField, PresetOption, Widget } from "../types";
import { BUILDER_CONTEXT_KEY } from "../constants/injectionKeys";
import { usePresetOptions } from "../composables/usePresetOptions";
import { useFormBuilderStore } from "../store/formBuilderStore";

const props = defineProps<{ field: FormField }>();

const store = useFormBuilderStore();
const context = inject(BUILDER_CONTEXT_KEY);
const t = window.EasyLocale.getLocale;

function patch(changes: Partial<FormField>): void {
  store.patchField(props.field, changes);
}

// PRD M8 — the preset itself. Hidden and Not-hidden have different meanings
// for the same control: hidden makes this the field's ONLY source of truth
// (required, enforced server-side by FormField#hidden_requires_preset);
// visible makes it an optional default the requester sees pre-filled and
// may change or clear.
type PresetKind = "text" | "number" | "choice" | "multi_choice" | "date";

// Grouped by shape, not by widget 1:1 — a Dropdown/Radio/User-lookup/
// Checkbox preset is all "pick one of a server-provided list" even though
// only some of those are CHOICE_WIDGETS on the model (checkbox's Yes/No pair
// comes from FormField#preset_options the same way, just via a different
// branch server-side). A lookup table rather than a switch keeps this at
// eslint's complexity ceiling.
const PRESET_KIND_BY_WIDGET: Partial<Record<Widget, PresetKind>> = {
  text: "text",
  long_text: "text",
  number: "number",
  select: "choice",
  radio: "choice",
  user: "choice",
  checkbox: "choice",
  multi_select: "multi_choice",
  date: "date",
};

const presetKind = computed<PresetKind | null>(() => PRESET_KIND_BY_WIDGET[props.field.widget] ?? null);

// Loaded lazily — only once this panel is actually open — since every
// field's Advanced section could in principle be open at once in the
// inline-editing layout, and most fields never need this round trip at all.
const {
  options: presetOptions,
  loading: presetOptionsLoading,
  load: loadPresetOptions,
} = usePresetOptions(context!);

watch(
  () => [props.field.widget, props.field.mappedAttribute, props.field.customFieldId] as const,
  () => void loadPresetOptions(props.field),
  { immediate: true }
);

const hasPreset = computed(() => {
  if (props.field.presetOffsetDays !== null) return true;
  return Array.isArray(props.field.presetValue)
    ? props.field.presetValue.length > 0
    : !!props.field.presetValue;
});

function setPresetText(value: string): void {
  patch({ presetValue: value === "" ? null : value });
}

function setPresetNumber(raw: string | number | null): void {
  const value = raw === null || raw === undefined || `${raw}`.trim() === "" ? null : `${raw}`;
  patch({ presetValue: value });
}

const presetSingleValue = computed<PresetOption | null>(() => {
  if (Array.isArray(props.field.presetValue)) return null;
  return presetOptions.value.find((o) => o.value === props.field.presetValue) ?? null;
});

function setPresetChoice(option: PresetOption | null): void {
  patch({ presetValue: option?.value ?? null });
}

const presetMultiValue = computed<PresetOption[]>(() => {
  const raw = Array.isArray(props.field.presetValue) ? props.field.presetValue : [];
  return presetOptions.value.filter((o) => raw.includes(o.value));
});

function setPresetMulti(selected: PresetOption[] | null): void {
  patch({ presetValue: (selected ?? []).map((o) => o.value) });
}

interface DateBoundModeOption {
  label: string;
  value: DateBoundMode;
}

function deriveDateBoundMode(date: string | null, offsetDays: number | null): DateBoundMode {
  if (offsetDays !== null) return "offset";
  if (date) return "fixed";
  return "none";
}

// See FieldAdvanced's identical note on min/max date mode: local state
// initialized once, not derived, and safe because this component is
// remounted (not reused) whenever a different field's panel opens.
const presetDateMode = ref<DateBoundMode>(
  deriveDateBoundMode(
    Array.isArray(props.field.presetValue) ? null : props.field.presetValue,
    props.field.presetOffsetDays
  )
);

const presetDateModeOptions = computed<DateBoundModeOption[]>(() => [
  { label: t("easy_form_designer.builder.option_preset_date_mode_none"), value: "none" },
  { label: t("easy_form_designer.builder.option_date_mode_fixed"), value: "fixed" },
  { label: t("easy_form_designer.builder.option_date_mode_offset"), value: "offset" },
]);

const presetDateModeValue = computed(
  () => presetDateModeOptions.value.find((o) => o.value === presetDateMode.value) ?? null
);

function setPresetDateMode(option: DateBoundModeOption | null): void {
  presetDateMode.value = option?.value ?? "none";
  patch({ presetValue: null, presetOffsetDays: null });
}

function toDayjs(iso: string | null): Dayjs | null {
  return iso ? dayjs(iso) : null;
}

function setPresetFixedDate(value: Dayjs | null): void {
  patch({ presetValue: value ? value.format("YYYY-MM-DD") : null });
}

function setPresetOffset(raw: string | number | null): void {
  const trimmed = raw === null || raw === undefined ? "" : `${raw}`.trim();
  if (trimmed === "") {
    patch({ presetOffsetDays: null });
    return;
  }

  const parsed = Number(trimmed);
  patch({ presetOffsetDays: Number.isNaN(parsed) ? null : parsed });
}

function presetLabel(): string {
  return props.field.hidden
    ? t("easy_form_designer.builder.label_preset_value")
    : t("easy_form_designer.builder.label_default_value");
}
</script>

<template>
  <template v-if="presetKind">
    <DSTextField
      v-if="presetKind === 'text'"
      :model-value="typeof field.presetValue === 'string' ? field.presetValue : ''"
      name="preset_value"
      :label="presetLabel()"
      @update:model-value="(v: string) => setPresetText(v)"
    />

    <DSNumberField
      v-if="presetKind === 'number'"
      :model-value="typeof field.presetValue === 'string' ? field.presetValue : null"
      name="preset_value"
      :label="presetLabel()"
      @update:model-value="(v: string | number | null) => setPresetNumber(v)"
    />

    <DSSelect
      v-if="presetKind === 'choice'"
      name="preset_value"
      :model-value="presetSingleValue"
      :options="presetOptions"
      :loading="presetOptionsLoading"
      :label="presetLabel()"
      @update:model-value="(v) => setPresetChoice(v as PresetOption | null)"
    />

    <DSSelect
      v-if="presetKind === 'multi_choice'"
      name="preset_value"
      multiple
      :model-value="presetMultiValue"
      :options="presetOptions"
      :loading="presetOptionsLoading"
      :label="
        field.hidden
          ? t('easy_form_designer.builder.label_preset_values')
          : t('easy_form_designer.builder.label_default_values')
      "
      @update:model-value="(v) => setPresetMulti(v as PresetOption[] | null)"
    />

    <template v-if="presetKind === 'date'">
      <DSSelect
        name="preset_date_mode"
        :model-value="presetDateModeValue"
        :options="presetDateModeOptions"
        :label="presetLabel()"
        @update:model-value="(v) => setPresetDateMode(v as DateBoundModeOption | null)"
      />
      <DSDatepicker
        v-if="presetDateMode === 'fixed'"
        name="preset_value"
        :label="t('easy_form_designer.builder.label_date_value')"
        :model-value="toDayjs(typeof field.presetValue === 'string' ? field.presetValue : null)"
        @update:model-value="(v: Dayjs | null) => setPresetFixedDate(v)"
      />
      <DSNumberField
        v-if="presetDateMode === 'offset'"
        :model-value="field.presetOffsetDays"
        name="preset_offset_days"
        :label="t('easy_form_designer.builder.label_days')"
        allow-negative
        @update:model-value="(v: string | number | null) => setPresetOffset(v)"
      />
    </template>

    <p v-if="field.hidden && !hasPreset" class="efd-preset__warning">
      {{ t("easy_form_designer.builder.caption_hidden_requires_preset") }}
    </p>
    <p v-else class="caption">
      {{
        field.hidden
          ? t("easy_form_designer.builder.caption_hidden_written")
          : t("easy_form_designer.builder.caption_default_shown")
      }}
    </p>
  </template>
</template>

<style scoped lang="scss">
.efd-preset__warning {
  color: var(--Colors-Danger-500, #ff1066);
  font-size: var(--Scale-FontSize-2, 12px);
}
</style>
