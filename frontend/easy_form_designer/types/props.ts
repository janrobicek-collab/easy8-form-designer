import type { FormField, MappingOption } from "./index";

export interface FieldCardProps {
  field: FormField;
  selected: boolean;
}

export interface FieldConfigProps {
  field: FormField | null;
  options: MappingOption[];
  loading: boolean;
}
