module EasyFormDesigner
  # Compiles one form submission into a real Easy8 task.
  #
  # This is the KO criterion of the whole engine: every answer must land on the
  # attribute the form author mapped it to, so the resulting task is
  # filterable, reportable and automatable — not a wall of prose.
  #
  # Assignment ORDER matters. `project` and `tracker` must be set before any
  # custom value is assigned, or the custom values are silently dropped
  # (Redmine defect #19368). Custom values also go through the
  # `custom_field_values=` hash form, never hand-built CustomValue records.
  class IssueBuilder

    class SubmissionError < StandardError; end

    attr_reader :form, :answers, :user, :issue, :submission

    # @param form [EasyFormDesigner::Form]
    # @param answers [Hash] raw answers keyed by field token
    # @param user [User] the requester
    def initialize(form, answers, user: User.current)
      @form = form
      @answers = (answers || {}).stringify_keys
      @user = user
    end

    # Creates the issue and its submission record in one transaction.
    #
    # @return [EasyFormDesigner::FormSubmission]
    # @raise [SubmissionError] if the issue is invalid
    def call
      compiler = EasyFormDesigner::TemplateCompiler.new(form, answers)

      EasyFormDesigner::FormSubmission.transaction do
        @issue = build_issue(compiler)

        raise SubmissionError, @issue.errors.full_messages.join(", ") unless @issue.save

        @submission = EasyFormDesigner::FormSubmission.create!(
          form: form,
          issue: @issue,
          user: user,
          payload: answers
        )
      end

      submission
    end

    private

    # @return [Issue]
    def build_issue(compiler)
      issue = Issue.new

      # 1. Project and tracker FIRST — everything else depends on them.
      issue.project = form.project
      issue.tracker = form.tracker

      # 2. Authorship. Status is deliberately not set here: assigning the
      #    tracker above already runs core's `self.status ||= default_status`
      #    (issue.rb:547), which resolves it from `tracker.default_status`.
      #    There is no `IssueStatus.default` in this Redmine version.
      issue.author = user

      # 3. Native attributes the author mapped fields onto.
      #
      # NOTE: deliberately NOT via `safe_attributes=`. That filters by the
      # *requester's* permissions, which would silently drop values the form
      # author explicitly mapped — a requester without :edit_issues could not
      # set priority, and the task would come out mis-fielded with no error
      # shown to anyone. The form definition is the authority here, not the
      # submitter's rights. Revisit alongside M8 (hidden/preset fields), which
      # carries the same tension.
      native_attributes.each { |name, value| issue.send(:"#{name}=", value) }

      # 4. Compiled templates. These win over a field mapped straight at
      #    subject/description, because the template is the author's explicit
      #    statement of what the task should read like.
      issue.subject = compiler.subject if form.subject_template.present?
      issue.description = compiler.description if form.description_template.present?

      # A tracker-valid subject is mandatory in Redmine; fall back to the form
      # name rather than failing validation with an empty string.
      issue.subject = form.name if issue.subject.blank?

      # 5. Custom values LAST, via the hash form.
      issue.custom_field_values = custom_field_values if custom_field_values.any?

      issue
    end

    # @return [Hash{String => Object}]
    def native_attributes
      @native_attributes ||= form.fields.select(&:native?).each_with_object({}) do |field, acc|
        next unless answerable?(field)

        acc[field.mapped_attribute] = answers[field.token]
      end
    end

    # @return [Hash{Integer => Object}]
    def custom_field_values
      @custom_field_values ||= form.fields.select(&:custom?).each_with_object({}) do |field, acc|
        next unless answerable?(field)

        acc[field.custom_field_id] = answers[field.token]
      end
    end

    # A checkbox left unchecked ("0") is a deliberate "no" answer, not a
    # missing one — false.blank? is true in Rails, so the generic blank-skip
    # below would otherwise treat "unchecked" identically to "never answered"
    # and silently drop the attribute instead of setting it false. The raw
    # "0"/"1" string is passed straight through either way: that is Redmine's
    # own storage representation for a bool-format custom field, matching
    # what TemplateCompiler already assumes when rendering it.
    #
    # @return [Boolean]
    def answerable?(field)
      return true if field.widget == "checkbox"

      answers[field.token].present?
    end

  end
end
