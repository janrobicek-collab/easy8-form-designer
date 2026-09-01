import type { InjectionKey } from "vue";
import type { BuilderContext } from "../types";

// REQ-17. FieldRow/FieldAdvanced/SectionCard each need the gateway's
// project/tracker/urls to fetch their OWN mapping and preset options — the
// inline-editing layout keeps every row's config mounted at once (there's no
// single "selected" panel any more to hold this centrally), so it's provided
// once at the root rather than prop-drilled through four component layers.
export const BUILDER_CONTEXT_KEY: InjectionKey<BuilderContext> = Symbol("easyFormDesignerBuilderContext");
