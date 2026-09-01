import { expect, test } from "@playwright/test";
import { FormBuilderPage } from "../../pages/easy_form_designer/formBuilder.page";

// REQ-19. Builder round trip — REQ-16 made every field require a section and
// REQ-17 replaced the palette/canvas with drag-and-drop grouped rows; this is
// the one thing no RSpec request spec can prove, since the whole point is
// real pointer interaction (drag) and real client-side state (Pinia).
test.describe.serial("Form designer builder round trip #687043", () => {
  let builder: FormBuilderPage;
  const formName = `Playwright form ${Date.now()}`;

  test.beforeAll(async ({ browser }) => {
    builder = new FormBuilderPage(await (await browser.newContext()).newPage());
    await builder.preparePage();
  });

  test.afterAll(async () => {
    await builder.page.close();
  });

  test("creates a form and lands on the builder with a default section #687043", async () => {
    await builder.createForm(formName);

    // Form#ensure_default_section (REQ-16) — a brand-new form already has
    // one section, so there is always somewhere to add a first field.
    await expect(builder.sectionCard("general")).toBeVisible();
  });

  test("adds a field inside the default section #687043", async () => {
    await builder.addField("general");

    await expect(builder.fieldRow("untitled_field")).toBeVisible();
    await expect(builder.fieldRow("untitled_field").getByText("Not mapped")).toBeVisible();
  });

  test("renames a section and a field, updating their tokens #687043", async () => {
    await builder.renameSection("general", "Requester details");
    await builder.setFieldLabel("untitled_field", "Full name");

    await expect(builder.sectionCard("requester_details")).toBeVisible();
    await expect(builder.fieldRow("full_name")).toBeVisible();
  });

  test("adds a second section and moves the field into it by drag #687043", async () => {
    await builder.addSection();
    // The second default-named section collides with the first's original
    // token and gets suffixed, matching FormSection#default_token.
    await expect(builder.sectionCard("untitled_section")).toBeVisible();

    await builder.dragFieldToSection("full_name", "untitled_section");

    await expect(
      builder.page.locator('[data-cy="field__list--untitled_section"] [data-cy="section__field--full_name"]')
    ).toBeVisible();
  });

  test("reorders two fields within a section by drag #687043", async () => {
    await builder.addField("untitled_section");
    await builder.setFieldLabel("untitled_field", "Second field");

    await builder.dragFieldWithinSection("second_field", "full_name");

    const list = builder.page.locator('[data-cy="field__list--untitled_section"]');
    const tokens = await list.locator("[data-cy^='section__field--']").evaluateAll((rows) =>
      rows.map((row) => row.getAttribute("data-cy"))
    );
    expect(tokens[0]).toBe("section__field--second_field");
  });

  test("collapsing a section hides its fields but keeps it selectable #687043", async () => {
    await builder.toggleSectionCollapsed("untitled_section");

    await expect(builder.fieldRow("full_name")).toBeHidden();
    await expect(builder.sectionCard("untitled_section")).toBeVisible();

    await builder.toggleSectionCollapsed("untitled_section");
    await expect(builder.fieldRow("full_name")).toBeVisible();
  });

  test("cannot remove the last remaining section #687043", async () => {
    // Two sections exist here (requester_details, untitled_section) —
    // removing one is allowed and it disappears, leaving one.
    await builder.removeSection("untitled_section");
    await expect(builder.sectionCard("untitled_section")).toBeHidden();
    await expect(builder.sectionCard("requester_details")).toBeVisible();

    // REQ-16's invariant (every field needs a section) means the LAST
    // section can't be removed at all — canRemoveSection turns DSFieldset's
    // own `removable` off, so the trash button isn't even rendered, not
    // merely disabled.
    await expect(
      builder.sectionCard("requester_details").locator('[data-cy="ds-fieldset__remove-button"]')
    ).toBeHidden();
  });

  test("survives a reload after saving #687043", async () => {
    // Only "requester_details" remains at this point, and removing
    // "untitled_section" took full_name/second_field down with it (a
    // section's fields are destroyed along with it) — add a fresh field so
    // this actually proves persistence, not just an empty section surviving.
    await builder.addField("requester_details");
    await builder.setFieldLabel("untitled_field", "Serial number");
    // Every field must map to a real task attribute (the KO criterion) — an
    // unmapped field fails FormField#exactly_one_mapping and the whole save
    // is rejected, exactly the validation this step would otherwise trip.
    await builder.setFieldMapping("serial_number", "Subject");

    await builder.save();
    await builder.reloadPage();

    await expect(builder.sectionCard("requester_details")).toBeVisible();
    await expect(builder.fieldRow("serial_number")).toBeVisible();
  });
});
