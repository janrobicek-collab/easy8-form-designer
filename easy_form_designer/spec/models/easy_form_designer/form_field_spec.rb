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
end
