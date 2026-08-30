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
        create(:issue_custom_field, field_format: "version",
                                    is_for_all: false,
                                    projects: [project.id], trackers: [tracker])
      end

      it { expect(attributes.custom_fields).not_to include(cf) }
    end

    # "user" was excluded pending the user-lookup widget (PRD M2) — now built.
    context "with a user field format" do
      let_it_be(:cf) do
        create(:issue_custom_field, field_format: "user",
                                    is_for_all: false,
                                    projects: [project.id], trackers: [tracker])
      end

      it { expect(attributes.custom_fields).to include(cf) }
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
      expect(attributes.for_widget("select")[:native]).to eq(%w[priority_id])
      expect(attributes.for_widget("number")[:native]).to eq(%w[estimated_hours])
      expect(attributes.for_widget("radio")[:native]).to eq(%w[priority_id])
      expect(attributes.for_widget("user")[:native]).to eq(%w[assigned_to_id])
    end

    # Assignee moved from Dropdown to User lookup exclusively — a plain
    # <select> of every assignable user is worse UX than the searchable
    # lookup, and offering the same attribute two ways with no distinction
    # would be confusing, not flexible.
    it "no longer offers Assignee under the Dropdown widget" do
      expect(attributes.for_widget("select")[:native]).not_to include("assigned_to_id")
    end
  end

  describe "multi-value custom fields" do
    let_it_be(:single_list_cf) do
      create(:issue_custom_field, field_format: "list", multiple: false, is_for_all: false,
                                  projects: [project.id], trackers: [tracker],
                                  possible_values: %w[a b])
    end

    let_it_be(:multi_list_cf) do
      create(:issue_custom_field, field_format: "list", multiple: true, is_for_all: false,
                                  projects: [project.id], trackers: [tracker],
                                  possible_values: %w[a b])
    end

    # A single-value widget rendered against a multiple: true field could only
    # ever submit one of the field's values through a plain <select>, silently
    # discarding the rest of what the custom field allows.
    it "does not offer a multi-value field under a single-value widget", :aggregate_failures do
      expect(attributes.for_widget("select")[:custom_fields]).not_to include(multi_list_cf)
      expect(attributes.for_widget("radio")[:custom_fields]).not_to include(multi_list_cf)
    end

    it "does not offer a single-value field under multi_select" do
      expect(attributes.for_widget("multi_select")[:custom_fields]).not_to include(single_list_cf)
    end

    it "offers each field under its matching widget", :aggregate_failures do
      expect(attributes.for_widget("select")[:custom_fields]).to include(single_list_cf)
      expect(attributes.for_widget("multi_select")[:custom_fields]).to include(multi_list_cf)
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
