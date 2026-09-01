require "easy_extensions/spec_helper"

RSpec.describe EasyFormDesigner::SubmissionValidator, logged: :admin do
  let_it_be(:tracker, refind: true) { create(:tracker) }
  let_it_be(:project, refind: true) { create(:project, trackers: [tracker]) }

  let(:form) { create(:easy_form_designer_form, project: project, tracker: tracker) }

  # @return [Array<String>] messages for the one field under test
  def messages_for(field, value)
    described_class.new(form.reload, { field.token => value }).errors[field.token].to_a
  end

  describe "required fields" do
    let!(:field) { create(:easy_form_designer_form_field, form: form, required: true) }

    it "rejects a blank answer" do
      expect(messages_for(field, "")).to be_present
    end

    it "rejects a missing answer" do
      expect(messages_for(field, nil)).to be_present
    end

    it "accepts a present answer" do
      expect(messages_for(field, "Broken laptop")).to be_empty
    end

    context "when the field is optional" do
      let!(:field) { create(:easy_form_designer_form_field, form: form, required: false) }

      it "accepts a blank answer" do
        expect(messages_for(field, "")).to be_empty
      end
    end

    # A checkbox always posts something ("1" or "0" — a hidden field supplies
    # the unchecked case), so it is never blank. Required therefore has to mean
    # "must be checked", the ordinary meaning of a required consent box.
    context "for a checkbox" do
      let_it_be(:bool_cf) do
        create(:issue_custom_field, field_format: "bool", is_for_all: false,
                                    projects: [project.id], trackers: [tracker])
      end

      let!(:field) do
        create(:easy_form_designer_form_field, :checkbox, form: form,
                                                          custom_field: bool_cf, required: true)
      end

      it "rejects an unchecked box" do
        expect(messages_for(field, "0")).to be_present
      end

      it "accepts a checked box" do
        expect(messages_for(field, "1")).to be_empty
      end
    end

    # [""].blank? is false, so a plain blank? check treats "the requester
    # cleared the selection" as a real answer and lets an empty required
    # multi-select through.
    context "for a multi-select posting an empty selection" do
      let_it_be(:list_cf) do
        create(:issue_custom_field, field_format: "list", multiple: true,
                                    possible_values: %w[Windows Linux], is_for_all: false,
                                    projects: [project.id], trackers: [tracker])
      end

      let!(:field) do
        create(:easy_form_designer_form_field, :multi_select, form: form,
                                                              custom_field: list_cf, required: true)
      end

      it "rejects [\"\"]" do
        expect(messages_for(field, [""])).to be_present
      end

      it "accepts a real selection" do
        expect(messages_for(field, ["Windows"])).to be_empty
      end
    end
  end

  describe "email rule" do
    let!(:field) { create(:easy_form_designer_form_field, :email_validated, form: form) }

    it { expect(messages_for(field, "rob@easy8.com")).to be_empty }
    it { expect(messages_for(field, "not-an-email")).to be_present }
    it { expect(messages_for(field, "rob@")).to be_present }

    # The rule only applies to an answer that exists — an optional field left
    # empty is unanswered, not malformed.
    it { expect(messages_for(field, "")).to be_empty }
  end

  describe "url rule" do
    let!(:field) { create(:easy_form_designer_form_field, :url_validated, form: form) }

    it { expect(messages_for(field, "https://easy8.com/x")).to be_empty }
    it { expect(messages_for(field, "http://intranet/form")).to be_empty }
    it { expect(messages_for(field, "not a url")).to be_present }

    # D1, and the deliberate divergence from Redmine's own LinkFormat, which
    # accepts this and prepends http:// when rendering. The requester form
    # renders this rule as <input type="url">, whose native check demands a
    # scheme — so accepting it here would mean the server accepted a value the
    # browser had already refused to submit.
    it "rejects a bare host, unlike LinkFormat" do
      expect(messages_for(field, "easy8.com")).to be_present
    end
  end

  describe "number range" do
    let!(:field) { create(:easy_form_designer_form_field, :ranged, form: form) }

    it { expect(messages_for(field, "20")).to be_empty }
    it { expect(messages_for(field, "1")).to be_empty }
    it { expect(messages_for(field, "40")).to be_empty }
    it { expect(messages_for(field, "0")).to be_present }
    it { expect(messages_for(field, "41")).to be_present }
    it { expect(messages_for(field, "abc")).to be_present }

    # Core's own FloatFormat normalises a decimal comma before validating, so a
    # requester whose keyboard produces "," is not told their number isn't one.
    it "accepts a decimal comma" do
      expect(messages_for(field, "2,5")).to be_empty
    end

    it "names the bound it violated" do
      expect(messages_for(field, "41").join).to include("40")
    end

    context "with only a minimum" do
      let!(:field) { create(:easy_form_designer_form_field, :ranged, form: form, max_value: nil) }

      it { expect(messages_for(field, "9000")).to be_empty }
      it { expect(messages_for(field, "0")).to be_present }
    end
  end

  # Follow-up to PRD M7 while manually testing it: a date bound, fixed or
  # relative to the day of SUBMISSION. There is no client-side counterpart —
  # DesignSystem::Components::Datepicker takes no min/max at all — so this
  # tier is the only check that ever runs for a date-range rule.
  describe "date range" do
    context "with a fixed range" do
      let!(:field) do
        create(:easy_form_designer_form_field, :date_due, form: form,
                                                          min_date: Date.new(2026, 1, 1),
                                                          max_date: Date.new(2026, 12, 31))
      end

      it { expect(messages_for(field, "2026-06-15")).to be_empty }
      it { expect(messages_for(field, "2026-01-01")).to be_empty }
      it { expect(messages_for(field, "2026-12-31")).to be_empty }
      it { expect(messages_for(field, "2025-12-31")).to be_present }
      it { expect(messages_for(field, "2027-01-01")).to be_present }

      # Rob's feedback testing this live: a field with BOTH bounds set should
      # name the whole valid window in one message, not just whichever single
      # bound the submitted value happened to violate — "must be between X
      # and Y" tells the requester the actual target, not half of it.
      it "names the whole window when both bounds are configured" do
        expect(messages_for(field, "2025-12-31").join).to include("2026-01-01").and include("2026-12-31")
      end

      it "reports the same combined window regardless of which side was violated" do
        expect(messages_for(field, "2027-01-01").join).to include("2026-01-01").and include("2026-12-31")
      end
    end

    context "with only a maximum (a ceiling, no floor)" do
      let!(:field) { create(:easy_form_designer_form_field, :date_due, form: form, max_date: Date.new(2026, 6, 1)) }

      # Not "must not be after" — phrased as what the requester should do.
      it "says the date must be BEFORE the ceiling, not a double negative" do
        expect(messages_for(field, "2026-06-02").join).to include("must be before")
      end
    end

    context "with only a minimum (a floor, no ceiling)" do
      let!(:field) { create(:easy_form_designer_form_field, :date_due, form: form, min_date: Date.new(2026, 6, 1)) }

      it "says the date must be AFTER the floor, not a double negative" do
        expect(messages_for(field, "2026-05-31").join).to include("must be after")
      end
    end

    context "with an offset relative to today" do
      # Computed the same way the code does, rather than freezing the clock —
      # this is exactly what a requester submitting "today" would experience.
      let!(:field) { create(:easy_form_designer_form_field, :date_due, form: form, min_date_offset_days: -7) }

      it "accepts a date within the last 7 days" do
        expect(messages_for(field, Date.current.iso8601)).to be_empty
      end

      it "accepts exactly 7 days ago" do
        expect(messages_for(field, (Date.current - 7).iso8601)).to be_empty
      end

      it "rejects more than 7 days ago" do
        expect(messages_for(field, (Date.current - 8).iso8601)).to be_present
      end

      it "accepts any date in the future" do
        expect(messages_for(field, (Date.current + 365).iso8601)).to be_empty
      end
    end

    context "with an unparsable value" do
      let!(:field) { create(:easy_form_designer_form_field, :date_due, form: form, min_date: Date.current) }

      it { expect(messages_for(field, "not-a-date")).to be_present }
    end

    context "when the field is optional and left blank" do
      let!(:field) do
        create(:easy_form_designer_form_field, :date_due, form: form, min_date: Date.current, required: false)
      end

      it { expect(messages_for(field, "")).to be_empty }
    end
  end

  # D2 — the validator delegates to the mapped custom field's own rules rather
  # than reimplementing them, so a constraint an admin set in Easy8 lands on
  # the right form field instead of arriving as an unattributed flash string
  # after issue.save had already rejected it.
  describe "the mapped custom field's own rules" do
    let_it_be(:regexp_cf) do
      create(:issue_custom_field, field_format: "string", regexp: '\A[A-Z]{3}-\d{4}\z',
                                  is_for_all: false, projects: [project.id], trackers: [tracker])
    end

    let!(:field) do
      create(:easy_form_designer_form_field, form: form, widget: "text",
                                             mapped_attribute: nil, custom_field: regexp_cf)
    end

    it "rejects a value the custom field's regexp refuses" do
      expect(messages_for(field, "nope")).to be_present
    end

    it "accepts a value it allows" do
      expect(messages_for(field, "ABC-1234")).to be_empty
    end

    context "with a length constraint" do
      let_it_be(:regexp_cf) do
        create(:issue_custom_field, field_format: "string", min_length: 4,
                                    is_for_all: false, projects: [project.id], trackers: [tracker])
      end

      it { expect(messages_for(field, "ab")).to be_present }
      it { expect(messages_for(field, "abcd")).to be_empty }
    end
  end

  describe "#errors" do
    it "keys messages by field token, so each lands on its own input" do
      email = create(:easy_form_designer_form_field, :email_validated, form: form,
                                                                       label: "Contact email")
      number = create(:easy_form_designer_form_field, :ranged, form: form, label: "Days")
      form.reload

      errors = described_class.new(form, { email.token => "bad", number.token => "99" }).errors

      expect(errors.keys).to contain_exactly(email.token, number.token)
    end

    it "reports nothing for a fully valid submission" do
      field = create(:easy_form_designer_form_field, :email_validated, form: form)
      form.reload

      validator = described_class.new(form, { field.token => "rob@easy8.com" })

      expect(validator).to be_valid
    end

    # One empty input should produce one message, not "cannot be blank" plus
    # "must be a valid email address" for the same absence.
    it "does not stack a format error on top of a blank error" do
      field = create(:easy_form_designer_form_field, :email_validated, form: form, required: true)

      expect(messages_for(field, "").size).to eq(1)
    end
  end

  # PRD M8. A hidden field is not requester input at all — it never appears
  # on the requester form, so there is nothing here for a message to help
  # anyone fix. Design-time legality is FormField's own job
  # (#preset_value_valid_for_mapping), not this class's.
  describe "hidden fields" do
    it "reports nothing for a hidden, required field with no submitted answer" do
      field = create(:easy_form_designer_form_field, :hidden_priority, form: form, required: true)

      expect(messages_for(field, nil)).to be_empty
    end

    # Even a Redmine-required custom field mapped to a hidden form field must
    # not surface here — that combination is unsatisfiable purely by the
    # requester's actions, since they never see the field either way.
    it "reports nothing for a hidden field whose custom field is itself required" do
      required_cf = create(:issue_custom_field, field_format: "string", is_required: true,
                                                 is_for_all: false, projects: [project.id], trackers: [tracker])
      field = create(:easy_form_designer_form_field, form: form, widget: "text", mapped_attribute: nil,
                                                     custom_field: required_cf, hidden: true,
                                                     preset_value: "stamped")

      expect(messages_for(field, nil)).to be_empty
    end

    it "is excluded from #errors' keys entirely, not merely reported as empty" do
      field = create(:easy_form_designer_form_field, :hidden_priority, form: form)

      expect(described_class.new(form.reload, {}).errors.keys).not_to include(field.token)
    end
  end

  # PRD M11. Same reasoning as the hidden fields above — a required error on
  # a field nobody was shown is a dead end, not something the requester can
  # act on. The difference is that visibility here depends on the answers
  # being validated, not on the form definition alone.
  describe "fields in a conditional section" do
    let_it_be(:shown_priority) { create(:issue_priority) }
    let_it_be(:other_priority) { create(:issue_priority) }

    let!(:trigger) do
      create(:easy_form_designer_form_field, :select_priority, form: form, label: "Priority", token: "priority")
    end

    let!(:section) do
      create(:easy_form_designer_form_section, :gated, form: form, visibility_field: trigger,
                                                       visibility_value: shown_priority.id.to_s)
    end

    let!(:gated_field) do
      create(:easy_form_designer_form_field, form: form, label: "Serial", token: "serial", widget: "text",
                                             mapped_attribute: "subject", required: true, section: section)
    end

    it "demands the required field when the section is visible" do
      errors = described_class.new(form.reload, { "priority" => shown_priority.id.to_s }).errors

      expect(errors).to have_key(gated_field.token)
    end

    it "does not demand it when the section is hidden" do
      errors = described_class.new(form.reload, { "priority" => other_priority.id.to_s }).errors

      expect(errors).not_to have_key(gated_field.token)
    end

    it "reports the submission valid when only a hidden section's field is unanswered" do
      validator = described_class.new(form.reload, { "priority" => other_priority.id.to_s })

      expect(validator).to be_valid
    end
  end
end
