<script setup lang="ts">
import { computed, inject, ref, watch } from "vue";
import { DSBadge, DSFieldset, DSIcon, DSSelect, DSSwitch, DSTextField } from "@/src/design_system";
import type { FormField, FormSection, MappingOption, Widget } from "../types";
import { WIDGETS, tokenPlaceholder } from "../types";
import { BUILDER_CONTEXT_KEY } from "../constants/injectionKeys";
import { useMappingOptions } from "../composables/useMappingOptions";
import { useFormBuilderStore } from "../store/formBuilderStore";
import DragHandle from "./DragHandle.vue";
import FieldAdvanced from "./FieldAdvanced.vue";

const props = defineProps<{ section: FormSection; field: FormField }>();

const store = useFormBuilderStore();
const context = inject(BUILDER_CONTEXT_KEY)!;
const t = window.EasyLocale.getLocale;

function patch(changes: Partial<FormField>): void {
  store.patchField(props.field, changes);
}

const widgetLabels: Record<Widget, string> = {
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

interface WidgetOption {
  label: string;
  value: Widget;
}

const widgetOptions: WidgetOption[] = WIDGETS.map((w) => ({ label: widgetLabels[w], value: w }));
const widgetValue = computed(() => widgetOptions.find((o) => o.value === props.field.widget) ?? null);

function setWidget(option: WidgetOption | null): void {
  if (!option) return;
  // Switching widget invalidates whatever this field was mapped to, and any
  // rule (validation, range, preset) authored for the previous widget —
  // FormField's own model validations would reject a mismatched combination
  // outright, so clearing them here is what keeps the row from silently
  // holding a save that's already doomed to fail.
  patch({
    widget: option.value,
    mappedAttribute: null,
    customFieldId: null,
    validationFormat: null,
    minValue: null,
    maxValue: null,
    minDate: null,
    maxDate: null,
    minDateOffsetDays: null,
    maxDateOffsetDays: null,
    hidden: false,
    presetValue: null,
    presetOffsetDays: null,
  });
}

// DSSelect's v-model is the selected OPTION OBJECT itself, matched by
// reference/value against the `options` array — not a plain string.
interface MapOption {
  label: string;
  value: string;
  type: MappingOption["type"];
  rawValue: MappingOption["value"];
}

const { options, loading, load } = useMappingOptions(context);

watch(() => props.field.widget, (widget) => void load(widget), { immediate: true });

const mapOptions = computed<MapOption[]>(() =>
  options.value.map((o) => ({ label: o.label, value: `${o.type}:${o.value}`, type: o.type, rawValue: o.value }))
);

const mappingValue = computed<MapOption | null>(
  () =>
    mapOptions.value.find((o) =>
      props.field.customFieldId
        ? o.type === "custom_field" && o.rawValue === props.field.customFieldId
        : o.type === "native" && o.rawValue === props.field.mappedAttribute
    ) ?? null
);

function setMapping(option: MapOption | null): void {
  patch({
    mappedAttribute: option?.type === "native" ? String(option.rawValue) : null,
    customFieldId: option?.type === "custom_field" ? Number(option.rawValue) : null,
  });
}

const mapped = computed(() => !!props.field.mappedAttribute || !!props.field.customFieldId);

const advancedOpen = ref(false);
</script>

<template>
  <div class="efd-field-row">
    <DragHandle :data-cy="`handle__drag--field-${field.token}`" />

    <DSFieldset
      :name="field.token"
      removable
      with-border
      :data-cy="`section__field--${field.token}`"
      @remove="store.removeField(section, field)"
    >
      <template #actions>
        <DSBadge v-if="field.hidden" :text="t('easy_form_designer.builder.label_hidden_badge')" state="info" />
        <DSBadge
          :text="mapped ? t('easy_form_designer.builder.label_mapped') : t('easy_form_designer.builder.label_not_mapped')"
          :state="mapped ? 'success' : 'danger'"
        />
      </template>

      <div class="efd-field-row__grid">
        <div class="efd-field-row__col efd-field-row__col--type">
          <DSSelect
            name="widget"
            :model-value="widgetValue"
            :options="widgetOptions"
            required
            :label="t('easy_form_designer.builder.label_field_type')"
            @update:model-value="(v) => setWidget(v as WidgetOption | null)"
          />
        </div>

        <div class="efd-field-row__col efd-field-row__col--label">
          <DSTextField
            :model-value="field.label"
            required
            :label="t('easy_form_designer.builder.label_field_label')"
            @update:model-value="(v: string) => patch({ label: v })"
          />
        </div>

        <div class="efd-field-row__col efd-field-row__col--maps-to">
          <DSSelect
            name="mapped_attribute"
            :model-value="mappingValue"
            :options="mapOptions"
            :loading="loading"
            required
            :label="t('easy_form_designer.builder.label_maps_to')"
            @update:model-value="(v) => setMapping(v as MapOption | null)"
          />
        </div>
      </div>

      <DSTextField
        :model-value="field.helpText ?? ''"
        :label="t('easy_form_designer.builder.label_help_text')"
        @update:model-value="(v: string) => patch({ helpText: v })"
      />

      <div class="efd-field-row__footer">
        <DSSwitch
          v-if="!field.hidden"
          :model-value="field.required"
          name="required"
          :label="t('easy_form_designer.builder.label_required')"
          @update:model-value="(v: boolean) => patch({ required: v })"
        />
        <code class="efd-field-row__token">{{ tokenPlaceholder(field.token) }}</code>

        <button
          type="button"
          class="efd-field-row__advanced-toggle"
          :data-cy="`toggle__expand--field-advanced-${field.token}`"
          @click="advancedOpen = !advancedOpen"
        >
          <DSIcon :icon="advancedOpen ? 'arrow-up' : 'arrow-down'" size="sm" />
          {{ t("easy_form_designer.builder.toggle_advanced") }}
        </button>
      </div>

      <FieldAdvanced v-if="advancedOpen" :field="field" />
    </DSFieldset>
  </div>
</template>

<style scoped lang="scss">
.efd-field-row {
  display: flex;
  align-items: flex-start;
  gap: var(--Scale-Size-1, 4px);

  &__grid {
    display: grid;
    grid-template-columns: repeat(12, 1fr);
    gap: var(--Scale-Size-3, 12px);
  }

  &__col {
    grid-column: span 12;

    @media (min-width: 720px) {
      &--type {
        grid-column: span 3;
      }

      &--label {
        grid-column: span 5;
      }

      &--maps-to {
        grid-column: span 4;
      }
    }
  }

  &__footer {
    display: flex;
    align-items: center;
    gap: var(--Scale-Size-3, 12px);
    margin-top: var(--Scale-Size-1, 4px);
  }

  &__token {
    font-size: var(--Scale-FontSize-2, 12px);
    color: var(--Colors-Greys-500, #5c6268);
  }

  &__advanced-toggle {
    display: inline-flex;
    align-items: center;
    gap: var(--Scale-Size-1, 4px);
    margin-left: auto;
    border: none;
    background: none;
    color: var(--Colors-Primary-500, #0d65f2);
    font-size: var(--Scale-FontSize-2, 12px);
    cursor: pointer;
  }
}
</style>
