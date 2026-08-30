import type { CreateBuilderData } from "../src/easy_form_designer/types";

window.EasyFormDesigner ||= {};

window.EasyFormDesigner.createBuilderApp = async (builderData: CreateBuilderData) => {
  const { createBuilderApp } = await import("../src/easy_form_designer/main");
  createBuilderApp(builderData);
};
