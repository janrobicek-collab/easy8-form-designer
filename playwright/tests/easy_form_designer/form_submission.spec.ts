import { expect, test } from "@playwright/test";
import { FormBuilderPage } from "../../pages/easy_form_designer/formBuilder.page";
import { FormSubmissionPage } from "../../pages/easy_form_designer/formSubmission.page";

// REQ-19. Requester round trip — proves REQ-16's server-side rewrite of
// _fields.html.erb (sections outer, that section's fields inner) actually
// renders as separate groups in section order on the real page, and that a
// submission still creates a task end to end. The rule-editor half of this
// (a conditional section becoming visible once its trigger is answered) is
// intentionally left to the manual checklist in docs/smoketests.md rather
// than automated here — it needs the builder's DSSelect-driven rule editor,
// whose interaction pattern this session had no way to verify blind.
test.describe.serial("Form designer submission round trip #687043", () => {
  let builder: FormBuilderPage;
  let submission: FormSubmissionPage;
  const formName = `Playwright submission form ${Date.now()}`;
  let formId: string;

  test.beforeAll(async ({ browser }) => {
    builder = new FormBuilderPage(await (await browser.newContext()).newPage());
    submission = new FormSubmissionPage(await (await browser.newContext()).newPage());
    await builder.preparePage();
    await submission.preparePage();
  });

  test.afterAll(async () => {
    await builder.page.close();
    await submission.page.close();
  });

  test("builds a two-section form and publishes it #687043", async () => {
    await builder.createForm(formName);
    formId = /forms\/(\d+)\/edit/.exec(builder.page.url())?.[1] ?? "";
    expect(formId).not.toBe("");

    await builder.renameSection("general", "Requester details");
    await builder.addField("requester_details");
    await builder.setFieldLabel("untitled_field", "Reason");
    await builder.setFieldMapping("reason", "Subject");

    await builder.addSection();
    await builder.renameSection("untitled_section", "Hardware");
    await builder.addField("hardware");
    await builder.setFieldLabel("untitled_field", "Model");
    // A Text field only offers "Subject" as a native mapping (already taken
    // by "reason") — Long text is what maps to Description.
    await builder.setFieldWidget("model", "Long text");
    await builder.setFieldMapping("model", "Description");

    await builder.save();
    await expect(builder.unmappedFieldAlert()).toBeHidden();

    // The Publish button's disabled attribute is plain server-rendered HTML
    // (edit.html.erb: disabled: !@form.publishable?) set at the page's
    // ORIGINAL load — a Vue-only save() has no way to update it without a
    // real reload, unlike the Vue-mounted parts of the page.
    await builder.reloadPage();

    // ds_button renders an <a href=... role="button"> (edit.html.erb, not
    // part of the builder Vue app's own data-cy scheme) — an explicit
    // role="button" on an anchor, so it's a button by accessible role
    // despite the tag.
    await builder.page.getByRole("button", { name: "Publish" }).click();
    await builder.waitForDocumentReady();
  });

  test("renders each section as its own group, in section order #687043", async () => {
    await submission.open(formId);

    await expect(submission.sectionGroup("requester_details")).toBeVisible();
    await expect(submission.sectionGroup("hardware")).toBeVisible();

    const detailsBox = await submission.sectionGroup("requester_details").boundingBox();
    const hardwareBox = await submission.sectionGroup("hardware").boundingBox();
    expect(detailsBox?.y).toBeLessThan(hardwareBox?.y ?? Number.POSITIVE_INFINITY);
  });

  test("submits and creates a task with both answers #687043", async () => {
    await submission.answerText("reason", "Broken laptop screen");
    await submission.answerText("model", "ThinkPad X1");

    await submission.submit();

    await expect(submission.page).toHaveURL(/\/form-designer\/forms\/\d+\/submission\?submission_id=\d+/);
  });
});
