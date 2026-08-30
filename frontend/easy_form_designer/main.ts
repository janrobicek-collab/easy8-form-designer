import { createApp } from "vue";
import FormBuilder from "./FormBuilder.vue";
import type { ApiForm, BuilderContext, CreateBuilderData } from "./types";

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

  // The saved fields/templates aren't otherwise reachable — without this the
  // canvas always starts blank on load or refresh, no matter what is already
  // in the database.
  const initialForm = readInitialForm(el.dataset.initialId);

  createApp(FormBuilder, { context, initialForm }).mount(el);
}

function readInitialForm(scriptId: string | undefined): ApiForm | null {
  if (!scriptId) return null;

  const node = document.getElementById(scriptId);
  if (!node?.textContent) return null;

  try {
    return JSON.parse(node.textContent) as ApiForm;
  } catch {
    return null;
  }
}
