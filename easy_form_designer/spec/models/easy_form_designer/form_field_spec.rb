require "easy_extensions/spec_helper"

RSpec.describe EasyFormDesigner::FormField, logged: :admin do
  subject(:field) { build(:easy_form_designer_form_field, form: form) }

  let_it_be(:tracker, refind: true) { create(:tracker) }
  let_it_be(:project, refind: true) { create(:project, trackers: [tracker]) }

  let(:form) { create(:easy_form_designer_form, project: project, tracker: tracker) }

  describe "mapping" do
    it { is_expected.to be_valid }

    # The KO criterion, enforced at the model layer: no unlinked form-only fields.
    context "with no mapping at all" do
      subject(:field) do
        build(:easy_form_designer_form_field, form: form, mapped_attribute: nil, custom_field: nil)
      end

      it { is_expected.not_to be_valid }
    end

    context "with both a native attribute and a custom field" do
      let_it_be(:cf) do
        create(:issue_custom_field, field_format: "string", is_for_all: false,
                                    projects: [project.id], trackers: [tracker])
      end

      subject(:field) do
        build(:easy_form_designer_form_field, form: form,
                                              mapped_attribute: "subject", custom_field: cf)
      end

      it "is invalid — a field drives exactly one attribute" do
        expect(field).not_to be_valid
      end
    end

    context "with a custom field outside the project ∩ tracker intersection" do
      let_it_be(:foreign_cf) do
        create(:issue_custom_field, field_format: "string", is_for_all: false,
                                    projects: [create(:project).id], trackers: [create(:tracker)])
      end

      subject(:field) do
        build(:easy_form_designer_form_field, form: form,
                                              mapped_attribute: nil, custom_field: foreign_cf)
      end

      it { is_expected.not_to be_valid }
    end

    context "with an unrecognised native attribute" do
      subject(:field) do
        build(:easy_form_designer_form_field, form: form, mapped_attribute: "not_a_field")
      end

      it { is_expected.not_to be_valid }
    end
  end

  describe "token generation" do
    it "derives a token from the label" do
      field = create(:easy_form_designer_form_field, form: form, label: "Employee name", token: nil)

      expect(field.token).to eq("employee_name")
    end

    it "disambiguates a token that is already taken" do
      create(:easy_form_designer_form_field, form: form, label: "Employee name", token: nil)
      form.reload
      second = create(:easy_form_designer_form_field, form: form, label: "Employee name", token: nil,
                                                      mapped_attribute: "description", widget: "long_text")

      expect(second.token).to eq("employee_name_2")
    end
  end

  # REQ-16. Every field now belongs to a section — a form-only concept, not
  # something the requester or IssueBuilder ever sees directly.
  describe "section" do
    it "is invalid with no section" do
      field = build(:easy_form_designer_form_field, form: form, section: nil)

      expect(field).not_to be_valid
    end

    it "is invalid when the section belongs to a different form" do
      foreign_form = create(:easy_form_designer_form, project: project, tracker: tracker)
      foreign_section = create(:easy_form_designer_form_section, form: foreign_form)

      field = build(:easy_form_designer_form_field, form: form, section: foreign_section)

      expect(field).not_to be_valid
    end

    it "is valid in a section that belongs to the same form" do
      section = create(:easy_form_designer_form_section, form: form)

      field = build(:easy_form_designer_form_field, form: form, section: section)

      expect(field).to be_valid
    end
  end

  describe "#options" do
    context "for a select mapped to a list custom field" do
      let_it_be(:list_cf) do
        create(:issue_custom_field, field_format: "list", possible_values: %w[Windows Linux],
                                    is_for_all: false, projects: [project.id], trackers: [tracker])
      end

      subject(:field) do
        create(:easy_form_designer_form_field, form: form, widget: "select",
                                               mapped_attribute: nil, custom_field: list_cf)
      end

      # Options come from the mapped attribute, never authored on the field —
      # that is what makes an unmapped field structurally unrenderable.
      it { expect(field.options).to eq([%w[Windows Windows], %w[Linux Linux]]) }
    end

    context "for a non-select widget" do
      it { expect(field.options).to eq([]) }
    end

    context "for a radio field mapped to priority" do
      subject(:field) { build(:easy_form_designer_form_field, :radio_priority, form: form) }

      it "resolves the same way select does" do
        expect(field.options).to eq(IssuePriority.active.map { |p| [p.name, p.id.to_s] })
      end
    end

    context "for a multi_select mapped to a list custom field" do
      let_it_be(:list_cf) do
        create(:issue_custom_field, field_format: "list", multiple: true,
                                    possible_values: %w[Windows Linux],
                                    is_for_all: false, projects: [project.id], trackers: [tracker])
      end

      subject(:field) do
        create(:easy_form_designer_form_field, form: form, widget: "multi_select",
                                               mapped_attribute: nil, custom_field: list_cf)
      end

      it { expect(field.options).to eq([%w[Windows Windows], %w[Linux Linux]]) }
    end

    # Regression: enumeration-format custom fields keep their choices in a
    # real CustomFieldEnumeration association, never in possible_values
    # (always nil for this format) — reading possible_values directly
    # silently produced zero options, so a Radio buttons field mapped to an
    # enumeration custom field rendered with no inputs at all on the
    # requester form, no error anywhere.
    context "for a radio field mapped to an enumeration custom field" do
      let_it_be(:enum_cf) do
        create(:issue_custom_field, field_format: "enumeration",
                                    is_for_all: false, projects: [project.id], trackers: [tracker])
      end

      let_it_be(:option_a) { CustomFieldEnumeration.create!(custom_field: enum_cf, name: "Alice", active: true) }
      let_it_be(:option_b) { CustomFieldEnumeration.create!(custom_field: enum_cf, name: "Bob", active: true) }

      subject(:field) do
        create(:easy_form_designer_form_field, form: form, widget: "radio",
                                               mapped_attribute: nil, custom_field: enum_cf)
      end

      it "resolves options from the enumeration association" do
        expect(field.options).to eq([["Alice", option_a.id.to_s], ["Bob", option_b.id.to_s]])
      end
    end
  end

  describe "duplicate attribute mapping" do
    context "when another field already maps to the same native attribute" do
      # form.reload mirrors what genuinely happens between two real requests
      # (the controller always re-finds the form fresh) — without it, this
      # spec would be testing RSpec's in-memory object reuse, not the app.
      before do
        create(:easy_form_designer_form_field, :select_priority, form: form)
        form.reload
      end

      subject(:field) { build(:easy_form_designer_form_field, :radio_priority, form: form) }

      it { is_expected.not_to be_valid }
    end

    context "when another field already maps to the same custom field" do
      let_it_be(:cf) do
        create(:issue_custom_field, field_format: "string", is_for_all: false,
                                    projects: [project.id], trackers: [tracker])
      end

      before do
        create(:easy_form_designer_form_field, form: form, widget: "text",
                                               mapped_attribute: nil, custom_field: cf)
        form.reload
      end

      subject(:field) do
        build(:easy_form_designer_form_field, form: form, widget: "text",
                                              mapped_attribute: nil, custom_field: cf)
      end

      it { is_expected.not_to be_valid }
    end

    context "when two fields both map to subject" do
      before { create(:easy_form_designer_form_field, form: form, widget: "text", mapped_attribute: "subject") }

      subject(:field) { build(:easy_form_designer_form_field, form: form, widget: "text", mapped_attribute: "subject") }

      # Subject and description are the deliberate exceptions — their
      # compiled templates already win over a directly-mapped field, so
      # "last one wins" natively isn't the same silent data-loss risk it
      # would be for, say, two fields both mapped to Priority.
      it { is_expected.to be_valid }
    end

    context "when two fields both map to description" do
      before { create(:easy_form_designer_form_field, form: form, widget: "long_text", mapped_attribute: "description") }

      subject(:field) do
        build(:easy_form_designer_form_field, form: form, widget: "long_text", mapped_attribute: "description")
      end

      it { is_expected.to be_valid }
    end
  end

  describe "the five widgets added for PRD M2" do
    %i[number_estimated radio_priority user_assignee].each do |trait|
      it "#{trait} is a valid native mapping" do
        expect(build(:easy_form_designer_form_field, trait, form: form)).to be_valid
      end
    end

    {
      multi_select: { field_format: "list", multiple: true, possible_values: %w[a b] },
      checkbox: { field_format: "bool" },
    }.each do |trait, cf_attrs|
      it "#{trait} is a valid custom-field mapping" do
        cf = create(:issue_custom_field, is_for_all: false, projects: [project.id],
                                         trackers: [tracker], **cf_attrs)

        expect(build(:easy_form_designer_form_field, trait, form: form, custom_field: cf)).to be_valid
      end
    end
  end

  # PRD M7. The rules themselves are exercised in
  # EasyFormDesigner::SubmissionValidator's spec; what matters here is that an
  # unenforceable CONFIGURATION cannot be saved in the first place.
  describe "M7 validation rule configuration" do
    it "accepts an email rule on a text field" do
      expect(build(:easy_form_designer_form_field, :email_validated, form: form)).to be_valid
    end

    it "accepts a url rule on a text field" do
      expect(build(:easy_form_designer_form_field, :url_validated, form: form)).to be_valid
    end

    it "accepts a range on a number field" do
      expect(build(:easy_form_designer_form_field, :ranged, form: form)).to be_valid
    end

    it "accepts a single bound on its own" do
      field = build(:easy_form_designer_form_field, :ranged, form: form, max_value: nil)

      expect(field).to be_valid
    end

    it "rejects an unrecognised format" do
      field = build(:easy_form_designer_form_field, form: form, validation_format: "phone")

      expect(field).not_to be_valid
    end

    # A format rule on a widget that never renders as a single-line input can
    # never be checked against anything the requester actually typed.
    it "rejects an email rule on a long text field" do
      field = build(:easy_form_designer_form_field, :long_text, form: form, validation_format: "email")

      expect(field).not_to be_valid
    end

    it "rejects a range on a text field" do
      field = build(:easy_form_designer_form_field, form: form, min_value: 1)

      expect(field).not_to be_valid
    end

    # An inverted range rejects every possible answer, so it has to be caught
    # while the person who can fix it is still looking at it.
    it "rejects a minimum above the maximum" do
      field = build(:easy_form_designer_form_field, :ranged, form: form, min_value: 40, max_value: 1)

      expect(field).not_to be_valid
    end

    it "accepts a minimum equal to the maximum" do
      field = build(:easy_form_designer_form_field, :ranged, form: form, min_value: 8, max_value: 8)

      expect(field).to be_valid
    end
  end

  # BigDecimal#to_s would render a bound of 40 as "0.4e2" — and this value is
  # shown to the form author in the builder and to the requester in an error
  # message, so the scientific notation would have been visible in both.
  describe ".format_bound" do
    it { expect(described_class.format_bound(BigDecimal("40.000"))).to eq("40") }
    it { expect(described_class.format_bound(BigDecimal("2.5"))).to eq("2.5") }
    it { expect(described_class.format_bound(nil)).to be_nil }
  end

  # PRD M7 follow-up, at Rob's request while manually testing M7: a date bound
  # either fixed or relative to the day of submission ("today" + N days).
  describe "date range validation rule configuration" do
    it "accepts a fixed minimum date" do
      field = build(:easy_form_designer_form_field, :date_due, form: form, min_date: Date.current)

      expect(field).to be_valid
    end

    it "accepts a fixed maximum date on its own" do
      field = build(:easy_form_designer_form_field, :date_due, form: form, max_date: Date.current)

      expect(field).to be_valid
    end

    it "accepts an offset-only minimum" do
      field = build(:easy_form_designer_form_field, :date_due, form: form, min_date_offset_days: -7)

      expect(field).to be_valid
    end

    it "accepts an offset-only maximum" do
      field = build(:easy_form_designer_form_field, :date_due, form: form, max_date_offset_days: 30)

      expect(field).to be_valid
    end

    it "rejects a date bound on a non-date widget" do
      field = build(:easy_form_designer_form_field, form: form, min_date: Date.current)

      expect(field).not_to be_valid
    end

    it "rejects a fixed date and an offset set together on the minimum side" do
      field = build(:easy_form_designer_form_field, :date_due, form: form,
                                                                min_date: Date.current, min_date_offset_days: -7)

      expect(field).not_to be_valid
    end

    it "rejects a fixed date and an offset set together on the maximum side" do
      field = build(:easy_form_designer_form_field, :date_due, form: form,
                                                                max_date: Date.current, max_date_offset_days: 30)

      expect(field).not_to be_valid
    end

    it "rejects a minimum fixed date after the maximum fixed date" do
      field = build(:easy_form_designer_form_field, :date_due, form: form,
                                                                min_date: Date.current + 10, max_date: Date.current)

      expect(field).not_to be_valid
    end

    it "rejects a minimum offset greater than the maximum offset" do
      field = build(:easy_form_designer_form_field, :date_due, form: form,
                                                                min_date_offset_days: 30, max_date_offset_days: -7)

      expect(field).not_to be_valid
    end

    it "accepts a minimum offset equal to the maximum offset" do
      field = build(:easy_form_designer_form_field, :date_due, form: form,
                                                                min_date_offset_days: 5, max_date_offset_days: 5)

      expect(field).to be_valid
    end

    # Deliberate gap, not an oversight: whether a fixed max_date conflicts with
    # a min_date_offset_days depends on what day the rule is evaluated on, so
    # a static check at authoring time could give a correct verdict today and
    # a wrong one tomorrow. See the comment on #date_bounds_ordered.
    it "does not reject a mixed fixed-date-plus-offset combination, even an absurd one" do
      field = build(:easy_form_designer_form_field, :date_due, form: form,
                                                                min_date_offset_days: 3650, max_date: Date.current)

      expect(field).to be_valid
    end
  end

  describe "#effective_min_date and #effective_max_date" do
    let(:today) { Date.new(2026, 8, 31) }

    it "prefers the fixed date over any offset" do
      field = build(:easy_form_designer_form_field, :date_due, form: form, min_date: Date.new(2026, 1, 1))

      expect(field.effective_min_date(today: today)).to eq(Date.new(2026, 1, 1))
    end

    it "resolves a positive offset to a future date" do
      field = build(:easy_form_designer_form_field, :date_due, form: form, max_date_offset_days: 30)

      expect(field.effective_max_date(today: today)).to eq(today + 30)
    end

    it "resolves a negative offset to a past date" do
      field = build(:easy_form_designer_form_field, :date_due, form: form, min_date_offset_days: -7)

      expect(field.effective_min_date(today: today)).to eq(today - 7)
    end

    it "returns nil when neither bound is set" do
      field = build(:easy_form_designer_form_field, :date_due, form: form)

      expect(field.effective_min_date(today: today)).to be_nil
      expect(field.effective_max_date(today: today)).to be_nil
    end
  end

  # PRD M8 — default and hidden/preset fields.
  describe "hidden requires a preset (D3)" do
    it "rejects a hidden field with no preset at all" do
      field = build(:easy_form_designer_form_field, form: form, widget: "select",
                                                     mapped_attribute: "priority_id", hidden: true)

      expect(field).not_to be_valid
    end

    it "accepts a hidden field with a fixed preset" do
      expect(build(:easy_form_designer_form_field, :hidden_priority, form: form)).to be_valid
    end

    it "accepts a hidden date field with a day-offset preset" do
      expect(build(:easy_form_designer_form_field, :preset_due_date_offset, form: form)).to be_valid
    end

    it "accepts a VISIBLE field with a preset — a default, not a stamp" do
      # Not IssuePriority.active.first! — a global enumeration whose ambient
      # contents shouldn't be load-bearing for this test's setup.
      priority = IssuePriority.active.first || create(:issue_priority)
      field = build(:easy_form_designer_form_field, form: form, widget: "select",
                                                     mapped_attribute: "priority_id", hidden: false,
                                                     preset_value: priority.id.to_s)

      expect(field).to be_valid
    end

    it "forces required back to false when hidden" do
      field = create(:easy_form_designer_form_field, :hidden_priority, form: form, required: true)

      expect(field.required).to be(false)
    end
  end

  describe "a fixed preset and a day offset are mutually exclusive" do
    it "rejects both set together" do
      field = build(:easy_form_designer_form_field, :date_due, form: form,
                                                                preset_value: Date.current.to_s,
                                                                preset_offset_days: 7)

      expect(field).not_to be_valid
    end

    it "rejects a day-offset preset on a non-date widget" do
      field = build(:easy_form_designer_form_field, form: form, preset_offset_days: 7)

      expect(field).not_to be_valid
    end
  end

  describe "preset value legality against the mapping" do
    it "rejects a value outside a dropdown's options" do
      field = build(:easy_form_designer_form_field, form: form, widget: "select",
                                                     mapped_attribute: "priority_id",
                                                     preset_value: "not-a-priority-id")

      expect(field).not_to be_valid
    end

    it "rejects a non-numeric preset on a number field" do
      field = build(:easy_form_designer_form_field, :number_estimated, form: form, preset_value: "not-a-number")

      expect(field).not_to be_valid
    end

    it "accepts a numeric preset on a number field" do
      expect(build(:easy_form_designer_form_field, :number_estimated, form: form, preset_value: "5")).to be_valid
    end

    it "rejects an unparsable date preset on a date field" do
      field = build(:easy_form_designer_form_field, :date_due, form: form, preset_value: "not-a-date")

      expect(field).not_to be_valid
    end

    it "rejects a checkbox preset that isn't 0 or 1" do
      cf = create(:issue_custom_field, field_format: "bool", is_for_all: false,
                                       projects: [project.id], trackers: [tracker])
      field = build(:easy_form_designer_form_field, :checkbox, form: form, custom_field: cf, preset_value: "yes")

      expect(field).not_to be_valid
    end

    it "accepts a checkbox preset of 0 or 1" do
      cf = create(:issue_custom_field, field_format: "bool", is_for_all: false,
                                       projects: [project.id], trackers: [tracker])
      field = build(:easy_form_designer_form_field, :checkbox, form: form, custom_field: cf, preset_value: "1")

      expect(field).to be_valid
    end

    it "rejects a preset naming a principal that doesn't exist" do
      field = build(:easy_form_designer_form_field, :user_assignee, form: form, preset_value: "999999")

      expect(field).not_to be_valid
    end

    it "accepts a preset naming a real principal" do
      member = create(:user)
      create(:member, project: project, user: member)

      field = build(:easy_form_designer_form_field, :user_assignee, form: form, preset_value: member.id.to_s)

      expect(field).to be_valid
    end

    context "for a multi_select field" do
      let_it_be(:list_cf) do
        create(:issue_custom_field, field_format: "list", multiple: true, possible_values: %w[a b],
                                    is_for_all: false, projects: [project.id], trackers: [tracker])
      end

      it "rejects a value that isn't one of the field's options" do
        field = build(:easy_form_designer_form_field, :multi_select, form: form, custom_field: list_cf,
                                                                      preset_value: "c")

        expect(field).not_to be_valid
      end

      it "accepts every newline-separated value being a legal option" do
        field = build(:easy_form_designer_form_field, :multi_select, form: form, custom_field: list_cf,
                                                                      preset_value: "a\nb")

        expect(field).to be_valid
      end
    end

    it "is skipped entirely while the field is unmapped — exactly_one_mapping owns that failure" do
      field = build(:easy_form_designer_form_field, form: form, mapped_attribute: nil, custom_field: nil,
                                                     preset_value: "whatever")
      field.valid?

      expect(field.errors[:preset_value]).to be_empty
    end
  end

  describe "#effective_preset_value" do
    let(:today) { Date.new(2026, 8, 31) }

    it "resolves a day offset relative to the given today" do
      field = build(:easy_form_designer_form_field, :preset_due_date_offset, form: form)

      expect(field.effective_preset_value(today: today)).to eq((today + 7).to_s)
    end

    it "resolves a fixed preset as-is" do
      field = build(:easy_form_designer_form_field, :hidden_priority, form: form)

      expect(field.effective_preset_value).to eq(field.preset_value)
    end

    it "splits a multi_select preset on newlines" do
      cf = create(:issue_custom_field, field_format: "list", multiple: true, possible_values: %w[a b],
                                       is_for_all: false, projects: [project.id], trackers: [tracker])
      field = build(:easy_form_designer_form_field, :multi_select, form: form, custom_field: cf,
                                                                    preset_value: "a\nb")

      expect(field.effective_preset_value).to eq(%w[a b])
    end

    it "returns nil when no preset is configured" do
      expect(field.effective_preset_value).to be_nil
    end
  end

  describe "#preset_options" do
    it "offers Yes/No for a checkbox" do
      cf = create(:issue_custom_field, field_format: "bool", is_for_all: false,
                                       projects: [project.id], trackers: [tracker])
      field = build(:easy_form_designer_form_field, :checkbox, form: form, custom_field: cf)

      expect(field.preset_options.map(&:last)).to contain_exactly("1", "0")
    end

    # The "<< me >>" sentinel would resolve to the FORM AUTHOR here, not the
    # requester — a preset is picked once at design time and reused for every
    # future submission, so offering it would be a trap, not a convenience.
    it "excludes the '<< me >>' sentinel from a user field's options" do
      member = create(:user)
      create(:member, project: project, user: member)

      field = build(:easy_form_designer_form_field, :user_assignee, form: form)

      expect(field.preset_options.map(&:first)).not_to include(a_string_starting_with("<<"))
    end

    it "returns no choices for a widget with nothing to pick from" do
      expect(field.preset_options).to eq([])
    end
  end

  # PRD M13 — file attachments.
  describe "the file widget" do
    it "is valid mapped to the attachments pseudo-attribute" do
      expect(build(:easy_form_designer_form_field, :file_upload, form: form)).to be_valid
    end

    # Unlike every other attribute, several file fields legitimately ADD to
    # the same attachment collection — that isn't the silent-overwrite hazard
    # the duplicate-mapping check exists to catch.
    it "allows a second file field on the same form" do
      create(:easy_form_designer_form_field, :file_upload, form: form)
      form.reload

      expect(build(:easy_form_designer_form_field, :file_upload, form: form)).to be_valid
    end

    it "rejects being hidden — there is no such thing as a preset file", :aggregate_failures do
      field = build(:easy_form_designer_form_field, :file_upload, form: form, hidden: true)

      expect(field).not_to be_valid
      expect(field.errors.full_messages.join).to match(/cannot be hidden/i)
    end

    # hidden_requires_preset would otherwise ALSO fire, sending the author
    # hunting for a preset setting that cannot exist for this widget.
    it "reports only the file-specific reason, not 'needs a preset value'" do
      field = build(:easy_form_designer_form_field, :file_upload, form: form, hidden: true)
      field.valid?

      expect(field.errors.full_messages.join).not_to match(/preset value/i)
    end

    it "is #file? and #native?, since it maps to a pseudo-attribute", :aggregate_failures do
      field = build(:easy_form_designer_form_field, :file_upload, form: form)

      expect(field).to be_file
      expect(field).to be_native
      expect(field).to be_mapped
    end

    it "offers no preset choices" do
      expect(build(:easy_form_designer_form_field, :file_upload, form: form).preset_options).to eq([])
    end
  end

  describe "PRD M8 D1 — status_id and category_id as native attributes" do
    it "accepts a select mapped to status_id" do
      field = build(:easy_form_designer_form_field, form: form, widget: "select", mapped_attribute: "status_id")

      expect(field).to be_valid
    end

    it "resolves status_id options from the tracker's issue statuses" do
      # Tracker#issue_statuses is workflow-derived, not a static list — a
      # tracker with no configured workflow has none at all, which would make
      # this assertion trivially true for the wrong reason (two empty
      # arrays). A real transition gives it something to actually resolve.
      create(:workflow_transition, tracker: tracker)

      field = build(:easy_form_designer_form_field, form: form, widget: "select", mapped_attribute: "status_id")

      expect(field.options).to eq(tracker.issue_statuses.map { |s| [s.name, s.id.to_s] })
      expect(field.options).not_to be_empty
    end

    it "accepts a radio mapped to category_id" do
      field = build(:easy_form_designer_form_field, form: form, widget: "radio", mapped_attribute: "category_id")

      expect(field).to be_valid
    end

    it "resolves category_id options from the project's issue categories" do
      category = project.issue_categories.create!(name: "Ops")
      field = build(:easy_form_designer_form_field, form: form, widget: "radio", mapped_attribute: "category_id")

      expect(field.options).to include([category.name, category.id.to_s])
    end
  end
end
