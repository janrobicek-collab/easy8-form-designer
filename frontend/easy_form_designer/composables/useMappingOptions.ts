import { ref } from "vue";
import type { BuilderContext, MappingOption, Widget } from "../types";

/**
 * Fetches the legal "Maps to" options for a widget from
 * EasyFormDesignerAttributesController.
 *
 * The server is the authority on what a field may map to — the UI never
 * derives that list itself, so it cannot offer a mapping the model would
 * reject at save time.
 */
export function useMappingOptions(context: BuilderContext) {
  const options = ref<MappingOption[]>([]);
  const loading = ref(false);
  const error = ref<string | null>(null);
  const cache = new Map<Widget, MappingOption[]>();

  async function load(widget: Widget): Promise<void> {
    if (cache.has(widget)) {
      options.value = cache.get(widget) as MappingOption[];
      return;
    }

    loading.value = true;
    error.value = null;

    try {
      const url = new URL(context.attributesUrl, window.location.origin);
      url.searchParams.set("project_id", String(context.projectId));
      url.searchParams.set("tracker_id", String(context.trackerId));
      url.searchParams.set("widget", widget);

      const response = await fetch(url.toString(), {
        headers: { Accept: "application/json" },
        credentials: "same-origin",
      });

      if (!response.ok) throw new Error(`HTTP ${response.status}`);

      const data = (await response.json()) as { options: MappingOption[] };
      cache.set(widget, data.options);
      options.value = data.options;
    } catch (e) {
      error.value = e instanceof Error ? e.message : String(e);
      options.value = [];
    } finally {
      loading.value = false;
    }
  }

  return { options, loading, error, load };
}
