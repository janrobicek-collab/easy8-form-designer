import { Locator } from "@playwright/test";
import admin from "../../fixtures/users/admin.json";
import { BasePage } from "../base.page";
import { autologin } from "../../utils";

// REQ-19. Requester-facing fill-in page — server-rendered ERB, not Vue, so
// these locators target plain form controls and the section__group--<token>
// data-cy this session added to the section heading (_fields.html.erb).
export class FormSubmissionPage extends BasePage {
  public async preparePage(apiKey = admin.api_key) {
    await autologin(this.page, apiKey);
  }

  public async open(formId: string) {
    await this.page.goto(`/form-designer/forms/${formId}/submission/new`);
    await this.waitForDocumentReady();
  }

  public sectionGroup(token: string): Locator {
    return this.page.locator(`[data-cy="section__group--${token}"]`);
  }

  public answerField(token: string) {
    return this.page.locator(`[name="answers[${token}]"]`);
  }

  // A native <select> (see _fields.html.erb's comment on why it isn't
  // DSSelect) — driving one via Playwright's own selectOption avoids
  // depending on the DS autocomplete helpers this view deliberately avoids.
  public async answerSelect(token: string, optionLabel: string) {
    await this.answerField(token).selectOption({ label: optionLabel });
  }

  public async answerText(token: string, value: string) {
    await this.answerField(token).fill(value);
  }

  public async answerDate(token: string, isoDate: string) {
    // DSDatepicker submits through a hidden input under the same name;
    // ds_datepicker's visible control has no [name] at all (see
    // _fields.html.erb's "date" case comment), so this targets the hidden
    // input directly rather than driving the calendar UI.
    await this.answerField(token).fill(isoDate);
    // A calendar pick assigns the hidden input's value with no native
    // event at all (submission_form.ts's own documented finding) — fire one
    // so the refresh script's value-diff watcher notices the change.
    await this.answerField(token).dispatchEvent("change");
  }

  public async submit() {
    // DSActionButtons (see formBuilder.page.ts's identical note on the
    // gateway form) — new.html.erb's submit id is "submit". Not a generic
    // [type="submit"] selector: the base layout's own top-nav search form
    // has one too, and matches first in DOM order.
    await this.page.locator('[data-cy="ds-action-buttons__submit-button--submit"]').click();
    await this.waitForDocumentReady();
  }
}
