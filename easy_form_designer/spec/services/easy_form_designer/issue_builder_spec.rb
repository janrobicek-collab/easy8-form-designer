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

    context "with a checkbox field left unchecked" do
      let_it_be(:bool_cf) do
        create(:issue_custom_field, field_format: "bool", projects: [project.id], trackers: [tracker])
      end

      let(:form) do
        create(:easy_form_designer_form, project: project, tracker: tracker, name: "Checkbox form")
      end

      let(:answers) { { "is_private" => "0" } }

      before do
        create(:easy_form_designer_form_field, form: form, label: "Private", token: "is_private",
                                               widget: "checkbox", custom_field: bool_cf, mapped_attribute: nil)
        form.reload
        form.publish
      end

      # The bug this fixes: false.blank? is true in Rails, so a naive
      # `next if value.blank?` guard treats "explicitly unchecked" identically
      # to "never answered" and drops the attribute instead of setting it
      # false. custom_field_value returns "0"/"1" (string) for a bool CF,
      # never a real Ruby boolean — that's Redmine's own representation.
      it "still writes false to the custom field rather than leaving it unset" do
        issue = build_issue.issue.reload

        expect(issue.custom_field_value(bool_cf)).to eq("0")
      end
    end

    context "with a multi_select field" do
      let_it_be(:multi_cf) do
        create(:issue_custom_field, field_format: "list", multiple: true,
                                    possible_values: %w[Windows macOS Linux],
                                    projects: [project.id], trackers: [tracker])
      end

      let(:form) do
        create(:easy_form_designer_form, project: project, tracker: tracker, name: "Multi-select form")
      end

      let(:answers) { { "platforms" => %w[Windows Linux] } }

      before do
        create(:easy_form_designer_form_field, form: form, label: "Platforms", token: "platforms",
                                               widget: "multi_select", custom_field: multi_cf,
                                               mapped_attribute: nil)
        form.reload
        form.publish
      end

      it "writes every selected value to the custom field" do
        issue = build_issue.issue.reload

        expect(issue.custom_field_value(multi_cf)).to match_array(%w[Windows Linux])
      end
    end

    context "with a user-lookup field" do
      let_it_be(:assignee) { create(:user) }
      let_it_be(:membership) { create(:member, project: project, user: assignee) }

      let(:form) do
        create(:easy_form_designer_form, project: project, tracker: tracker, name: "Assignee form")
      end

      let(:answers) { { "assignee" => assignee.id.to_s } }

      before do
        create(:easy_form_designer_form_field, form: form, label: "Assignee", token: "assignee",
                                               widget: "user", mapped_attribute: "assigned_to_id")
        form.reload
        form.publish
      end

      it "assigns the task to the selected principal" do
        expect(build_issue.issue.assigned_to_id).to eq(assignee.id)
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

      # The controller needs the rejected Issue itself, not just the joined
      # message, to attribute each error back to the field that wrote it.
      it "carries the rejected issue on the error" do
        expect { build_issue }.to raise_error(described_class::SubmissionError) { |error|
          expect(error.issue).to be_a(Issue)
        }
      end
    end

    # PRD M8. AnswerResolver is exercised in its own spec; what matters HERE
    # is that IssueBuilder actually routes through it end to end, on a real
    # Issue, for both a native attribute and a custom field.
    context "with a hidden preset field" do
      # Explicit, not IssuePriority.active.first! — a global enumeration
      # whose ambient contents depend on what else has run in the suite.
      # An explicitly-created record makes this test's own expectations
      # independent of that.
      let_it_be(:preset_priority) { create(:issue_priority) }

      let(:form) do
        create(:easy_form_designer_form, project: project, tracker: tracker, name: "Hidden preset form")
      end

      let(:answers) { {} }

      before do
        create(:easy_form_designer_form_field, form: form, label: "Priority", token: "priority", widget: "select",
                                               mapped_attribute: "priority_id", hidden: true,
                                               preset_value: preset_priority.id.to_s)
        form.reload
        form.publish
      end

      it "stamps the preset even though the requester never answered it" do
        expect(build_issue.issue.priority_id).to eq(preset_priority.id)
      end

      # The actual security property: a hidden field is not rendered on the
      # requester form at all, but nothing stops a crafted request from
      # POSTing a value for its token anyway. The form's own preset must win
      # regardless of what (if anything) was submitted for it.
      context "when the request carries a value for the hidden field's token anyway" do
        let_it_be(:other_priority) { create(:issue_priority) }
        let(:answers) { { "priority" => other_priority.id.to_s } }

        it "ignores the submitted value and writes the preset" do
          expect(other_priority.id).not_to eq(preset_priority.id) # sanity: the two really do differ
          expect(build_issue.issue.priority_id).to eq(preset_priority.id)
        end
      end

      it "records the RESOLVED value, not the raw submission, on the audit trail" do
        expect(build_issue.payload["priority"]).to eq(preset_priority.id.to_s)
      end
    end

    context "with a hidden preset on a custom field" do
      # Deliberately NOT named text_cf: the outer describe's own before hook
      # (which runs for every example under #call, this nested context
      # included) already maps a field to the outer let_it_be(:text_cf) — a
      # same-named local override here would shadow that reference too
      # (let/let_it_be always resolve to the innermost definition, even from
      # a hook written in an ancestor group), so the outer hook's field and
      # this context's own field would collide on the very custom field this
      # test is trying to isolate.
      let_it_be(:routing_cf) do
        create(:issue_custom_field, field_format: "string", projects: [project.id], trackers: [tracker])
      end

      let(:form) do
        create(:easy_form_designer_form, project: project, tracker: tracker, name: "Hidden CF form")
      end

      let(:answers) { {} }

      before do
        create(:easy_form_designer_form_field, form: form, label: "Routing tag", token: "routing_tag",
                                               widget: "text", custom_field: routing_cf, mapped_attribute: nil,
                                               hidden: true, preset_value: "portal-intake")
        form.reload
        form.publish
      end

      it "writes the preset to the custom field" do
        issue = build_issue.issue.reload

        expect(issue.custom_field_value(routing_cf)).to eq("portal-intake")
      end
    end

    context "with a hidden day-offset preset on a date field" do
      let(:form) do
        create(:easy_form_designer_form, project: project, tracker: tracker, name: "Hidden due date form")
      end

      let(:answers) { {} }

      before do
        create(:easy_form_designer_form_field, :preset_due_date_offset, form: form, label: "Due date",
                                                                        token: "due_date")
        form.reload
        form.publish
      end

      it "stamps due_date as today + the configured offset" do
        expect(build_issue.issue.due_date).to eq(Date.current + 7)
      end
    end

    # TemplateCompiler itself has no special-case knowledge of hidden fields —
    # it just renders whatever answers hash it's handed. What matters is that
    # IssueBuilder hands it the RESOLVED hash (post-AnswerResolver), so a
    # template referencing a hidden field's token sees the preset like any
    # other answer, not a blank the requester never had a chance to fill in.
    context "when a subject template references a hidden field's token" do
      # Same reason as routing_cf above: not named text_cf, to avoid shadowing
      # the outer describe's shared let_it_be(:text_cf) that its own before
      # hook (inherited into this context) also maps a field to.
      let_it_be(:source_cf) do
        create(:issue_custom_field, field_format: "string", projects: [project.id], trackers: [tracker])
      end

      let(:form) do
        create(:easy_form_designer_form, project: project, tracker: tracker,
                                         subject_template: "Intake via {{ source }}")
      end

      let(:answers) { {} }

      before do
        create(:easy_form_designer_form_field, form: form, label: "Source", token: "source", widget: "text",
                                               custom_field: source_cf, mapped_attribute: nil,
                                               hidden: true, preset_value: "self-service portal")
        form.reload
        form.publish
      end

      it "resolves the token to the preset" do
        expect(build_issue.issue.subject).to eq("Intake via self-service portal")
      end
    end

    # PRD M13. A file field's answer is uploads, not a value — it takes its
    # own path (#attach_files) rather than either attribute hash, and lands
    # as real Attachments through acts_as_attachable, exactly as a file
    # dragged onto the issue would.
    context "with a file upload field" do
      let(:form) do
        create(:easy_form_designer_form, project: project, tracker: tracker, name: "Upload form")
      end

      let(:upload) { fixture_file_upload("files/testfile.txt", "text/plain") }
      let(:answers) { { "evidence" => [upload] } }

      before do
        create(:easy_form_designer_form_field, :file_upload, form: form, label: "Evidence", token: "evidence")
        form.reload
        form.publish
      end

      it "attaches the uploaded file to the created task", :aggregate_failures do
        issue = build_issue.issue.reload

        expect(issue.attachments.count).to eq(1)
        expect(issue.attachments.first.filename).to eq("testfile.txt")
      end

      # Satisfies Attachment's own description_required? validation on
      # instances that enable it, and makes the Files tab readable when a
      # form has several file fields.
      it "describes the attachment with the field's label" do
        expect(build_issue.issue.reload.attachments.first.description).to eq("Evidence")
      end

      context "with several files on one field" do
        let(:answers) do
          { "evidence" => [fixture_file_upload("files/testfile.txt", "text/plain"),
                           fixture_file_upload("files/yoda-tux-256.png", "image/png")] }
        end

        it "attaches every one of them" do
          expect(build_issue.issue.reload.attachments.map(&:filename))
            .to contain_exactly("testfile.txt", "yoda-tux-256.png")
        end
      end

      # The JSON payload column cannot serialise an UploadedFile at all, so
      # the audit trail records what was uploaded instead.
      it "records filenames on the submission, not the upload objects" do
        expect(build_issue.payload["evidence"]).to eq(["testfile.txt"])
      end

      context "when the template references the file field" do
        let(:form) do
          create(:easy_form_designer_form, project: project, tracker: tracker,
                                           subject_template: "Report — {{ evidence }}")
        end

        it "renders the filenames rather than an unusable object" do
          expect(build_issue.issue.subject).to eq("Report — testfile.txt")
        end
      end

      # A task created with some files silently missing is worse than a clear
      # failure. Attachment validates size/extension itself; a rejection has
      # to take the whole submission down with it — and the rollback then
      # removes both the rows and the files already written to disk.
      context "when a file is rejected by Attachment's own validation" do
        before { allow(Setting).to receive(:attachment_max_size).and_return("0") }

        it "aborts the submission instead of half-attaching", :aggregate_failures do
          expect { build_issue }.to raise_error(described_class::SubmissionError, /Evidence/)
          expect(Issue.where(subject: "Upload form")).not_to exist
          expect(EasyFormDesigner::FormSubmission.count).to eq(0)
        end
      end
    end

    context "D1 — a hidden preset on status_id and category_id" do
      let_it_be(:category) { project.issue_categories.create!(name: "Ops") }

      # Tracker#issue_statuses (what AvailableAttributes/FormField#native_options
      # actually reads for a status_id mapping) is derived from the tracker's
      # OWN workflow transitions, not a static list — a freshly-created
      # tracker with no workflow configured has none at all, so a status_id
      # preset would have nothing legal to be.
      let_it_be(:status_transition) { create(:workflow_transition, tracker: tracker) }

      let(:form) do
        create(:easy_form_designer_form, project: project, tracker: tracker, name: "Hidden routing form")
      end

      let(:answers) { {} }

      before do
        create(:easy_form_designer_form_field, form: form, label: "Status", token: "status", widget: "select",
                                               mapped_attribute: "status_id", hidden: true,
                                               preset_value: tracker.issue_statuses.first.id.to_s)
        create(:easy_form_designer_form_field, form: form, label: "Category", token: "category", widget: "select",
                                               mapped_attribute: "category_id", hidden: true,
                                               preset_value: category.id.to_s)
        form.reload
        form.publish
      end

      it "stamps both status and category", :aggregate_failures do
        issue = build_issue.issue

        expect(issue.status_id).to eq(tracker.issue_statuses.first.id)
        expect(issue.category_id).to eq(category.id)
      end
    end
  end
end
