export interface CreateBuilderData {
  rootContainerId: string;
}

/** Widget types supported by the first slice. Mirrors FormField::WIDGETS. */
export const WIDGETS = ["text", "long_text", "select", "date"] as const;
export type Widget = (typeof WIDGETS)[number];

/** One option in the "Maps to" dropdown, served by AvailableAttributes. */
export interface MappingOption {
  type: "native" | "custom_field";
  value: string | number;
  label: string;
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
  _destroy?: boolean;
}

export interface BuilderContext {
  formId: number;
  projectId: number;
  trackerId: number;
  attributesUrl: string;
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
}

export interface ApiForm {
  id: number;
  subject_template: string | null;
  description_template: string | null;
  fields: ApiFormField[];
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
  };
}
