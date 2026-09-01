require "easy_extensions/spec_helper"

# PRD M8's builder-side wiring: form_json actually serialises hidden/preset
# fields into the embedded JSON the Vue builder hydrates from, and the new
# preset-options endpoint actually returns what FormField#preset_options
# computes, through the real controller and routing — not just the method
# call in isolation.
RSpec.describe "EasyFormDesignerForms", type: :request, logged: :admin do
  let_it_be(:tracker, refind: true) { create(:tracker) }
  let_it_be(:project, refind: true) { create(:project, trackers: [tracker]) }

  let(:form) { create(:easy_form_designer_form, project: project, tracker: tracker, name: "Routing form") }

  let!(:hidden_field) do
    create(:easy_form_designer_form_field, :hidden_priority, form: form, label: "Priority", token: "priority")
  end

  before { form.reload }

  describe "GET /form-designer/forms/:id/edit" do
    before { get edit_easy_form_designer_form_path(form) }

    it "embeds the field's hidden/preset state in the builder's hydration JSON", :aggregate_failures do
      expect(response).to have_http_status(:success)

      embedded = Nokogiri::HTML(response.body).at_css("#app-easy-form-designer-initial").text
      field_json = JSON.parse(embedded)["fields"].first

      expect(field_json["hidden"]).to be(true)
      expect(field_json["preset_value"]).to eq(hidden_field.preset_value)
    end
  end

  # PRD M11. The ordering problem this exists to solve: a brand-new section
  # and a field assigned to it are created in the SAME save, so the field
  # cannot carry a real section_id yet. The builder references the section by
  # a temporary key and the controller resolves it once the section is saved.
  describe "PATCH with a new section and a field assigned to it" do
    it "resolves the temporary key to the saved section's real id", :aggregate_failures do
      patch easy_form_designer_form_path(form), params: {
        easy_form_designer_form: {
          sections_attributes: [
            { temp_key: "new-1", position: 1, name: "Hardware", token: "hardware" },
          ],
          fields_attributes: [
            { id: hidden_field.id, position: 1, label: hidden_field.label, token: hidden_field.token,
              widget: hidden_field.widget, mapped_attribute: hidden_field.mapped_attribute,
              hidden: true, preset_value: hidden_field.preset_value },
            { position: 2, label: "Serial", token: "serial", widget: "text",
              mapped_attribute: "subject", section_id: "new-1" },
          ],
        },
      }, as: :json

      expect(response).to have_http_status(:success)

      # Two sections now exist: the form's own auto-created default (holding
      # the pre-existing hidden_field, whose payload above never mentions
      # section_id and so keeps it) plus the one this PATCH just created.
      section = form.reload.sections.find_by!(name: "Hardware")
      serial = form.fields.find_by(token: "serial")

      expect(form.sections.count).to eq(2)
      expect(section.name).to eq("Hardware")
      expect(serial.section_id).to eq(section.id)
    end
  end

  # PRD M11. The rule editor's operator list is EasyQuery's own, per the
  # field's filter type — so the wording matches any other Easy8 filter and
  # this engine translates nothing itself.
  describe "GET preset-options — the operator half" do
    it "offers a list field only the operators :list allows", :aggregate_failures do
      get preset_options_easy_form_designer_form_path(form, widget: "select",
                                                            mapped_attribute: "priority_id")

      body = JSON.parse(response.body)

      expect(body["filter_type"]).to eq("list")
      expect(body["operators"].map { |o| o["value"] }).to eq(%w[= !])
      # Labels come from EasyQuery.operators, already translated.
      expect(body["operators"].map { |o| o["label"] }).to eq(["is", "is not"])
    end

    it "offers a text field the text operators, which include no equals" do
      get preset_options_easy_form_designer_form_path(form, widget: "text",
                                                            mapped_attribute: "subject")

      operators = JSON.parse(response.body)["operators"].map { |o| o["value"] }

      expect(operators).to eq(["~", "!~", "^~", "$~", "!*", "*"])
    end

    it "offers a date field the period operators", :aggregate_failures do
      get preset_options_easy_form_designer_form_path(form, widget: "date",
                                                            mapped_attribute: "due_date")

      body = JSON.parse(response.body)
      operators = body["operators"].map { |o| o["value"] }

      expect(body["filter_type"]).to eq("date_period")
      expect(operators).to include("t", "w", "lm", ">t-", "><t-")

      # date_period_1/2 are the two MODES of Easy8's composite period widget,
      # not dropdown choices — EasyQuery gives them no label, and showing the
      # raw string to an author would be worse than omitting them.
      expect(operators).not_to include("date_period_1", "date_period_2")
    end

    it "marks the value-less operators so the client can hide the value input" do
      get preset_options_easy_form_designer_form_path(form, widget: "select",
                                                            mapped_attribute: "category_id")

      by_value = JSON.parse(response.body)["operators"].index_by { |o| o["value"] }

      expect(by_value["*"]["needs_value"]).to be(false)
      expect(by_value["="]["needs_value"]).to be(true)
    end

    it "offers nothing for a file field, whose answer isn't filterable", :aggregate_failures do
      get preset_options_easy_form_designer_form_path(
        form, widget: "file", mapped_attribute: EasyFormDesigner::FormField::ATTACHMENTS_ATTRIBUTE
      )

      body = JSON.parse(response.body)

      expect(body["filter_type"]).to be_nil
      expect(body["operators"]).to be_empty
    end
  end

  describe "GET /form-designer/forms/:id/preset-options" do
    before do
      get preset_options_easy_form_designer_form_path(
        form, widget: "select", mapped_attribute: "priority_id"
      )
    end

    it "returns the same choices FormField#preset_options computes", :aggregate_failures do
      expect(response).to have_http_status(:success)

      body = JSON.parse(response.body)
      expected = IssuePriority.active.map { |p| { "label" => p.name, "value" => p.id.to_s } }

      expect(body["options"]).to eq(expected)
    end
  end
end
