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

    # Carries the rejected Issue so the caller can attribute its errors back to
    # the form fields that produced them, instead of flattening them into one
    # unactionable sentence. See EasyFormDesignerSubmissionsController#create.
    class SubmissionError < StandardError

      attr_reader :issue

      def initialize(message, issue = nil)
        super(message)
        @issue = issue
      end

    end

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
      compiler = EasyFormDesigner::TemplateCompiler.new(form, serializable_answers)

      EasyFormDesigner::FormSubmission.transaction do
        @issue = build_issue(compiler)

        # PRD M13. Before #save, matching what IssuesController#create itself
        # does — acts_as_attachable's before_save hook is what actually links
        # the created Attachments to the issue. Running inside this
        # transaction is deliberate: Attachment's own
        # `after_rollback :delete_from_disk, on: :create` then cleans the
        # physical files up too if anything below fails, so a rejected
        # submission leaves neither rows nor orphaned files on disk.
        attach_files(@issue)

        raise SubmissionError.new(@issue.errors.full_messages.join(", "), @issue) unless @issue.save

        @submission = EasyFormDesigner::FormSubmission.create!(
          form: form,
          issue: @issue,
          user: user,
          payload: serializable_answers
        )
      end

      submission
    end

    private

    # PRD M8 — every hidden field's submitted value (if a crafted request even
    # sent one; the requester form itself never renders an input for it) is
    # discarded here in favour of the form's own preset. See AnswerResolver
    # for why that overwrite is the actual security control. Memoized: this
    # is read from several places below and the whole of one #call must agree
    # on a single resolved hash — recomputing it partway through could let a
    # later read see a different answer than an earlier one already used.
    #
    # @return [Hash{String => Object}]
    def resolved_answers
      @resolved_answers ||= EasyFormDesigner::AnswerResolver.new(form, answers).call
    end

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
      # submitter's rights. PRD M8's hidden/preset fields lean on exactly
      # this: a hidden priority/status/category preset is written here
      # whether or not the submitter could set it themselves — see
      # AnswerResolver, which is what makes that safe against a submitter
      # simply not raising it.
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

    # File fields are `native?` (they map to the "attachments"
    # pseudo-attribute) but must never reach this hash: there is no usable
    # `issue.attachments=` setter for uploads, and the association setter
    # would REPLACE the collection instead of appending to it. They go
    # through #attach_files instead.
    #
    # @return [Hash{String => Object}]
    def native_attributes
      @native_attributes ||= form.fields.select { |f| f.native? && !f.file? }.each_with_object({}) do |field, acc|
        next unless answerable?(field)

        acc[field.mapped_attribute] = resolved_answers[field.token]
      end
    end

    # @return [Array<EasyFormDesigner::FormField>]
    def file_fields
      @file_fields ||= form.fields.select(&:file?)
    end

    # PRD M13. Turns each file field's uploads into real Attachments on the
    # issue, via acts_as_attachable's own idiom (the same call
    # IssuesController#create makes).
    #
    # The attachment description is the FIELD'S LABEL, for two reasons: it
    # satisfies Attachment's `description_required?` validation on instances
    # that switch the `attachment_description_required` setting on, and it
    # makes the task's Files tab readable ("Screenshot", "Signed contract")
    # instead of a bare list of filenames.
    #
    # A rejected file (too large, disallowed extension — Attachment validates
    # both itself) aborts the WHOLE submission rather than quietly producing a
    # task with some files missing. A half-attached task nobody was told about
    # is a worse outcome than a clear "this file was rejected, try again".
    def attach_files(issue)
      file_fields.each do |field|
        uploads = Array(resolved_answers[field.token]).reject(&:blank?)
        next if uploads.empty?

        result = issue.save_attachments(
          uploads.each_with_index.to_h { |file, i| [i.to_s, { "file" => file, "description" => field.label }] }
        )
        next if result[:unsaved].blank?

        raise SubmissionError.new(rejected_files_message(field, result[:unsaved]), issue)
      end
    end

    # @return [String]
    def rejected_files_message(field, unsaved)
      details = unsaved.map { |a| [a.filename, a.errors.full_messages.presence&.join(", ")].compact.join(" — ") }

      "#{field.label}: #{details.join("; ")}"
    end

    # PRD M13. The same answers with each file field's uploads reduced to
    # their filenames — the only shape safe to leave the attachment path.
    #
    # Two consumers need it, for the same underlying reason (neither can do
    # anything with an ActionDispatch::Http::UploadedFile): `payload` is a
    # JSON column that cannot serialise one, and TemplateCompiler renders
    # text. Filenames are also the genuinely useful answer for both — an
    # audit trail of what was uploaded, and "photo.png, receipt.pdf" in a
    # description.
    #
    # @return [Hash{String => Object}]
    def serializable_answers
      @serializable_answers ||=
        if file_fields.empty?
          resolved_answers
        else
          resolved_answers.merge(file_fields.to_h { |field| [field.token, uploaded_filenames(field)] })
        end
    end

    # @return [Array<String>]
    def uploaded_filenames(field)
      Array(resolved_answers[field.token]).filter_map { |u| u.try(:original_filename) }
    end

    # @return [Hash{Integer => Object}]
    def custom_field_values
      @custom_field_values ||= form.fields.select(&:custom?).each_with_object({}) do |field, acc|
        next unless answerable?(field)

        acc[field.custom_field_id] = resolved_answers[field.token]
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

      resolved_answers[field.token].present?
    end

  end
end
