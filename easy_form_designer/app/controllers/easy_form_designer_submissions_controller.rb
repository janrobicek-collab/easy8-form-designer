# Requester-facing fill-in and submit. Server-rendered — no Vue here, so the
# form is responsive and validated without an SPA in the path.
class EasyFormDesignerSubmissionsController < ApplicationController
  # The Turbo frame wrapping every field on the requester form — the one
  # region whose content depends on the answers so far (PRD M11). Named here
  # rather than in the view because both the view that renders the frame and
  # the form that targets it need the same string.
  FIELDS_FRAME_ID = "efd-form-fields".freeze

  before_action :require_login
  before_action :find_form
  before_action :authorize_submission

  helper_method :existing_principal_value

  def show
    @submission = @form.submissions.find(params[:submission_id])
  end

  def new
    @answers = default_answers
    @field_errors = {}
  end

  # PRD M11. Re-renders the fields for the answers given so far, and nothing
  # else: no validation, no Issue, no persistence of any kind.
  #
  # This is what makes a conditional section actually appear. Section
  # visibility is a function of the answers, so it can only be decided at
  # render time — and until this action existed the requester form was
  # rendered exactly once, with no answers, which meant a gated section could
  # never be shown at all.
  #
  # Deliberately server-side: RuleEvaluator stays the single implementation
  # of what an operator means. The browser never evaluates a rule, it only
  # posts the answers back and swaps in whatever this returns. Easy8's own
  # new-issue form works the same way (EasyIssuesController#dependent_fields,
  # likewise an action with no body — the state is rebuilt from params).
  def refresh
    @answers = submitted_answers
    @field_errors = {}

    render partial: "fields", layout: false
  end

  def create
    @answers = submitted_answers

    validator = EasyFormDesigner::SubmissionValidator.new(@form, @answers)
    @field_errors = validator.errors

    if @field_errors.any?
      flash.now[:error] = l(:error_unable_to_save, default: "Please correct the highlighted fields.")
      return render :new, status: :unprocessable_content
    end

    @submission = EasyFormDesigner::IssueBuilder.new(@form, @answers, user: User.current).call
    redirect_to easy_form_designer_form_submission_path(@form, submission_id: @submission.id)
  rescue EasyFormDesigner::IssueBuilder::SubmissionError => e
    # Anything the validator could not know about — a native Issue validation
    # (due date before start date), or a custom-field rule that only applies to
    # a value in context.
    #
    # Every error is either attributed to a field or kept in the flash, never
    # neither: partitioning rather than "flash only if nothing was attributed"
    # is deliberate, because the latter hides the remaining errors as soon as
    # one of them happens to be attributable.
    @field_errors, unattributed = partition_issue_errors(e.issue, e.message)
    flash.now[:error] = unattributed.join(", ") if unattributed.any?
    render :new, status: :unprocessable_content
  rescue EasyFormDesigner::TemplateCompiler::UnknownToken => e
    # Not a requester error at all — the form's own template references a token
    # no field provides, so no answer could ever fix it. Stays a flash.
    flash.now[:error] = e.message
    @field_errors = {}
    render :new, status: :unprocessable_content
  end

  private

  # Seeds a VISIBLE field's default preset as its initial answer, so the
  # requester sees it pre-filled and may change or clear it — PRD M8's other
  # half from a hidden field, which never renders at all (see the view,
  # `@form.fields.reject(&:hidden?)`). Deliberately only called here, never
  # from #create's error re-render: a requester who cleared a default meant
  # it, and re-seeding it there would silently undo that.
  #
  # @return [Hash{String => Object}]
  def default_answers
    @form.fields.reject(&:hidden?).select(&:preset?).each_with_object({}) do |field, acc|
      acc[field.token] = field.effective_preset_value
    end
  end

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

  # Splits a rejected Issue's errors into the ones that belong to a specific
  # form field and the ones that belong to nobody, so a native-attribute or
  # in-context custom-field failure lands on its own input like every validator
  # error does, and anything unattributable still reaches the requester.
  #
  # @param issue [Issue, nil]
  # @param fallback [String] the joined message, used when there is no issue
  # @return [Array(Hash{String => Array<String>}, Array<String>)]
  def partition_issue_errors(issue, fallback)
    return [{}, [fallback]] if issue.blank?

    by_token = {}
    unattributed = []

    issue.errors.each do |error|
      field = field_for_error(error)

      if field
        (by_token[field.token] ||= []) << error.message
      else
        unattributed << issue.errors.full_message(error.attribute, error.message)
      end
    end

    [by_token, unattributed]
  end

  # Two different lookups, because core registers the two kinds differently:
  #
  #   * native attributes — errors.add(:due_date, ...), keyed by the attribute
  #     name, which is exactly what FormField#mapped_attribute holds.
  #   * custom fields — CustomFieldValue#validate_value adds to :base but tags
  #     the error with attributes: ["cf_<id>"] (app/models/custom_field_value.rb).
  #     That tag is the only reliable link back; the message text itself is just
  #     the custom field's name prefixed to a sentence.
  #
  # @param error [ActiveModel::Error]
  # @return [EasyFormDesigner::FormField, nil]
  def field_for_error(error)
    cf_tags = Array(error.options[:attributes])

    @form.fields.detect do |field|
      if field.custom?
        cf_tags.include?("cf_#{field.custom_field_id}")
      elsif field.native?
        error.attribute.to_s == field.mapped_attribute
      end
    end
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
