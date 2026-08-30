# Requester-facing fill-in and submit. Server-rendered — no Vue here, so the
# form is responsive and validated without an SPA in the path.
class EasyFormDesignerSubmissionsController < ApplicationController
  before_action :require_login
  before_action :find_form
  before_action :authorize_submission

  helper_method :existing_principal_value

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
    @form.fields.select { |f| f.required? && missing?(f) }
  end

  # A checkbox always submits a value ("1" or "0"), so it is never blank —
  # "required" on a checkbox has to mean "must be checked", the ordinary
  # meaning of a required consent/confirmation box, not merely "answered".
  #
  # @return [Boolean]
  def missing?(field)
    return @answers[field.token] != "1" if field.widget == "checkbox"

    @answers[field.token].blank?
  end

  # Resolves a stored user-lookup answer (a Principal id) back to the
  # {value:, label:} shape DesignSystem::Components::Autocomplete expects for
  # its value: — only relevant when re-rendering the form after a validation
  # error, since a fresh form has no answer yet.
  #
  # @param id [String, Integer, nil]
  # @return [Hash, nil]
  def existing_principal_value(id)
    return nil if id.blank?

    principal = Principal.find_by(id: id)
    return nil unless principal

    { value: principal.id.to_s, label: principal.name }
  end

end
