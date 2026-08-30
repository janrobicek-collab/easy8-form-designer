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
  end
end
