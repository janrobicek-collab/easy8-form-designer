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

  describe "radio fields" do
    let(:form) do
      create(:easy_form_designer_form,
             project: project, tracker: tracker,
             description_template: "Priority: {{ priority }}")
    end

    let_it_be(:priority) { create(:issue_priority) }

    let(:answers) { { "priority" => priority.id.to_s } }

    before do
      create(:easy_form_designer_form_field, form: form, label: "Priority", token: "priority",
                                             widget: "radio", mapped_attribute: "priority_id")
      form.reload
    end

    it "resolves the same way select does" do
      expect(compiler.description).to eq("Priority: #{priority.name}")
    end
  end

  describe "multi_select fields" do
    let_it_be(:list_cf) do
      create(:issue_custom_field, field_format: "list", multiple: true,
                                  possible_values: %w[Windows Linux macOS],
                                  projects: [project.id], trackers: [tracker])
    end

    let(:form) do
      create(:easy_form_designer_form,
             project: project, tracker: tracker,
             description_template: "Platforms: {{ platforms }}")
    end

    before do
      create(:easy_form_designer_form_field, form: form, label: "Platforms", token: "platforms",
                                             widget: "multi_select", custom_field: list_cf,
                                             mapped_attribute: nil)
      form.reload
    end

    context "with multiple values selected" do
      let(:answers) { { "platforms" => %w[Windows macOS] } }

      it "joins the human labels" do
        expect(compiler.description).to eq("Platforms: Windows, macOS")
      end
    end

    context "with nothing selected" do
      let(:answers) { { "platforms" => [] } }

      it "renders an empty string" do
        expect(compiler.description).to eq("Platforms: ")
      end
    end
  end

  describe "checkbox fields" do
    let(:form) do
      create(:easy_form_designer_form,
             project: project, tracker: tracker,
             description_template: "Private: {{ is_private }}")
    end

    before do
      create(:easy_form_designer_form_field, form: form, label: "Private", token: "is_private",
                                             widget: "checkbox",
                                             custom_field: create(:issue_custom_field, field_format: "bool",
                                                                                       projects: [project.id],
                                                                                       trackers: [tracker]),
                                             mapped_attribute: nil)
      form.reload
    end

    context "when checked" do
      let(:answers) { { "is_private" => "1" } }

      it { expect(compiler.description).to eq("Private: Yes") }
    end

    context "when unchecked" do
      let(:answers) { { "is_private" => "0" } }

      # An explicit "no" answer must render as "No" — the whole point of this
      # widget existing is to distinguish "unchecked" from "unanswered", and a
      # blank render here would erase that distinction right back out.
      it { expect(compiler.description).to eq("Private: No") }
    end
  end

  describe "user fields" do
    let_it_be(:member) { create(:user) }

    let(:form) do
      create(:easy_form_designer_form,
             project: project, tracker: tracker,
             description_template: "Assignee: {{ assignee }}")
    end

    let(:answers) { { "assignee" => member.id.to_s } }

    before do
      create(:easy_form_designer_form_field, form: form, label: "Assignee", token: "assignee",
                                             widget: "user", mapped_attribute: "assigned_to_id")
      form.reload
    end

    it "resolves the id to the principal's name" do
      expect(compiler.description).to eq("Assignee: #{member.name}")
    end
  end

  describe ".unknown_tokens" do
    it "lists template tokens no field provides" do
      expect(described_class.unknown_tokens(form, "{{ who }} and {{ nope }}")).to eq(["nope"])
    end

    # A section marker is not a field token; reporting it as one would send
    # the author looking for a field that was never supposed to exist.
    it "does not report a section marker as an unknown field token" do
      expect(described_class.unknown_tokens(form, "{{#extras}}{{ who }}{{/extras}}")).to be_empty
    end
  end

  # PRD M11 — conditional section blocks, in Mustache's open/close shape.
  describe "section blocks" do
    let_it_be(:shown_priority) { create(:issue_priority) }
    let_it_be(:other_priority) { create(:issue_priority) }

    let(:form) do
      create(:easy_form_designer_form, project: project, tracker: tracker,
                                       description_template: description_template)
    end

    let(:description_template) { "Base line.{{#extras}}Serial: {{ serial }}{{/extras}}" }
    let(:answers) { { "priority" => priority_answer, "serial" => "SN-12345" } }
    let(:priority_answer) { shown_priority.id.to_s }

    before do
      trigger = create(:easy_form_designer_form_field, :select_priority, form: form, label: "Priority",
                                                                         token: "priority")
      section = create(:easy_form_designer_form_section, :gated, form: form, name: "Extras", token: "extras",
                                                                 visibility_field: trigger,
                                                                 visibility_value: shown_priority.id.to_s)
      create(:easy_form_designer_form_field, form: form, label: "Serial", token: "serial", widget: "text",
                                             mapped_attribute: "subject", section: section)
      form.reload
    end

    it "keeps the block, markers removed, when the section is visible" do
      expect(compiler.description).to eq("Base line.Serial: SN-12345")
    end

    context "when the section is hidden" do
      let(:priority_answer) { other_priority.id.to_s }

      it "drops the block entirely" do
        expect(compiler.description).to eq("Base line.")
      end

      # The block's own tokens must never reach the flat substitution pass —
      # they belong to fields nobody was asked.
      it "does not raise on a token inside the dropped block" do
        expect { compiler.description }.not_to raise_error
      end
    end

    # CKEditor wraps a marker typed on its own line in its own paragraph.
    # Consuming that wrapper is what stops every compiled description
    # growing a trail of empty paragraphs.
    context "with CKEditor-style paragraph wrapping" do
      let(:description_template) do
        "<p>Base line.</p><p>{{#extras}}</p><p>Serial: {{ serial }}</p><p>{{/extras}}</p>"
      end

      it "leaves no empty paragraph behind when visible" do
        expect(compiler.description).to eq("<p>Base line.</p><p>Serial: SN-12345</p>")
      end

      context "when hidden" do
        let(:priority_answer) { other_priority.id.to_s }

        it "leaves no empty paragraph behind when dropped" do
          expect(compiler.description).to eq("<p>Base line.</p>")
        end
      end
    end

    context "when the template names a section that no longer exists" do
      let(:description_template) { "{{#gone}}orphaned{{/gone}}" }

      it "fails loudly rather than emitting the block unconditionally" do
        expect { compiler.description }.to raise_error(described_class::UnknownToken, /gone/)
      end
    end
  end

  describe ".unknown_section_tokens" do
    it "lists section markers the form no longer has" do
      expect(described_class.unknown_section_tokens(form, "{{#gone}}x{{/gone}}")).to eq(["gone"])
    end
  end
end
