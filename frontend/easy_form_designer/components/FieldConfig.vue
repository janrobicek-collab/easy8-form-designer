<script setup lang="ts">
import dayjs, { type Dayjs } from "dayjs";
import { computed, ref, watch } from "vue";
import { DSDatepicker, DSNumberField, DSSelect, DSSwitch, DSTextField } from "@/src/design_system";
import type {
  DateBoundMode,
  FormField,
  FormSection,
  MappingOption,
  PresetOption,
  ValidationFormat,
} from "../types";
import { DATE_RANGE_WIDGETS, FILE_WIDGETS, RANGE_WIDGETS, VALIDATION_FORMAT_WIDGETS } from "../types";

const props = defineProps<{
  field: FormField | null;
  options: MappingOption[];
  loading: boolean;
  presetOptions: PresetOption[];
  presetOptionsLoading: boolean;
  // PRD M11 — every section on the form, for the "Move to section" picker.
  sections: FormSection[];
}>();

const emit = defineEmits<{ update: [field: FormField] }>();

// DSSelect's v-model is the selected OPTION OBJECT itself, matched by
// reference/value against the `options` array — not a plain string. Passing
// a string here (as an earlier version of this file did) makes the select
// silently unresponsive: nothing ever matches, and the object DSSelect emits
// back on @update:model-value has no .split() method, so the handler throws.
// A unique `value` per option is still needed for DSOptionList's internal
// selection bookkeeping, so it's kept as the same "type:rawValue" string;
// `type`/`rawValue` travel alongside it as plain extra keys on the option.
interface SelectOption {
  label: string;
  value: string;
  type: MappingOption["type"];
  rawValue: MappingOption["value"];
}

const selectOptions = computed<SelectOption[]>(() =>
  props.options.map((o) => ({
    label: o.label,
    value: `${o.type}:${o.value}`,
    type: o.type,
    rawValue: o.value,
  }))
);

const mappingValue = computed<SelectOption | null>(() => {
  if (!props.field) return null;

  return (
    selectOptions.value.find((o) =>
      props.field?.customFieldId
        ? o.type === "custom_field" && o.rawValue === props.field.customFieldId
        : o.type === "native" && o.rawValue === props.field?.mappedAttribute
    ) ?? null
  );
});

function patch(changes: Partial<FormField>): void {
  if (!props.field) return;
  emit("update", { ...props.field, ...changes });
}

function setMapping(option: SelectOption | null): void {
  patch({
    mappedAttribute: option?.type === "native" ? String(option.rawValue) : null,
    customFieldId: option?.type === "custom_field" ? Number(option.rawValue) : null,
  });
}

// PRD M7. Only shown for widgets the model actually accepts a rule on —
// FormField#validation_format_matches_widget / #range_matches_widget reject the
// rest, so offering them here would just produce a save that fails.
const supportsValidationFormat = computed(
  () => !!props.field && VALIDATION_FORMAT_WIDGETS.includes(props.field.widget)
);
const supportsRange = computed(
  () => !!props.field && RANGE_WIDGETS.includes(props.field.widget)
);
const supportsDateRange = computed(
  () => !!props.field && DATE_RANGE_WIDGETS.includes(props.field.widget)
);

// PRD M13. A file field's answer is uploaded files, so neither half of M8
// applies to it: there is no preset file to stamp, and the model rejects
// `hidden` on it outright (FormField#file_widget_cannot_be_hidden). Gate the
// controls rather than offering ones the save would reject — the same reason
// supportsValidationFormat/supportsRange gate theirs.
const isFileField = computed(() => !!props.field && FILE_WIDGETS.includes(props.field.widget));

// PRD M11. There is no drag-and-drop in this builder — a field is appended
// on creation and never moved — so this dropdown is how a field changes
// section without being deleted and re-added.
interface SectionOption {
  label: string;
  value: string;
  sectionId: number | string | null;
}

const sectionOptions = computed<SectionOption[]>(() => [
  { label: "Ungrouped", value: "none", sectionId: null },
  ...props.sections.map((s) => ({ label: s.name, value: String(s.id), sectionId: s.id })),
]);

const sectionValue = computed<SectionOption | null>(
  () => sectionOptions.value.find((o) => o.sectionId === (props.field?.sectionId ?? null)) ?? null
);

// Same DSSelect contract as the "Maps to" select above: v-model is the option
// OBJECT, matched out of `options`, never a bare string. "None" is a real
// option with a null rawValue rather than an absent selection, so clearing a
// rule is an explicit choice the author can see and make.
interface FormatOption {
  label: string;
  value: string;
  rawValue: ValidationFormat | null;
}

const formatOptions: FormatOption[] = [
  { label: "None", value: "none", rawValue: null },
  { label: "Email", value: "email", rawValue: "email" },
  { label: "URL (http:// or https://)", value: "url", rawValue: "url" },
];

const formatValue = computed<FormatOption | null>(() => {
  if (!props.field) return null;

  return (
    formatOptions.find((o) => o.rawValue === (props.field?.validationFormat ?? null)) ?? null
  );
});

function setValidationFormat(option: FormatOption | null): void {
  patch({ validationFormat: option?.rawValue ?? null });
}

// "" from a cleared DSNumberField must persist as null, not as the string "",
// which Rails would cast to 0 on a decimal column — silently inventing a bound
// of zero where the author meant "no bound".
function setBound(key: "minValue" | "maxValue", raw: string | number | null): void {
  const value = raw === null || raw === undefined || `${raw}`.trim() === "" ? null : `${raw}`;
  patch({ [key]: value } as Partial<FormField>);
}

// A date bound is either a fixed date or a day offset from today — the model
// rejects both being set on the same side (FormField#date_bounds_not_double_specified).
// "Mode" has to be tracked as separate local state rather than derived purely
// from minDate/minDateOffsetDays: while the author is filling in a brand-new
// "Fixed date" bound, minDate is still null (nothing picked yet), and if mode
// were derived from the data alone it would read back as "No limit" and the
// picker the author just opened would vanish under them.
interface DateBoundModeOption {
  label: string;
  value: DateBoundMode;
}

const dateBoundModeOptions: DateBoundModeOption[] = [
  { label: "No limit", value: "none" },
  { label: "Fixed date", value: "fixed" },
  { label: "Days from today", value: "offset" },
];

function deriveDateBoundMode(date: string | null | undefined, offsetDays: number | null | undefined): DateBoundMode {
  if (offsetDays !== null && offsetDays !== undefined) return "offset";
  if (date) return "fixed";
  return "none";
}

const minDateMode = ref<DateBoundMode>("none");
const maxDateMode = ref<DateBoundMode>("none");

// PRD M8's date preset reuses the same mode-tracking pattern; declared here
// (not down by the rest of the preset logic) so the single watch below can
// derive all three modes together on a field switch.
const presetDateMode = ref<DateBoundMode>("none");

// Re-derived only when the SELECTED FIELD changes (a different token) — every
// keystroke elsewhere replaces `field` with a new object of the same field
// (see FormBuilder's updateField), which must not reset the mode mid-edit.
watch(
  () => props.field?.token,
  () => {
    minDateMode.value = deriveDateBoundMode(props.field?.minDate, props.field?.minDateOffsetDays);
    maxDateMode.value = deriveDateBoundMode(props.field?.maxDate, props.field?.maxDateOffsetDays);
    presetDateMode.value = deriveDateBoundMode(
      Array.isArray(props.field?.presetValue) ? null : (props.field?.presetValue ?? null),
      props.field?.presetOffsetDays
    );
  },
  { immediate: true }
);

const minDateModeValue = computed<DateBoundModeOption | null>(
  () => dateBoundModeOptions.find((o) => o.value === minDateMode.value) ?? null
);
const maxDateModeValue = computed<DateBoundModeOption | null>(
  () => dateBoundModeOptions.find((o) => o.value === maxDateMode.value) ?? null
);

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

// DSDatepicker's own v-model is a Dayjs, not the plain ISO date string every
// other layer of this feature uses (the DB column, the JSON API, FormField's
// TS type) — converted only at this boundary so nothing else has to know
// about Dayjs.
function toDayjs(iso: string | null | undefined): Dayjs | null {
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

// PRD M8 — hidden/preset fields. "Hidden" and "Required" are mutually
// exclusive in the model (FormField#clear_required_when_hidden forces
// required back to false server-side); patched together here so the UI
// never shows a stale, silently-ineffective Required switch after turning
// Hidden on.
function setHidden(value: boolean): void {
  if (!props.field) return;
  patch({ hidden: value, required: value ? false : props.field.required });
}

// A preset is configured at all — fixed value (any widget) or day offset
// (date only). Mirrors FormField#preset?.
const hasPreset = computed(() => {
  if (!props.field) return false;
  if (props.field.presetOffsetDays !== null) return true;

  return Array.isArray(props.field.presetValue) ? props.field.presetValue.length > 0 : !!props.field.presetValue;
});

// Which control the preset editor renders — grouped by shape, not by widget
// 1:1: a Dropdown/Radio/User-lookup/Checkbox preset is all "pick one of a
// server-provided list" even though only some of them are CHOICE_WIDGETS on
// the model (checkbox's Yes/No pair comes from FormField#preset_options the
// same way, just via a different branch server-side).
type PresetKind = "text" | "number" | "choice" | "multi_choice" | "date";

const presetKind = computed<PresetKind | null>(() => {
  switch (props.field?.widget) {
    case "text":
    case "long_text":
      return "text";
    case "number":
      return "number";
    case "select":
    case "radio":
    case "user":
    case "checkbox":
      return "choice";
    case "multi_select":
      return "multi_choice";
    case "date":
      return "date";
    default:
      return null;
  }
});

function setPresetText(value: string): void {
  patch({ presetValue: value === "" ? null : value });
}

// Same "" -> null rule as setBound above: a cleared number must not persist
// as "", which the preset_value TEXT column would otherwise store literally
// (unlike a decimal column, it wouldn't even get cast to 0 — but an empty
// string is still not "no preset", it's a stored blank).
function setPresetNumber(raw: string | number | null): void {
  const value = raw === null || raw === undefined || `${raw}`.trim() === "" ? null : `${raw}`;
  patch({ presetValue: value });
}

// Same DSSelect object-model-value contract as "Maps to" / "Validation"
// above. presetOptions already comes from the server as the exact legal set
// for this field's current mapping (EasyFormDesignerFormsController#preset_options),
// so no separate validation list is kept here.
const presetSingleValue = computed<PresetOption | null>(() => {
  if (!props.field || Array.isArray(props.field.presetValue)) return null;

  return props.presetOptions.find((o) => o.value === props.field?.presetValue) ?? null;
});

function setPresetChoice(option: PresetOption | null): void {
  patch({ presetValue: option?.value ?? null });
}

// multi_select's DSSelect multiple: true — v-model is an ARRAY of the
// selected option objects (DSMultiSelectModelValue), matched out of
// presetOptions the same way the single-choice case matches one.
const presetMultiValue = computed<PresetOption[]>(() => {
  const raw = Array.isArray(props.field?.presetValue) ? props.field.presetValue : [];
  return props.presetOptions.filter((o) => raw.includes(o.value));
});

function setPresetMulti(selected: PresetOption[] | null): void {
  patch({ presetValue: (selected ?? []).map((o) => o.value) });
}

// The date preset reuses the exact three-mode pattern (none/fixed/offset)
// already built for date bounds below — including tracking mode as separate
// local state rather than deriving it purely from the data, for the same
// reason: while the author is filling in a brand-new "Fixed date" preset,
// presetValue is still null (nothing picked yet), and a purely-derived mode
// would read that back as "No preset" and the picker would vanish under them.
// Reuses the DateBoundModeOption shape/type declared above for the min/max
// date-bound mode selects — presetDateMode itself is declared further up,
// beside minDateMode/maxDateMode, so the single field-switch watch can
// derive all three together.
const presetDateModeOptions: DateBoundModeOption[] = [
  { label: "No preset", value: "none" },
  { label: "Fixed date", value: "fixed" },
  { label: "Days from today", value: "offset" },
];

const presetDateModeValue = computed<DateBoundModeOption | null>(
  () => presetDateModeOptions.find((o) => o.value === presetDateMode.value) ?? null
);

function setPresetDateMode(option: DateBoundModeOption | null): void {
  presetDateMode.value = option?.value ?? "none";
  patch({ presetValue: null, presetOffsetDays: null });
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

// Each widget maps to a semantically-matching native attribute only — a
// single-line Text field to Subject, a multi-line Long text field to
// Description, and so on — never both. Nothing else in the UI explains
// this, so a field author who only ever tries "Text" fields sees just
// "Subject" on offer and has no way to tell that's by design rather than
// a bug (reported exactly this way).
const widgetHint = computed<string | null>(() => {
  switch (props.field?.widget) {
    case "text":
      return "A Text field maps to Subject or a matching custom field. To map to Description, use a Long text field instead.";
    case "long_text":
      return "A Long text field maps to Description or a matching custom field.";
    case "select":
      return "A Dropdown field maps to Priority, Status, Category, or a matching custom field.";
    case "date":
      return "A Date field maps to Due date, Start date, or a matching custom field.";
    case "number":
      return "A Number field maps to Estimated time or a matching custom field.";
    case "radio":
      return "A Radio buttons field maps to Priority, Status, Category, or a matching custom field.";
    case "multi_select":
      return "A Multi-select field maps to a matching custom field only — no native attribute takes multiple values.";
    case "checkbox":
      return "A Checkbox field maps to a matching custom field only — no native attribute is boolean today.";
    case "user":
      return "A User lookup field maps to Assignee or a matching custom field.";
    case "file":
      return "A File upload field always attaches to the task's Files — it has no other target, and cannot be hidden or preset.";
    default:
      return null;
  }
});
</script>

<template>
  <aside v-if="field" class="efd-config">
    <h3 class="efd-config__title">Field settings</h3>

    <DSTextField
      :model-value="field.label"
      label="Label"
      required
      @update:model-value="(v: string) => patch({ label: v })"
    />

    <DSTextField
      :model-value="field.helpText ?? ''"
      label="Help text"
      @update:model-value="(v: string) => patch({ helpText: v })"
    />

    <!-- Required is meaningless on a hidden field — its answer always comes
         from the preset below, never from requester input — so the switch
         is hidden entirely rather than shown disabled, matching the model
         forcing required back to false server-side (clear_required_when_hidden). -->
    <DSSwitch
      v-if="!field.hidden"
      :model-value="field.required"
      name="required"
      label="Required"
      @update:model-value="(v: boolean) => patch({ required: v })"
    />

    <!-- PRD M8 — hidden/preset fields. A hidden field renders NO input at all
         on the requester form; its value comes solely from the preset below.
         Not offered for a file field: there is no preset file to stamp. -->
    <template v-if="!isFileField">
      <DSSwitch
        :model-value="field.hidden"
        name="hidden"
        label="Hidden from requester"
        @update:model-value="(v: boolean) => setHidden(v)"
      />
      <p class="caption">
        Silently stamps this field's value at submission — the requester never sees it.
      </p>
    </template>

    <!-- PRD M11 — which section this field belongs to, if any. -->
    <DSSelect
      v-if="sections.length"
      name="section_id"
      :model-value="sectionValue"
      :options="sectionOptions"
      label="Section"
      @update:model-value="(v) => patch({ sectionId: (v as SectionOption | null)?.sectionId ?? null })"
    />

    <!-- Mandatory. A field with no mapping cannot be published, and its
         options would be empty anyway — the list comes from the mapped
         attribute, never from field-local config. -->
    <DSSelect
      name="mapped_attribute"
      :model-value="mappingValue"
      :options="selectOptions"
      :loading="loading"
      label="Maps to"
      required
      @update:model-value="(v) => setMapping(v as SelectOption | null)"
    />
    <p class="caption">
      Every field must write to a real task attribute.<template v-if="widgetHint"> {{ widgetHint }}</template>
    </p>

    <p v-if="!loading && !options.length" class="efd-config__warning">
      No attributes of this type exist for the selected project and task type.
    </p>

    <!-- PRD M7 — format validation, on the widgets that support it. -->
    <template v-if="supportsValidationFormat">
      <DSSelect
        name="validation_format"
        :model-value="formatValue"
        :options="formatOptions"
        label="Validation"
        @update:model-value="(v) => setValidationFormat(v as FormatOption | null)"
      />
      <p class="caption">
        Checked when the form is submitted. A URL must include http:// or https://.
      </p>
    </template>

    <template v-if="supportsRange">
      <DSNumberField
        :model-value="field.minValue"
        name="min_value"
        label="Minimum"
        @update:model-value="(v: string | number | null) => setBound('minValue', v)"
      />
      <DSNumberField
        :model-value="field.maxValue"
        name="max_value"
        label="Maximum"
        @update:model-value="(v: string | number | null) => setBound('maxValue', v)"
      />
      <p class="caption">Leave a bound empty for no limit.</p>
    </template>

    <template v-if="supportsDateRange">
      <DSSelect
        name="min_date_mode"
        :model-value="minDateModeValue"
        :options="dateBoundModeOptions"
        label="Earliest allowed date"
        @update:model-value="(v) => setDateBoundMode('min', v as DateBoundModeOption | null)"
      />
      <DSDatepicker
        v-if="minDateMode === 'fixed'"
        name="min_date"
        label="On or after"
        :model-value="toDayjs(field.minDate)"
        @update:model-value="(v: Dayjs | null) => setFixedDate('minDate', v)"
      />
      <DSNumberField
        v-if="minDateMode === 'offset'"
        :model-value="field.minDateOffsetDays"
        name="min_date_offset_days"
        label="Days from today"
        allow-negative
        @update:model-value="(v: string | number | null) => setDateOffset('minDateOffsetDays', v)"
      />

      <DSSelect
        name="max_date_mode"
        :model-value="maxDateModeValue"
        :options="dateBoundModeOptions"
        label="Latest allowed date"
        @update:model-value="(v) => setDateBoundMode('max', v as DateBoundModeOption | null)"
      />
      <DSDatepicker
        v-if="maxDateMode === 'fixed'"
        name="max_date"
        label="On or before"
        :model-value="toDayjs(field.maxDate)"
        @update:model-value="(v: Dayjs | null) => setFixedDate('maxDate', v)"
      />
      <DSNumberField
        v-if="maxDateMode === 'offset'"
        :model-value="field.maxDateOffsetDays"
        name="max_date_offset_days"
        label="Days from today"
        allow-negative
        @update:model-value="(v: string | number | null) => setDateOffset('maxDateOffsetDays', v)"
      />

      <p class="caption">
        A day offset is negative for the past, positive for the future (e.g. -7 rejects
        anything more than a week ago). Evaluated on the day the requester submits, not today.
        There is no in-browser check for this rule — the requester form validates it entirely
        on submit.
      </p>
    </template>

    <!-- PRD M8 — the preset itself. Hidden and Not-mapped states have
         different meanings for the same control: hidden makes this the
         field's ONLY source of truth (required, enforced server-side by
         FormField#hidden_requires_preset); visible makes it an optional
         default the requester sees pre-filled and may change or clear. -->
    <template v-if="presetKind && !isFileField">
      <h3 class="efd-config__title">
        {{ field.hidden ? "Preset value" : "Default value" }}
      </h3>

      <DSTextField
        v-if="presetKind === 'text'"
        :model-value="typeof field.presetValue === 'string' ? field.presetValue : ''"
        name="preset_value"
        :label="field.hidden ? 'Preset value' : 'Default value'"
        @update:model-value="(v: string) => setPresetText(v)"
      />

      <DSNumberField
        v-if="presetKind === 'number'"
        :model-value="typeof field.presetValue === 'string' ? field.presetValue : null"
        name="preset_value"
        :label="field.hidden ? 'Preset value' : 'Default value'"
        @update:model-value="(v: string | number | null) => setPresetNumber(v)"
      />

      <DSSelect
        v-if="presetKind === 'choice'"
        name="preset_value"
        :model-value="presetSingleValue"
        :options="presetOptions"
        :loading="presetOptionsLoading"
        :label="field.hidden ? 'Preset value' : 'Default value'"
        @update:model-value="(v) => setPresetChoice(v as PresetOption | null)"
      />

      <DSSelect
        v-if="presetKind === 'multi_choice'"
        name="preset_value"
        multiple
        :model-value="presetMultiValue"
        :options="presetOptions"
        :loading="presetOptionsLoading"
        :label="field.hidden ? 'Preset values' : 'Default values'"
        @update:model-value="(v) => setPresetMulti(v as PresetOption[] | null)"
      />

      <template v-if="presetKind === 'date'">
        <DSSelect
          name="preset_date_mode"
          :model-value="presetDateModeValue"
          :options="presetDateModeOptions"
          :label="field.hidden ? 'Preset value' : 'Default value'"
          @update:model-value="(v) => setPresetDateMode(v as DateBoundModeOption | null)"
        />
        <DSDatepicker
          v-if="presetDateMode === 'fixed'"
          name="preset_value"
          label="Date"
          :model-value="toDayjs(typeof field.presetValue === 'string' ? field.presetValue : null)"
          @update:model-value="(v: Dayjs | null) => setPresetFixedDate(v)"
        />
        <DSNumberField
          v-if="presetDateMode === 'offset'"
          :model-value="field.presetOffsetDays"
          name="preset_offset_days"
          label="Days from today"
          allow-negative
          @update:model-value="(v: string | number | null) => setPresetOffset(v)"
        />
      </template>

      <p v-if="field.hidden && !hasPreset" class="efd-config__warning">
        A field hidden from the requester must have a preset value.
      </p>
      <p v-else class="caption">
        {{
          field.hidden
            ? "Written to the task on every submission. The requester never sees this field."
            : "Shown to the requester pre-filled. They may change or clear it before submitting."
        }}
      </p>
    </template>
  </aside>

  <aside v-else class="efd-config efd-config--empty">
    <p>Select a field to configure it.</p>
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

  &__warning {
    color: var(--Colors-Danger-500, #ff1066);
    font-size: var(--Scale-FontSize-2, 12px);
  }

  &--empty {
    color: var(--Colors-Greys-500, #5c6268);
  }
}
</style>
