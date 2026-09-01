export interface CreateBuilderData {
  rootContainerId: string;
}

/**
 * PRD M11. What the requester form hands its refresh script — see
 * easy_form_designer_submissions/new.html.erb.
 *
 * `triggerTokens` comes from Form#rule_trigger_tokens: the fields some
 * section's rule actually reads. Passing the tokens rather than marking the
 * controls in the DOM is deliberate — a Design System component's data
 * attributes are a closed whitelist, so it could not carry a hook attribute
 * even if we wanted one there.
 */
export interface InitSubmissionFormData {
  formId: string;
  refreshFormId: string;
  frameId: string;
  triggerTokens: string[];
}

/** Widget types supported by the first slice. Mirrors FormField::WIDGETS. */
export const WIDGETS = [
  "text",
  "long_text",
  "select",
  "date",
  "number",
  "radio",
  "multi_select",
  "checkbox",
  "user",
  "file",
] as const;
export type Widget = (typeof WIDGETS)[number];

/**
 * PRD M13. The one widget whose answer is uploaded files rather than a
 * value — so it takes no format rule, no bounds, and no preset (there is no
 * such thing as a preset file), and the model rejects `hidden` on it
 * outright. Mirrors FormField::FILE_WIDGETS.
 */
export const FILE_WIDGETS: readonly Widget[] = ["file"];

/** PRD M7 format rules. Mirrors FormField::VALIDATION_FORMATS. */
export const VALIDATION_FORMATS = ["email", "url"] as const;
export type ValidationFormat = (typeof VALIDATION_FORMATS)[number];

/**
 * Which widgets accept which rule — mirrors FormField::VALIDATION_FORMAT_WIDGETS
 * and RANGE_WIDGETS. The model rejects a mismatch outright, so offering one here
 * would produce a save that fails with no obvious cause.
 */
export const VALIDATION_FORMAT_WIDGETS: readonly Widget[] = ["text"];
export const RANGE_WIDGETS: readonly Widget[] = ["number"];
export const DATE_RANGE_WIDGETS: readonly Widget[] = ["date"];

/**
 * PRD M8 — which widget accepts a day-offset preset. Mirrors
 * FormField::PRESET_OFFSET_WIDGETS; a fixed preset value, by contrast, is
 * available on every widget (it's just typed/picked differently per widget).
 */
export const PRESET_OFFSET_WIDGETS: readonly Widget[] = ["date"];

/** How one side (min or max) of a date range is currently expressed. */
export const DATE_BOUND_MODES = ["none", "fixed", "offset"] as const;
export type DateBoundMode = (typeof DATE_BOUND_MODES)[number];

/** One option in the "Maps to" dropdown, served by AvailableAttributes. */
export interface MappingOption {
  type: "native" | "custom_field";
  value: string | number;
  label: string;
}

/**
 * One choice in the preset-value picker (PRD M8), served by
 * EasyFormDesignerFormsController#preset_options. Simpler than MappingOption
 * — there's no "native vs custom_field" split to preserve here, just the
 * legal value/label pairs for whatever the field is already mapped to.
 */
export interface PresetOption {
  label: string;
  value: string;
}

/**
 * PRD M11. An EasyQuery operator string — "=", "!", "~", "><", "t", ">t-"
 * and so on. Deliberately not a closed union here: which operators exist,
 * and which a given field may use, is EasyQuery's business, and the server
 * sends the legal list per field (see usePresetOptions). Pinning a union
 * client-side would just be a second list to keep in step.
 */
export type VisibilityOperator = string;

/** One operator choice, as served for a field's filter type. */
export interface OperatorOption {
  value: VisibilityOperator;
  /** Already translated, from EasyQuery's own operator labels. */
  label: string;
  /** false for "is set" / "today" and friends, which carry their own meaning. */
  needs_value: boolean;
}

/**
 * Operators whose value is a count of days rather than something to compare
 * against. Mirrors FormSection::DAY_COUNT_OPERATORS.
 */
export const DAY_COUNT_OPERATORS: readonly string[] = ["t-", ">t-", "<t-", "><t-"];

/** Operators taking two values. Mirrors FormSection::RANGE_OPERATORS. */
export const RANGE_OPERATORS: readonly string[] = ["><"];

/**
 * EasyQuery filter types whose value is a date. Both exist in core —
 * `date_period` is what an issue's own due/start date and a date custom field
 * report; `date` is the plainer variant other filters use — and a rule on
 * either should be authored with a calendar rather than a text box.
 */
export const DATE_FILTER_TYPES: readonly string[] = ["date_period", "date"];

/**
 * PRD M11 — a named group of fields, optionally gated by a rule.
 *
 * `id` is a number once saved, but a brand-new section carries a temporary
 * string key instead ("new-1") because its real id doesn't exist until the
 * save that creates it — fields assigned to it reference that key, and the
 * controller swaps in the real id server-side (see
 * EasyFormDesignerFormsController#section_params_resolved).
 */
export interface FormSection {
  id: number | string;
  position: number;
  name: string;
  token: string;
  visibilityFieldId: number | null;
  visibilityOperator: VisibilityOperator | null;
  // An array because EasyQuery operators take varying arity: "between" needs
  // two, "=" can take several, and the value-less ones ("is set", "today")
  // need none. Stored as JSON server-side, as EasyAutomations::Condition
  // stores its own.
  visibilityValues: string[];
  _destroy?: boolean;
}

export interface FormField {
  id?: number;
  position: number;
  label: string;
  helpText: string | null;
  token: string;
  widget: Widget;
  required: boolean;
  mappedAttribute: string | null;
  customFieldId: number | null;
  validationFormat: ValidationFormat | null;
  // Strings, not numbers: these come straight from a DSNumberField and go
  // straight into a decimal column, and "" (cleared) must stay distinguishable
  // from 0 (a real bound). Number("") === 0 would silently invent a floor.
  minValue: string | null;
  maxValue: string | null;
  // A fixed bound and a day offset are mutually exclusive per side — the
  // model rejects both being set at once — so the UI only ever writes one of
  // the pair for a given side, clearing the other.
  minDate: string | null;
  maxDate: string | null;
  minDateOffsetDays: number | null;
  maxDateOffsetDays: number | null;
  // PRD M8. `hidden` fields never render an input on the requester form at
  // all — their answer comes solely from AnswerResolver, server-side.
  // presetValue is a plain string for every widget except multi_select,
  // where the server sends/expects an array (see FormField#preset_value_list
  // and EasyFormDesignerFormsController#form_json).
  hidden: boolean;
  presetValue: string | string[] | null;
  presetOffsetDays: number | null;
  // PRD M11. Null means top-level / ungrouped. A string value is a
  // not-yet-saved section's temporary key — see FormSection above.
  sectionId: number | string | null;
  _destroy?: boolean;
}

export interface BuilderContext {
  formId: number;
  projectId: number;
  trackerId: number;
  attributesUrl: string;
  presetOptionsUrl: string;
}

/** The snake_case shape EasyFormDesignerFormsController#form_json returns —
 * both embedded for initial hydration and as the update response body. */
export interface ApiFormField {
  id: number;
  position: number;
  label: string;
  help_text: string | null;
  token: string;
  widget: Widget;
  required: boolean;
  mapped_attribute: string | null;
  custom_field_id: number | null;
  validation_format: ValidationFormat | null;
  min_value: string | null;
  max_value: string | null;
  min_date: string | null;
  max_date: string | null;
  min_date_offset_days: number | null;
  max_date_offset_days: number | null;
  hidden: boolean;
  preset_value: string | string[] | null;
  preset_offset_days: number | null;
  section_id: number | null;
}

export interface ApiFormSection {
  id: number;
  position: number;
  name: string;
  token: string;
  visibility_field_id: number | null;
  visibility_operator: VisibilityOperator | null;
  visibility_values: string[];
}

export interface ApiForm {
  id: number;
  subject_template: string | null;
  description_template: string | null;
  fields: ApiFormField[];
  sections: ApiFormSection[];
}

// A literal "{{ }}" written inline in a Vue template breaks the SFC
// compiler — it tokenizes the inner braces as the start of a *nested*
// mustache and reports "Unterminated template". Building the string here
// keeps every component's own interpolation delimiters unambiguous.
export function tokenPlaceholder(token: string): string {
  return `{{ ${token} }}`;
}

export function fieldFromApi(f: ApiFormField): FormField {
  return {
    id: f.id,
    position: f.position,
    label: f.label,
    helpText: f.help_text,
    token: f.token,
    widget: f.widget,
    required: f.required,
    mappedAttribute: f.mapped_attribute,
    customFieldId: f.custom_field_id,
    validationFormat: f.validation_format,
    minValue: f.min_value,
    maxValue: f.max_value,
    minDate: f.min_date,
    maxDate: f.max_date,
    minDateOffsetDays: f.min_date_offset_days,
    maxDateOffsetDays: f.max_date_offset_days,
    hidden: f.hidden,
    presetValue: f.preset_value,
    presetOffsetDays: f.preset_offset_days,
    sectionId: f.section_id,
  };
}

export function sectionFromApi(s: ApiFormSection): FormSection {
  return {
    id: s.id,
    position: s.position,
    name: s.name,
    token: s.token,
    visibilityFieldId: s.visibility_field_id,
    visibilityOperator: s.visibility_operator,
    visibilityValues: s.visibility_values ?? [],
  };
}
