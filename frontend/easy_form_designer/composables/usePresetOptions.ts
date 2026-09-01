import { ref } from "vue";
import type { BuilderContext, FormField, OperatorOption, PresetOption } from "../types";

/**
 * Fetches the legal preset-value choices for a field's CURRENT MAPPING from
 * EasyFormDesignerFormsController#preset_options (PRD M8's preset picker).
 *
 * Unlike useMappingOptions (keyed by widget alone), the legal set here
 * depends on what the field is actually mapped to — a Dropdown mapped to
 * Priority and a Dropdown mapped to a custom field offer different presets —
 * so the cache key is the mapping itself, not just the widget.
 */
interface FieldOptions {
  options: PresetOption[];
  operators: OperatorOption[];
  filterType: string | null;
}

/** What an unmapped field, or a failed request, leaves the pickers showing. */
const EMPTY: FieldOptions = { options: [], operators: [], filterType: null };

/** The wire shape, which is snake_case like every other key this controller serves. */
interface ApiFieldOptions {
  options?: PresetOption[];
  operators?: OperatorOption[];
  filter_type?: string | null;
}

function messageFor(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

function fromApi(data: ApiFieldOptions): FieldOptions {
  return {
    options: data.options ?? [],
    operators: data.operators ?? [],
    filterType: data.filter_type ?? null,
  };
}

export function usePresetOptions(context: BuilderContext) {
  const options = ref<PresetOption[]>([]);
  // PRD M11. The same request answers "what can this field hold?" and "how
  // may it be compared?" — one question about one field, so one round trip.
  // The operator list is EasyQuery's own, already translated.
  const operators = ref<OperatorOption[]>([]);
  // The field's EasyQuery filter type ("list", "text", "date_period", …).
  // Which operators exist is already answered by `operators`; this answers
  // what a VALUE for them looks like — a date rule is picked from a calendar,
  // not typed, and its day-count operators take a plain number instead.
  const filterType = ref<string | null>(null);
  const loading = ref(false);
  const error = ref<string | null>(null);
  const cache = new Map<string, FieldOptions>();

  function cacheKey(field: FormField): string {
    return `${field.widget}:${field.mappedAttribute ?? ""}:${field.customFieldId ?? ""}`;
  }

  async function load(field: FormField): Promise<void> {
    // Nothing to pick a preset FOR until the field is mapped — mirrors
    // FormField#preset_value_valid_for_mapping's own "return unless mapped?"
    // guard, so the UI never offers a picker the model would reject anyway.
    if (!field.mappedAttribute && !field.customFieldId) {
      apply(EMPTY);
      return;
    }

    const key = cacheKey(field);
    const cached = cache.get(key);
    if (cached) {
      apply(cached);
      return;
    }

    loading.value = true;
    error.value = null;

    try {
      const resolved = await fetchOptions(field);

      cache.set(key, resolved);
      apply(resolved);
    } catch (e) {
      error.value = messageFor(e);
      apply(EMPTY);
    } finally {
      loading.value = false;
    }
  }

  async function fetchOptions(field: FormField): Promise<FieldOptions> {
    const response = await fetch(optionsUrl(field), {
      headers: { Accept: "application/json" },
      credentials: "same-origin",
    });

    if (!response.ok) throw new Error(`HTTP ${response.status}`);

    return fromApi(await response.json());
  }

  function optionsUrl(field: FormField): string {
    const url = new URL(context.presetOptionsUrl, window.location.origin);
    url.searchParams.set("widget", field.widget);
    if (field.mappedAttribute) url.searchParams.set("mapped_attribute", field.mappedAttribute);
    if (field.customFieldId) url.searchParams.set("custom_field_id", String(field.customFieldId));

    return url.toString();
  }

  function apply(resolved: FieldOptions): void {
    options.value = resolved.options;
    operators.value = resolved.operators;
    filterType.value = resolved.filterType;
  }

  return { options, operators, filterType, loading, error, load };
}
