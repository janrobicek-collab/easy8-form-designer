<script setup lang="ts">
import { computed } from "vue";
import { DSBadge } from "@/src/design_system";
import type { FormField, FormSection } from "../types";
import { tokenPlaceholder } from "../types";

const props = defineProps<{
  fields: FormField[];
  sections: FormSection[];
  selectedToken: string | null;
  selectedSectionId: number | string | null;
}>();

defineEmits<{
  select: [field: FormField];
  remove: [field: FormField];
  selectSection: [section: FormSection];
  removeSection: [section: FormSection];
}>();

interface CanvasRow {
  key: string;
  section?: FormSection;
  field?: FormField;
}

// PRD M11. Deliberately the SAME algorithm the requester view uses (walk the
// fields in order, emit a heading whenever the run moves into a different
// section) rather than grouping them — so what the author sees here is the
// order the requester will actually get, interleaving included, instead of a
// tidier lie.
//
// Sections with no fields yet are appended at the end: a section the author
// just created has to be visible and selectable before anything is in it.
const rows = computed<CanvasRow[]>(() => {
  const out: CanvasRow[] = [];
  const seen = new Set<number | string>();
  let currentSectionId: number | string | null | undefined;

  props.fields.forEach((field) => {
    if (field.sectionId !== currentSectionId) {
      currentSectionId = field.sectionId;
      const section = props.sections.find((s) => s.id === field.sectionId);
      if (section) {
        seen.add(section.id);
        out.push({ key: `section-${section.id}-${field.token}`, section });
      }
    }
    out.push({ key: `field-${field.token}`, field });
  });

  props.sections
    .filter((s) => !seen.has(s.id))
    .forEach((section) => out.push({ key: `section-${section.id}-empty`, section }));

  return out;
});

// A compact restatement of the rule for the card. The operator's own
// translated label lives in the config panel (it comes from the server with
// the field's filter type); repeating the raw symbol here would be noise, so
// the card just names the field and the value it's gated on.
function ruleSummary(section: FormSection): string | null {
  if (section.visibilityFieldId == null) return null;

  const field = props.fields.find((f) => f.id === section.visibilityFieldId);
  const values = section.visibilityValues ?? [];
  const target = values.length ? values.join(", ") : "a value";

  return `Shown by ${field?.label ?? "a field"} · ${target}`;
}

// PRD M8. A raw summary of whatever preset is configured — not the resolved
// human label (that needs the same server round trip FieldConfig's preset
// picker makes, which this list-of-cards view has no reason to duplicate for
// every field at once) — just enough for an author scanning the canvas to
// see at a glance which fields carry one.
function presetSummary(field: FormField): string | null {
  if (field.presetOffsetDays !== null) {
    return `today ${field.presetOffsetDays >= 0 ? "+" : ""}${field.presetOffsetDays}d`;
  }
  if (Array.isArray(field.presetValue)) {
    return field.presetValue.length ? field.presetValue.join(", ") : null;
  }

  return field.presetValue || null;
}
</script>

<template>
  <section class="efd-canvas">
    <p v-if="!fields.length" class="efd-canvas__empty">
      Add a field from the palette to start building this form.
    </p>

    <template v-for="row in rows" :key="row.key">
      <!-- PRD M11 — a section heading. Selecting it opens the section's own
           settings, and any field added while it is selected joins it. -->
      <div
        v-if="row.section"
        class="efd-canvas__section"
        :class="{ 'is-selected': row.section.id === selectedSectionId }"
        :data-cy="`form-designer-canvas__section-${row.section.token}`"
        @click="$emit('selectSection', row.section)"
      >
        <header class="efd-canvas__head">
          <span class="efd-canvas__label">{{ row.section.name }}</span>

          <div class="efd-canvas__head-actions">
            <DSBadge v-if="row.section.visibilityFieldId != null" text="Conditional" state="info" />
            <button
              type="button"
              class="efd-canvas__remove"
              @click.stop="$emit('removeSection', row.section)"
            >
              Remove
            </button>
          </div>
        </header>

        <p v-if="ruleSummary(row.section)" class="efd-canvas__help">{{ ruleSummary(row.section) }}</p>
      </div>

      <article
        v-else-if="row.field"
        class="efd-canvas__card"
        :class="{
          'is-selected': row.field.token === selectedToken,
          'is-in-section': row.field.sectionId != null,
        }"
        :data-cy="`form-designer-canvas__${row.field.token}`"
        @click="$emit('select', row.field)"
      >
        <header class="efd-canvas__head">
          <span class="efd-canvas__label">
            {{ row.field.label }}
            <abbr v-if="row.field.required" title="Required">*</abbr>
          </span>

          <div class="efd-canvas__head-actions">
            <!-- PRD M8 — a hidden field never renders on the requester form at
                 all, which is easy to forget while scanning a long field list
                 in the config panel alone. -->
            <DSBadge v-if="row.field.hidden" text="Hidden" state="info" />

            <!-- An unmapped field blocks publishing, so surface it on the card
                 itself rather than only in the config panel. -->
            <DSBadge
              :text="row.field.mappedAttribute || row.field.customFieldId ? 'Mapped' : 'Not mapped'"
              :state="row.field.mappedAttribute || row.field.customFieldId ? 'success' : 'error'"
            />

            <button type="button" class="efd-canvas__remove" @click.stop="$emit('remove', row.field)">
              Remove
            </button>
          </div>
        </header>

        <p v-if="row.field.helpText" class="efd-canvas__help">{{ row.field.helpText }}</p>
        <p v-if="presetSummary(row.field)" class="efd-canvas__help">
          {{ row.field.hidden ? "Preset" : "Default" }}: {{ presetSummary(row.field) }}
        </p>
        <code class="efd-canvas__token">{{ tokenPlaceholder(row.field.token) }}</code>
      </article>
    </template>
  </section>
</template>

<style scoped lang="scss">
.efd-canvas {
  display: flex;
  flex-direction: column;
  gap: var(--Scale-Size-3, 12px);

  &__empty {
    color: var(--Colors-Greys-500, #5c6268);
  }

  &__card {
    position: relative;
    padding: var(--Scale-Size-4, 16px);
    border: 1px solid var(--Colors-Greys-200, #dadee1);
    border-radius: var(--Scale-Radius-2, 6px);
    background: var(--Colors-Common-White, #fff);
    cursor: pointer;

    &.is-selected {
      border-color: var(--Colors-Primary-500, #0d65f2);
      box-shadow: 0 0 0 2px var(--Colors-Primary-200, #b4cffb);
    }

    // Indented under its section's heading, so membership is visible at a
    // glance rather than only in the config panel.
    &.is-in-section {
      margin-left: var(--Scale-Size-5, 20px);
    }
  }

  // PRD M11 — a section heading. Visually distinct from a field card so the
  // grouping reads as structure rather than as another question.
  &__section {
    padding: var(--Scale-Size-3, 12px) var(--Scale-Size-4, 16px);
    border-left: 3px solid var(--Colors-Primary-500, #0d65f2);
    border-radius: var(--Scale-Radius-2, 6px);
    background: var(--Colors-Greys-50, #f5f6f7);
    cursor: pointer;

    &.is-selected {
      box-shadow: 0 0 0 2px var(--Colors-Primary-200, #b4cffb);
    }

    .efd-canvas__label {
      font-weight: 700;
    }
  }

  &__head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--Scale-Size-2, 8px);
  }

  // A sibling of the badge in the flex header, not absolutely positioned
  // over it — an earlier version stacked both in the same top-right corner,
  // so on hover "Remove" rendered directly on top of "Mapped"/"Not mapped".
  &__head-actions {
    display: flex;
    align-items: center;
    gap: var(--Scale-Size-2, 8px);
    flex-shrink: 0;
  }

  &__label {
    font-weight: 600;
  }

  &__help,
  &__token {
    display: block;
    margin-top: var(--Scale-Size-1, 4px);
    font-size: var(--Scale-FontSize-2, 12px);
    color: var(--Colors-Greys-500, #5c6268);
  }

  &__remove {
    border: none;
    background: none;
    color: var(--Colors-Danger-500, #ff1066);
    cursor: pointer;
    opacity: 0;
  }

  &__card:hover &__remove {
    opacity: 1;
  }
}
</style>
