import { createApp } from "vue";
import FormBuilder from "./FormBuilder.vue";
import type { BuilderContext, CreateBuilderData } from "./types";

/**
 * Mounts the form builder. Called from
 * easy_form_designer_forms/edit.html.erb via the Vite entrypoint, following
 * the easy_automations rule-editor pattern.
 */
export function createBuilderApp({ rootContainerId }: CreateBuilderData): void {
  const el = document.getElementById(rootContainerId);
  if (!el) return;

  const context: BuilderContext = {
    formId: Number(el.dataset.formId),
    projectId: Number(el.dataset.projectId),
    trackerId: Number(el.dataset.trackerId),
    attributesUrl: String(el.dataset.attributesUrl ?? ""),
  };

  createApp(FormBuilder, { context }).mount(el);
}
