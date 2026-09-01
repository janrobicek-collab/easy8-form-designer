require "easy_extensions/spec_helper"

# PRD M8 — the one behavior a model/service spec cannot prove: that a hidden
# field genuinely renders NO input on the real, server-rendered requester
# page, and that a visible field's default genuinely appears pre-filled.
# IssueBuilder/AnswerResolver/SubmissionValidator are already proven at the
# unit level; this is the view-layer proof those pieces are wired together
# correctly end to end, through the actual controller and ERB template.
RSpec.describe "EasyFormDesignerSubmissions", type: :request, logged: :admin do
  let_it_be(:tracker, refind: true) { create(:tracker) }
  let_it_be(:project, refind: true) { create(:project, trackers: [tracker]) }
  let_it_be(:preset_priority) { create(:issue_priority) }
  let_it_be(:tamper_priority) { create(:issue_priority) }

  let(:form) do
    create(:easy_form_designer_form, project: project, tracker: tracker, name: "Access request")
  end

  before do
    # Visible — the requester sees this pre-filled and may change it.
    create(:easy_form_designer_form_field, form: form, label: "Reason", token: "reason", widget: "text",
                                           mapped_attribute: "subject", hidden: false, preset_value: "Default reason")
    # Hidden — the requester never sees this at all; its value is stamped
    # unconditionally at submit time.
    create(:easy_form_designer_form_field, form: form, label: "Priority", token: "priority", widget: "select",
                                           mapped_attribute: "priority_id", hidden: true,
                                           preset_value: preset_priority.id.to_s)
    form.reload
    # Publish only AFTER the fields exist — Form#publishable? requires every
    # field to already be mapped, so the :published factory trait (which sets
    # status at CREATE time, before any field exists) can't be used here.
    form.publish
  end

  describe "GET /submission/new" do
    before { get new_easy_form_designer_form_submission_path(form) }

    it "renders no input at all for the hidden field" do
      expect(response.body).not_to include('name="answers[priority]"')
    end

    it "pre-fills the visible field's default", :aggregate_failures do
      expect(response).to have_http_status(:success)
      expect(response.body).to include('name="answers[reason]"')
      expect(response.body).to include("Default reason")
    end
  end

  # PRD M13. The one thing no service spec can answer: whether a real
  # multipart upload survives the round trip through Rack, the DS form's
  # native <form enctype>, and `params[:answers].permit!.to_h` — which has to
  # hand an UploadedFile through untouched rather than coercing it.
  describe "POST /submission with a file upload" do
    let(:upload_form) do
      create(:easy_form_designer_form, project: project, tracker: tracker, name: "Upload request")
    end

    before do
      create(:easy_form_designer_form_field, form: upload_form, label: "Reason", token: "reason",
                                             widget: "text", mapped_attribute: "subject")
      create(:easy_form_designer_form_field, :file_upload, form: upload_form, label: "Evidence",
                                                           token: "evidence")
      upload_form.reload
      upload_form.publish
    end

    it "attaches the uploaded file to the created task", :aggregate_failures do
      post easy_form_designer_form_submission_path(upload_form), params: {
        answers: {
          reason: "Broken screen",
          evidence: [fixture_file_upload("files/testfile.txt", "text/plain")],
        },
      }

      issue = Issue.last
      expect(issue.subject).to eq("Broken screen")
      expect(issue.attachments.count).to eq(1)
      expect(issue.attachments.first.filename).to eq("testfile.txt")
      expect(issue.attachments.first.container).to eq(issue)
    end
  end

  describe "GET /submission/new with a file field" do
    let(:upload_form) do
      create(:easy_form_designer_form, project: project, tracker: tracker, name: "Upload request")
    end

    before do
      create(:easy_form_designer_form_field, :file_upload, form: upload_form, label: "Evidence",
                                                           token: "evidence")
      upload_form.reload
      upload_form.publish
      get new_easy_form_designer_form_submission_path(upload_form)
    end

    # Without the multipart enctype the file params arrive empty and the
    # failure is silent — the form submits, the task is created, the file is
    # simply gone.
    it "renders a multipart form with a multi-file input", :aggregate_failures do
      expect(response.body).to include("multipart/form-data")
      expect(response.body).to include('name="answers[evidence][]"')
      expect(response.body).to include("multiple")
    end
  end

  # PRD M11. The view-layer half of conditional sections: a hidden section's
  # fields must render no input at all (the same tamper boundary a hidden
  # field has), and its block must be gone from the compiled description.
  describe "conditional sections" do
    let_it_be(:shown_priority) { create(:issue_priority) }
    let_it_be(:other_priority) { create(:issue_priority) }

    let(:gated_form) do
      create(:easy_form_designer_form, project: project, tracker: tracker, name: "Gated request",
                                       description_template: "Base.{{#extras}} Serial: {{ serial }}{{/extras}}")
    end

    before do
      trigger = create(:easy_form_designer_form_field, :select_priority, form: gated_form,
                                                                         label: "Priority", token: "priority")
      section = create(:easy_form_designer_form_section, :gated, form: gated_form, name: "Extras",
                                                                 token: "extras", visibility_field: trigger,
                                                                 visibility_value: shown_priority.id.to_s)
      create(:easy_form_designer_form_field, form: gated_form, label: "Serial", token: "serial",
                                             widget: "text", mapped_attribute: "subject", section: section)
      gated_form.reload
      gated_form.publish
    end

    it "renders no input for a hidden section's field", :aggregate_failures do
      get new_easy_form_designer_form_submission_path(gated_form)

      # Nothing has been answered yet, so the equals rule is unsatisfied.
      expect(response.body).to include('name="answers[priority]"')
      expect(response.body).not_to include('name="answers[serial]"')
      expect(response.body).not_to include("Extras")
    end

    # The bug this describe block failed to catch for a whole release: the
    # assertions above prove the section stays hidden, and the ones below
    # prove the submitted answers reach the task — but nothing ever rendered
    # the form WITH an answer that satisfies the rule. Because the page was
    # rendered exactly once, with no answers, a gated section could never
    # appear at all. These are that missing assertion.
    describe "POST /submission/refresh" do
      it "renders the section's fields once its rule is satisfied", :aggregate_failures do
        post refresh_easy_form_designer_form_submission_path(gated_form),
             params: { answers: { priority: shown_priority.id.to_s } }

        expect(response).to have_http_status(:success)
        expect(response.body).to include('name="answers[serial]"')
        expect(response.body).to include("Extras")
      end

      it "still renders nothing for a rule that is not satisfied", :aggregate_failures do
        expect {
          post refresh_easy_form_designer_form_submission_path(gated_form),
               params: { answers: { priority: other_priority.id.to_s } }
        }.not_to change(Issue, :count)

        expect(response.body).not_to include('name="answers[serial]"')
        expect(response.body).not_to include("Extras")
      end

      # The refresh re-renders EVERY field, so an answer it doesn't carry back
      # would come back as an empty input — the requester would watch their
      # own typing vanish. Preservation is the params round trip itself, the
      # same way Easy8's issue form preserves what you have entered.
      it "renders the answers it was given back into their inputs" do
        post refresh_easy_form_designer_form_submission_path(gated_form),
             params: { answers: { priority: shown_priority.id.to_s, serial: "SN-KEEP-ME" } }

        expect(response.body).to include("SN-KEEP-ME")
      end

      it "wraps the fields in the frame the requester page targets" do
        post refresh_easy_form_designer_form_submission_path(gated_form),
             params: { answers: { priority: shown_priority.id.to_s } }

        expect(response.body).to include(
          %(<turbo-frame id="#{EasyFormDesignerSubmissionsController::FIELDS_FRAME_ID}")
        )
      end

      it "is refused on a draft form, exactly as rendering one is" do
        gated_form.unpublish

        post refresh_easy_form_designer_form_submission_path(gated_form),
             params: { answers: { priority: shown_priority.id.to_s } }

        expect(response).to have_http_status(:not_found)
      end
    end

    it "wires the refresh script only when a rule has something to watch", :aggregate_failures do
      get new_easy_form_designer_form_submission_path(gated_form)

      expect(response.body).to include("initSubmissionForm")
      # The tokens the script watches are the fields a rule actually reads —
      # here the trigger, never the gated field itself.
      expect(response.body).to include("[&quot;priority&quot;]").or include('["priority"]')
    end

    it "leaves a ruleless form's page free of the refresh machinery", :aggregate_failures do
      get new_easy_form_designer_form_submission_path(form)

      expect(response.body).not_to include("initSubmissionForm")
      expect(response.body).not_to include("efd-refresh-form")
    end

    it "omits a hidden section's block from the created task's description" do
      post easy_form_designer_form_submission_path(gated_form), params: {
        answers: { priority: other_priority.id.to_s, serial: "SN-SNEAKY" },
      }

      expect(Issue.last.description).to eq("Base.")
    end

    it "includes the block, and the answer, when the rule matches" do
      post easy_form_designer_form_submission_path(gated_form), params: {
        answers: { priority: shown_priority.id.to_s, serial: "SN-12345" },
      }

      expect(Issue.last.description).to eq("Base. Serial: SN-12345")
    end
  end

  # With JavaScript off there is no refresh trip, so a requester can satisfy a
  # rule and submit without ever having been shown the section's fields. That
  # is not a dead end — #create re-renders the form with the answers it was
  # given, which makes the section appear with its errors attached, so the
  # second attempt succeeds. One round trip instead of zero.
  #
  # Asserted because it is the fallback the whole feature rests on when the
  # frame doesn't load, and nothing else exercises it.
  describe "POST /submission with a satisfied rule and no answer for its section" do
    let_it_be(:gate_priority) { create(:issue_priority) }

    let(:strict_form) do
      create(:easy_form_designer_form, project: project, tracker: tracker, name: "Strict request")
    end

    before do
      trigger = create(:easy_form_designer_form_field, :select_priority, form: strict_form,
                                                                        label: "Priority", token: "priority")
      section = create(:easy_form_designer_form_section, :gated, form: strict_form, name: "Hardware",
                                                                 token: "hardware", visibility_field: trigger,
                                                                 visibility_value: gate_priority.id.to_s)
      create(:easy_form_designer_form_field, form: strict_form, label: "Serial", token: "serial",
                                             widget: "text", mapped_attribute: "subject",
                                             required: true, section: section)
      strict_form.reload
      strict_form.publish
    end

    it "re-renders the section so the missing answer can be given", :aggregate_failures do
      expect {
        post easy_form_designer_form_submission_path(strict_form),
             params: { answers: { priority: gate_priority.id.to_s } }
      }.not_to change(Issue, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('name="answers[serial]"')
      expect(response.body).to include("Hardware")
    end
  end

  describe "POST /submission (the tamper case)" do
    # A crafted request carries a value for the hidden field's token anyway —
    # something the real requester form never gives a user the means to do,
    # but nothing server-side prevents a raw POST from trying.
    let(:params) do
      { answers: { reason: "Laptop broke", priority: tamper_priority.id.to_s } }
    end

    it "ignores the tampered value and writes the form's own preset", :aggregate_failures do
      expect {
        post easy_form_designer_form_submission_path(form), params: params
      }.to change(Issue, :count).by(1)

      issue = Issue.last
      expect(issue.priority_id).to eq(preset_priority.id)
      expect(issue.priority_id).not_to eq(tamper_priority.id)
    end
  end
end
