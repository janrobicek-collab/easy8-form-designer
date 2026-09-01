import type { CreateBuilderData, InitSubmissionFormData } from "../src/easy_form_designer/types";

window.EasyFormDesigner ||= {};

window.EasyFormDesigner.createBuilderApp = async (builderData: CreateBuilderData) => {
  const { createBuilderApp } = await import("../src/easy_form_designer/main");
  createBuilderApp(builderData);
};

// PRD M11's conditional sections. Only the requester form calls this, and
// only when the form actually has a rule to watch, so the module stays out of
// every other page's bundle.
window.EasyFormDesigner.initSubmissionForm = async (data: InitSubmissionFormData) => {
  const { initSubmissionForm } = await import("../src/easy_form_designer/submission_form");
  initSubmissionForm(data);
};
