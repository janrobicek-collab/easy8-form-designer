import { Locator } from "@playwright/test";
import admin from "../../fixtures/users/admin.json";
import { BasePage } from "../base.page";
import { autologin } from "../../utils";

// REQ-19. Builder page object for the section/field editor rewritten in
// REQ-17 — every locator here targets a `data-cy` this session added
// specifically for Playwright (see the "data-cy audit" note in the plan):
// section__card--<token>, section__field--<token>, handle__drag--*,
// toggle__expand--*, button__add--*, button__save--form.
export class FormBuilderPage extends BasePage {
  public async preparePage(apiKey = admin.api_key) {
    await autologin(this.page, apiKey);
  }

  // The gateway step. Deliberately picks whichever project/tracker sorts
  // first rather than a fixture like `ganttProject` — this feature's own
  // behaviour doesn't depend on WHICH pair is chosen, and a fixed fixture
  // name only exists in the QA e2e dump this suite normally runs against,
  // not necessarily in every environment it might run in.
  public async createForm(name: string) {
    await this.page.goto("/form-designer/forms/new");
    await this.waitForDocumentReady();

    await this.clearAndFillTextInput("easy_form_designer_form[name]", name);
    await this.page.locator("#easy_form_designer_form_project_id").selectOption({ index: 1 });
    await this.page.locator("#easy_form_designer_form_tracker_id").selectOption({ index: 1 });

    // ds_action_buttons is a Vue-mounted <easy8-ds-action-buttons>, whose own
    // DSActionButtons.vue emits "ds-action-buttons__submit-button--<id>" —
    // NOT the "button__submit--<id>" convention BasePage's
    // clickOnSubmitFormButton assumes, which turned out to target a
    // different button pattern than this DS component uses.
    await this.clickOnSelector('[data-cy="ds-action-buttons__submit-button--continue"]');
    await this.page.waitForURL("**/form-designer/forms/*/edit");
    await this.waitForDocumentReady();
  }

  public sectionCard(token: string): Locator {
    return this.page.locator(`[data-cy="section__card--${token}"]`);
  }

  public fieldRow(token: string): Locator {
    return this.page.locator(`[data-cy="section__field--${token}"]`);
  }

  // The drag handle is a SIBLING of the fieldset it drags (SectionCard.vue /
  // FieldRow.vue both wrap `<DragHandle /><DSFieldset ...>` in one flex row,
  // matching the screenshot's handle-beside-the-block layout) — never a
  // descendant, so it has its own top-level data-cy rather than being found
  // via fieldRow(token).locator(...).
  public fieldDragHandle(token: string): Locator {
    return this.page.locator(`[data-cy="handle__drag--field-${token}"]`);
  }

  public sectionDragHandle(token: string): Locator {
    return this.page.locator(`[data-cy="handle__drag--section-${token}"]`);
  }

  public async addSection() {
    await this.clickOnSelector('[data-cy="button__add--section"]');
  }

  public async addField(sectionToken: string) {
    await this.clickOnSelector(`[data-cy="button__add--field-${sectionToken}"]`);
  }

  public async removeSection(token: string) {
    // DSFieldset gives every remove button the same fixed data-cy, and a
    // section's own button is far from the only one in its subtree — each
    // field row nested inside is a DSFieldset too. DSFieldset's template
    // renders the actions span (carrying this button) BEFORE the content
    // slot that holds those nested fields, so `.first()` reliably picks the
    // section's own.
    await this.sectionCard(token).locator('[data-cy="ds-fieldset__remove-button"]').first().click();
  }

  public async removeField(token: string) {
    await this.fieldRow(token).locator('[data-cy="ds-fieldset__remove-button"]').click();
  }

  public async renameSection(token: string, name: string) {
    // DSTextField's underlying input isn't given an explicit `name` here
    // (SectionCard.vue), so this targets it by its DS-generated label
    // association instead — the same reliable path setFieldLabel below uses.
    await this.sectionCard(token).getByLabel("Group name").fill(name);
  }

  public async setFieldLabel(token: string, label: string) {
    await this.fieldRow(token).getByLabel("Title").fill(label);
  }

  // "Maps to" is a real DSSelect (Vue-mounted inside the SPA, unlike the
  // requester form's deliberately-plain native selects — see
  // _fields.html.erb). The actual clickable trigger is DSSelect's visible
  // readonly text input (data-cy="ds-base-input__input--mapped_attribute")
  // — the element carrying `name="mapped_attribute"` is a plain
  // `<input type="hidden">` DSSelect submits through (the same pattern
  // already documented for DSDatepicker elsewhere in this engine), and
  // clicking a hidden input isn't a valid Playwright action regardless of
  // `force`. Not base.page.ts's shared selectValueInFrameworkSelect: its
  // page-wide getByText(optText) also matches a field row's OWN
  // "Description" help-text label whenever the option text happens to be a
  // native attribute name like "Description" — scoping to the open
  // ds-popover__content specifically avoids that collision.
  public async setFieldMapping(token: string, optionLabel: string) {
    await this.selectFromDsSelect(
      `[data-cy="section__field--${token}"] [data-cy="ds-base-input__input--mapped_attribute"]`,
      optionLabel
    );
  }

  // A Text field only ever offers "Subject" (or a matching custom field) as
  // its native mapping — "Description" needs the Long text widget instead
  // (FieldRow's own dropped widgetHint used to spell this out; the model
  // enforces it either way via FormField#exactly_one_mapping's available
  // set). Widget lives in the same "Maps to" DSSelect pattern, just a
  // different field/trigger.
  public async setFieldWidget(token: string, optionLabel: string) {
    await this.selectFromDsSelect(
      `[data-cy="section__field--${token}"] [data-cy="ds-base-input__input--widget"]`,
      optionLabel
    );
  }

  // Shared DSSelect driver for both of the above. Not base.page.ts's shared
  // selectValueInFrameworkSelect: its page-wide getByText(optText) also
  // matches unrelated same-text labels elsewhere on the page (e.g. a field
  // row's own "Description" help-text label) — scoping to the open
  // ds-popover__content specifically avoids that collision.
  private async selectFromDsSelect(triggerSelector: string, optionLabel: string) {
    await this.page.locator(triggerSelector).click();

    const popover = this.page.locator('[data-cy="ds-popover__content"]:visible');
    const option = popover.getByText(optionLabel, { exact: true });
    await option.waitFor({ state: "visible" });
    await option.click();
  }

  public async expandFieldAdvanced(token: string) {
    await this.clickOnSelector(`[data-cy="toggle__expand--field-advanced-${token}"]`);
  }

  public async toggleSectionCollapsed(sectionToken: string) {
    await this.clickOnSelector(`[data-cy="toggle__expand--section-${sectionToken}"]`);
  }

  // Playwright's dragTo simulates native HTML5 drag-and-drop, which
  // SortableJS (vuedraggable's underlying library) listens for via plain
  // mouse events instead — untested against the real component; if dragTo
  // turns out not to trigger a reorder, replace with an explicit
  // hover/mouse.down/mouse.move/mouse.up sequence on the two handles.
  public async dragFieldWithinSection(fromToken: string, toToken: string) {
    await this.fieldDragHandle(fromToken).dragTo(this.fieldDragHandle(toToken));
  }

  public async dragFieldToSection(fromToken: string, targetSectionToken: string) {
    const target = this.page.locator(`[data-cy="field__list--${targetSectionToken}"]`);
    await this.fieldDragHandle(fromToken).dragTo(target);
  }

  public async save() {
    // Every builder mutation (add/remove/rename/drag) is local Pinia state
    // only — nothing round-trips to the server until this one PATCH — so a
    // caller that reloads right after clicking Save without waiting for it
    // races the request and reloads against whatever the server already had.
    const [response] = await Promise.all([
      this.page.waitForResponse((r) => r.url().includes("/form-designer/forms/") && r.request().method() === "PATCH"),
      this.clickOnSelector('[data-cy="button__save--form"]'),
    ]);

    if (!response.ok()) {
      throw new Error(`Save PATCH failed with ${response.status()}: ${await response.text()}`);
    }
  }

  public unmappedFieldAlert(): Locator {
    return this.page.getByText("field(s) are not mapped");
  }
}
