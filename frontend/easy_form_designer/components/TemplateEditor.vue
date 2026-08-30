<script setup lang="ts">
import { computed } from "vue";
import { DSTextarea, DSTextField } from "@/src/design_system";
import type { EasyEditorInstance } from "@/src/ckeditor/easy_editor/types/easyEditor";
import type { FormField } from "../types";
import { tokenPlaceholder } from "../types";

// A stable id is required, not cosmetic: EasyEditor registers every live
// instance under its element id in window.CKEDITOR.instances, and that is the
// only handle we get for inserting a token at the caret.
const DESCRIPTION_EDITOR_ID = "efd-description-editor";

const TOKEN_RE = /\{\{\s*([a-zA-Z0-9_-]+)\s*\}\}/g;

const props = defineProps<{
  fields: FormField[];
  subjectTemplate: string;
  descriptionTemplate: string;
}>();

const emit = defineEmits<{
  "update:subjectTemplate": [value: string];
  "update:descriptionTemplate": [value: string];
}>();

const tokens = computed(() => props.fields.map((f) => ({ token: f.token, label: f.label })));

function escapeHtml(value: string): string {
  return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

// The template is HTML now, so the preview is rendered as HTML rather than
// printed as source. Field labels are escaped and wrapped in <mark> so a label
// containing angle brackets can't inject markup into the admin's own preview.
const preview = computed(() =>
  props.descriptionTemplate.replace(TOKEN_RE, (match, token: string) => {
    const field = props.fields.find((f) => f.token === token);
    return field ? `<mark>${escapeHtml(field.label)}</mark>` : match;
  })
);

function descriptionEditor(): EasyEditorInstance | null {
  return window.CKEDITOR?.instances?.[DESCRIPTION_EDITOR_ID] ?? null;
}

// Inserts at the caret through the editor's own model, mirroring how Easy8's
// DynamicTokens plugin inserts its tokens. Appending to the end is kept as a
// fallback for the window before the editor has finished mounting — losing the
// caret position is a far better outcome than the click doing nothing.
function insert(token: string): void {
  const placeholder = tokenPlaceholder(token);
  const editor = descriptionEditor();

  if (!editor) {
    emit("update:descriptionTemplate", `${props.descriptionTemplate}${placeholder}`);
    return;
  }

  editor.model.change((writer) => {
    const position = editor.model.document.selection.getFirstPosition();
    if (!position) return;

    writer.insertText(placeholder, position);
    writer.setSelection(position.getShiftedBy(placeholder.length));
  });

  editor.editing.view.focus();
}
</script>

<template>
  <div class="efd-templates">
    <DSTextField
      :model-value="subjectTemplate"
      label="Task subject"
      @update:model-value="(v: string) => emit('update:subjectTemplate', v)"
    />
    <p class="caption">
      Use {{ tokenPlaceholder("token") }} to insert an answer — mapping a field straight to
      Subject or Description fills its token in here automatically. The subject is plain
      text; only the description below supports formatting.
    </p>

    <DSTextarea
      :id="DESCRIPTION_EDITOR_ID"
      :model-value="descriptionTemplate"
      label="Task description"
      rich-editor
      :rows="8"
      @update:model-value="(v: string) => emit('update:descriptionTemplate', v)"
    />

    <div class="efd-templates__tokens">
      <span class="efd-templates__tokens-title">Insert a field</span>
      <button
        v-for="t in tokens"
        :key="t.token"
        type="button"
        class="efd-templates__chip"
        @click="insert(t.token)"
      >
        {{ tokenPlaceholder(t.token) }} &mdash; {{ t.label }}
      </button>
    </div>

    <section class="efd-templates__preview">
      <h4>Preview</h4>
      <div v-dompurify-html="preview" class="efd-templates__preview-body"></div>
    </section>
  </div>
</template>

<style scoped lang="scss">
.efd-templates {
  display: flex;
  flex-direction: column;
  gap: var(--Scale-Size-3, 12px);

  &__tokens {
    display: flex;
    flex-wrap: wrap;
    gap: var(--Scale-Size-2, 8px);
    align-items: center;
  }

  &__tokens-title {
    font-size: var(--Scale-FontSize-2, 12px);
    color: var(--Colors-Greys-500, #5c6268);
  }

  &__chip {
    padding: var(--Scale-Size-1, 4px) var(--Scale-Size-2, 8px);
    border: 1px solid var(--Colors-Greys-200, #dadee1);
    border-radius: var(--Scale-Radius-1, 4px);
    background: var(--Colors-Common-White, #fff);
    font-size: var(--Scale-FontSize-2, 12px);
    cursor: pointer;

    &:hover {
      background: var(--Colors-Primary-100, #f4f9ff);
    }
  }

  &__preview {
    padding: var(--Scale-Size-3, 12px);
    border: 1px solid var(--Colors-Greys-200, #dadee1);
    border-radius: var(--Scale-Radius-2, 6px);
    background: var(--Colors-Greys-100, #f4f5f6);

    h4 {
      margin: 0 0 var(--Scale-Size-2, 8px);
      font-size: var(--Scale-FontSize-2, 12px);
    }
  }

  &__preview-body {
    // Matches how the created task renders it — block elements from the editor
    // keep their own spacing, so no white-space override here.
    word-break: break-word;
  }
}
</style>
