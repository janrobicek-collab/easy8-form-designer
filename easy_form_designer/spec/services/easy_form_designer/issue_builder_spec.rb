require "easy_extensions/spec_helper"

# The KO criterion of the whole engine: a submitted answer must land on the
# task attribute the form author mapped it to. If this spec passes, the
# feasibility question from PRD #687043 is answered.
RSpec.describe EasyFormDesigner::IssueBuilder, logged: :admin do
  subject(:build_issue) { described_class.new(form, answers).call }

  let_it_be(:tracker, refind: true) { create(:tracker) }
  let_it_be(:project, refind: true) { create(:project, trackers: [tracker]) }

  let_it_be(:text_cf) do
    create(:issue_custom_field,
           field_format: "string",
           projects: [project.id],
           trackers: [tracker])
  end

  let_it_be(:list_cf) do
    create(:issue_custom_field,
           field_format: "list",
           possible_values: %w[Windows macOS Linux],
           projects: [project.id],
           trackers: [tracker])
  end

  let(:form) do
    create(:easy_form_designer_form,
           project: project,
           tracker: tracker,
           subject_template: "Access request — {{ employee_name }}",
           description_template: "Employee: {{ employee_name }}\nPlatform: {{ platform }}")
  end

  let(:answers) do
    { "employee_name" => "John Snow", "platform" => "Linux" }
  end

  before do
    create(:easy_form_designer_form_field,
           form: form, label: "Employee name", token: "employee_name",
           widget: "text", custom_field: text_cf, mapped_attribute: nil)
    create(:easy_form_designer_form_field,
           form: form, label: "Platform", token: "platform",
           widget: "select", custom_field: list_cf, mapped_attribute: nil)
    form.reload
    form.publish
  end

  describe "#call" do
    it "creates one issue and one submission" do
      expect { build_issue }.to change(Issue, :count).by(1)
        .and change(EasyFormDesigner::FormSubmission, :count).by(1)
    end

    it "routes the task to the form's project and tracker", :aggregate_failures do
      issue = build_issue.issue

      expect(issue.project).to eq(project)
      expect(issue.tracker).to eq(tracker)
      expect(issue.author).to eq(User.current)
    end

    it "compiles the subject and description from the templates", :aggregate_failures do
      issue = build_issue.issue

      expect(issue.subject).to eq("Access request — John Snow")
      # Redmine normalises stored text to CRLF, so compare on normalised breaks.
      expect(issue.description.gsub("\r\n", "\n")).to eq("Employee: John Snow\nPlatform: Linux")
    end

    # This is the assertion that matters. Redmine silently drops custom values
    # when tracker/project are assigned after them (defect #19368), so a naive
    # implementation passes every other example here and fails only this one.
    it "writes each answer to the custom field it was mapped to", :aggregate_failures do
      issue = build_issue.issue.reload

      expect(issue.custom_field_value(text_cf)).to eq("John Snow")
      expect(issue.custom_field_value(list_cf)).to eq("Linux")
    end

    it "keeps the raw answers on the submission as an audit trail" do
      expect(build_issue.payload).to eq(answers)
    end

    context "when a field maps to a native attribute" do
      let(:form) do
        create(:easy_form_designer_form,
               project: project, tracker: tracker,
               subject_template: "Request from {{ who }}")
      end

      let(:answers) { { "who" => "Jane", "why" => "Laptop broke" } }

      before do
        create(:easy_form_designer_form_field,
               form: form, label: "Who", token: "who",
               widget: "text", mapped_attribute: "subject")
        create(:easy_form_designer_form_field,
               form: form, label: "Why", token: "why",
               widget: "long_text", mapped_attribute: "description")
        form.reload
        form.publish
      end

      it "sets the native attribute, with the subject template taking precedence" do
        issue = build_issue.issue

        expect(issue.description).to eq("Laptop broke")
        expect(issue.subject).to eq("Request from Jane")
      end
    end

    context "when the form has no subject template" do
      let(:form) do
        create(:easy_form_designer_form,
               project: project, tracker: tracker, name: "Fallback form")
      end

      let(:answers) { {} }

      before { form.reload }

      it "falls back to the form name rather than failing validation" do
        expect(build_issue.issue.subject).to eq("Fallback form")
      end
    end

    context "when the issue is invalid" do
      before do
        allow_any_instance_of(Issue).to receive(:save).and_return(false)
        allow_any_instance_of(Issue).to receive_message_chain(:errors, :full_messages).and_return(["boom"])
      end

      it "raises and rolls back both records", :aggregate_failures do
        expect { build_issue }.to raise_error(described_class::SubmissionError, /boom/)
        expect(EasyFormDesigner::FormSubmission.count).to eq(0)
      end
    end
  end
end
