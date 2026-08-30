require "easy_extensions/spec_helper"

RSpec.describe EasyFormDesigner::AvailableAttributes, logged: :admin do
  subject(:attributes) { described_class.new(project, tracker) }

  let_it_be(:tracker, refind: true) { create(:tracker) }
  let_it_be(:other_tracker, refind: true) { create(:tracker) }
  let_it_be(:project, refind: true) { create(:project, trackers: [tracker]) }
  let_it_be(:other_project, refind: true) { create(:project, trackers: [other_tracker]) }

  describe "#custom_fields" do
    context "when a field is on both the project and the tracker" do
      let_it_be(:cf) do
        create(:issue_custom_field, field_format: "string",
                                    is_for_all: false,
                                    projects: [project.id], trackers: [tracker])
      end

      it { expect(attributes.custom_fields).to include(cf) }
    end

    # The whole point of the intersection: trusting either list alone is wrong.
    context "when a field is on the project but not the tracker" do
      let_it_be(:cf) do
        create(:issue_custom_field, field_format: "string",
                                    is_for_all: false,
                                    projects: [project.id], trackers: [other_tracker])
      end

      it { expect(attributes.custom_fields).not_to include(cf) }
    end

    context "when a field is on the tracker but not the project" do
      let_it_be(:cf) do
        create(:issue_custom_field, field_format: "string",
                                    is_for_all: false,
                                    projects: [other_project.id], trackers: [tracker])
      end

      it { expect(attributes.custom_fields).not_to include(cf) }
    end

    context "with an unsupported field format" do
      let_it_be(:cf) do
        create(:issue_custom_field, field_format: "user",
                                    is_for_all: false,
                                    projects: [project.id], trackers: [tracker])
      end

      it { expect(attributes.custom_fields).not_to include(cf) }
    end
  end

  describe "#for_widget" do
    let_it_be(:string_cf) do
      create(:issue_custom_field, field_format: "string", is_for_all: false,
                                  projects: [project.id], trackers: [tracker])
    end

    let_it_be(:date_cf) do
      create(:issue_custom_field, field_format: "date", is_for_all: false,
                                  projects: [project.id], trackers: [tracker])
    end

    it "offers only format-compatible custom fields", :aggregate_failures do
      expect(attributes.for_widget("text")[:custom_fields]).to include(string_cf)
      expect(attributes.for_widget("text")[:custom_fields]).not_to include(date_cf)
      expect(attributes.for_widget("date")[:custom_fields]).to include(date_cf)
    end

    it "offers only widget-compatible native attributes", :aggregate_failures do
      expect(attributes.for_widget("text")[:native]).to eq(%w[subject])
      expect(attributes.for_widget("date")[:native]).to match_array(%w[due_date start_date])
      expect(attributes.for_widget("select")[:native]).to match_array(%w[priority_id assigned_to_id])
    end
  end

  describe "#options_for_widget" do
    let_it_be(:string_cf) do
      create(:issue_custom_field, name: "Cost centre", field_format: "string",
                                  is_for_all: false, projects: [project.id], trackers: [tracker])
    end

    it "labels custom fields with their id so authors can disambiguate" do
      option = attributes.options_for_widget("text").detect { |o| o[:type] == "custom_field" }

      expect(option[:label]).to eq("Cost centre (cf_#{string_cf.id})")
    end
  end
end
