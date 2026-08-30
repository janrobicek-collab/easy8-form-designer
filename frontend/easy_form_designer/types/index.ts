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
