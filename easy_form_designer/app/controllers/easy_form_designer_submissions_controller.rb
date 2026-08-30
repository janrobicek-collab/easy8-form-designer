# Requester-facing fill-in and submit. Server-rendered — no Vue here, so the
# form is responsive and validated without an SPA in the path.
class EasyFormDesignerSubmissionsController < ApplicationController
  before_action :require_login
  before_action :find_form
  before_action :authorize_submission

  def show
    @submission = @form.submissions.find(params[:submission_id])
  end

  def new
    @answers = {}
  end

  def create
    @answers = submitted_answers

    @missing_fields = missing_required_fields
    if @missing_fields.any?
      flash.now[:error] = l(:error_unable_to_save, default: "Please fill in all required fields.")
      return render :new, status: :unprocessable_content
    end

    @submission = EasyFormDesigner::IssueBuilder.new(@form, @answers, user: User.current).call
    redirect_to easy_form_designer_form_submission_path(@form, submission_id: @submission.id)
  rescue EasyFormDesigner::IssueBuilder::SubmissionError,
         EasyFormDesigner::TemplateCompiler::UnknownToken => e
    flash.now[:error] = e.message
    render :new, status: :unprocessable_content
  end

  private

  def find_form
    @form = EasyFormDesigner::Form.find(params[:easy_form_designer_form_id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  # Drafts are never submittable, regardless of permission.
  def authorize_submission
    return render_404 unless @form.status_published?

    render_403 unless User.current.allowed_to_globally?(:submit_easy_forms)
  end

  # @return [Hash]
  def submitted_answers
    raw = params[:answers]
    return {} if raw.blank?

    raw.permit!.to_h.stringify_keys
  end

  # @return [Array<EasyFormDesigner::FormField>]
  def missing_required_fields
    @form.fields.select { |f| f.required? && @answers[f.token].blank? }
  end

end
