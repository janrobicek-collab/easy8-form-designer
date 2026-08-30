require "easy_extensions/spec_helper"

RSpec.describe EasyFormDesigner::TemplateCompiler, logged: :admin do
  subject(:compiler) { described_class.new(form, answers) }

  let_it_be(:tracker, refind: true) { create(:tracker) }
  let_it_be(:project, refind: true) { create(:project, trackers: [tracker]) }

  let(:form) do
    create(:easy_form_designer_form,
           project: project, tracker: tracker,
           subject_template: "Request — {{ who }}",
           description_template: "Who: {{ who }}\nWhen: {{ when_needed }}")
  end

  let(:answers) { { "who" => "John Snow", "when_needed" => "2026-09-15" } }

  before do
    create(:easy_form_designer_form_field,
           form: form, label: "Who", token: "who",
           widget: "text", mapped_attribute: "subject")
    create(:easy_form_designer_form_field,
           form: form, label: "When needed", token: "when_needed",
           widget: "date", mapped_attribute: "due_date")
    form.reload
  end

  describe "#subject" do
    it { expect(compiler.subject).to eq("Request — John Snow") }

    context "when the template is blank" do
      let(:form) do
        create(:easy_form_designer_form, project: project, tracker: tracker, subject_template: nil)
      end

      it { expect(compiler.subject).to eq("") }
    end

    context "when an answer contains HTML and newlines" do
      let(:answers) { { "who" => "a & b <c>\nsecond line", "when_needed" => "2026-09-15" } }

      # The subject is a plain varchar, never rendered as HTML — escaping or
      # <br>-ing it the way the description does would put literal entities
      # and tags into the task title.
      it "is left exactly as typed", :aggregate_failures do
        expect(compiler.subject).to eq("Request — a & b <c>\nsecond line")
        expect(compiler.subject).not_to include("&amp;")
        expect(compiler.subject).not_to include("<br>")
      end
    end
  end

  describe "#description" do
    it "resolves every token" do
      expect(compiler.description).to eq("Who: John Snow\nWhen: #{I18n.l(Date.parse('2026-09-15'))}")
    end

    context "when an answer is missing" do
      let(:answers) { { "who" => "John Snow" } }

      it "renders an empty string rather than the raw token" do
        expect(compiler.description).to eq("Who: John Snow\nWhen: ")
      end
    end

    context "when the template references a token no field provides" do
      let(:form) do
        create(:easy_form_designer_form,
               project: project, tracker: tracker,
               description_template: "Ghost: {{ deleted_field }}")
      end

      # Loud failure is the point — a template pointing at a field somebody
      # removed should not quietly produce a half-empty task description.
      it "raises UnknownToken" do
        expect { compiler.description }.to raise_error(described_class::UnknownToken, /deleted_field/)
      end
    end

    # The description is rendered as HTML by CKEditor::HTML::Formatter, so an
    # answer substituted into it is markup unless escaped — and answers are
    # requester-supplied.
    context "when an answer contains HTML" do
      let(:answers) { { "who" => "<script>alert(1)</script>", "when_needed" => "2026-09-15" } }

      it "escapes it rather than emitting live markup" do
        expect(compiler.description).to include("&lt;script&gt;alert(1)&lt;/script&gt;")
        expect(compiler.description).not_to include("<script>")
      end
    end

    context "when an answer spans multiple lines" do
      let(:answers) { { "who" => "line one\nline two", "when_needed" => "2026-09-15" } }

      # Newlines are invisible in HTML, so a multi-line answer would otherwise
      # collapse onto one line in the created task.
      it "converts its line breaks to <br>" do
        expect(compiler.description).to include("line one<br>line two")
      end
    end

    context "when a token is wrapped in editor markup" do
      let(:form) do
        create(:easy_form_designer_form,
               project: project, tracker: tracker,
               description_template: "<p><strong>{{ who }}</strong></p>")
      end

      it "still resolves the token" do
        expect(compiler.description).to eq("<p><strong>John Snow</strong></p>")
      end
    end

    context "when CKEditor emitted non-breaking spaces inside the braces" do
      let(:form) do
        create(:easy_form_designer_form,
               project: project, tracker: tracker,
               description_template: "Who:&nbsp;{{&nbsp;who&nbsp;}}")
      end

      # A token that looks correct in the editor but silently fails to resolve
      # is the worst possible failure mode here.
      it "still resolves the token" do
        expect(compiler.description).to eq("Who: John Snow")
      end
    end
  end


  describe "token whitespace tolerance" do
    let(:form) do
      create(:easy_form_designer_form,
             project: project, tracker: tracker,
             description_template: "A{{who}} B{{ who }} C{{   who   }}")
    end

    it "accepts any padding inside the braces" do
      expect(compiler.description).to eq("AJohn Snow BJohn Snow CJohn Snow")
    end
  end

  describe "choice fields" do
    let_it_be(:list_cf) do
      create(:issue_custom_field, field_format: "list",
                                  possible_values: %w[Windows Linux],
                                  projects: [project.id], trackers: [tracker])
    end

    let(:form) do
      create(:easy_form_designer_form,
             project: project, tracker: tracker,
             description_template: "Platform: {{ platform }}")
    end

    let(:answers) { { "platform" => "Linux" } }

    before do
      create(:easy_form_designer_form_field,
             form: form, label: "Platform", token: "platform",
             widget: "select", custom_field: list_cf, mapped_attribute: nil)
      form.reload
    end

    it "renders the human label, not the stored value" do
      expect(compiler.description).to eq("Platform: Linux")
    end
  end

  describe ".unknown_tokens" do
    it "lists template tokens no field provides" do
      expect(described_class.unknown_tokens(form, "{{ who }} and {{ nope }}")).to eq(["nope"])
    end
  end
end
