module EasyFormDesigner
  # A designed intake form bound to exactly one project + tracker pair.
  #
  # The project/tracker pair is the gateway (PRD M3): it is chosen before any
  # field exists, because it determines which native and custom attributes a
  # field is allowed to map to.
  class Form < EasyFormDesigner::ApplicationRecord
    belongs_to :project
    belongs_to :tracker
    belongs_to :author, class_name: "User"

    has_many :fields,
             -> { order(:position) },
             class_name: "EasyFormDesigner::FormField",
             foreign_key: :form_id,
             inverse_of: :form,
             dependent: :destroy

    # PRD M11. Destroying a section destroys its member fields with it —
    # deleting the container deletes the contents, matching what the Form
    # itself already does to its fields.
    has_many :sections,
             -> { order(:position) },
             class_name: "EasyFormDesigner::FormSection",
             foreign_key: :form_id,
             inverse_of: :form,
             dependent: :destroy

    has_many :submissions,
             class_name: "EasyFormDesigner::FormSubmission",
             inverse_of: :form,
             dependent: :nullify

    accepts_nested_attributes_for :fields, allow_destroy: true
    accepts_nested_attributes_for :sections, allow_destroy: true

    enum :status, { draft: 0, published: 1 }, prefix: true, default: "draft"

    # The description template is authored in CKEditor and stored as HTML —
    # Easy8 renders task descriptions exclusively through
    # CKEditor::HTML::Formatter. Scrubbed on save with the same scrubber
    # EasyIssueTemplate uses for its own issue description, so unsafe markup
    # cannot be persisted while legitimate formatting survives. The subject
    # template is deliberately not scrubbed: it is plain text, never rendered
    # as HTML.
    html_fragment :description_template, scrub: :strip

    # `fields_attributes` must be listed explicitly: Redmine::SafeAttributes
    # filters `safe_attributes=` against exactly this list, top-level keys
    # only — accepts_nested_attributes_for alone does not make a key safe,
    # it just defines the setter that this list has to permit.
    safe_attributes(*%w[name description project_id tracker_id subject_template
                        description_template fields_attributes sections_attributes])

    validates :name, presence: true
    validates :project, :tracker, presence: true
    validate :tracker_enabled_for_project
    validate :all_fields_mapped, if: :status_published?

    scope :like, ->(q) { where(arel_table[:name].matches("%#{q}%")) }
    scope :sorted, -> { order(:name) }
    scope :visible, ->(user = User.current) { where(visible_condition(user)) }

    delegate :to_s, to: :name

    # Draft forms are admin-only; published forms are visible to anyone who may
    # view the form library.
    #
    # @param user [User]
    # @return [String]
    def self.visible_condition(user)
      return "1=1" if user.allowed_to_globally?(:manage_easy_forms)
      return "#{table_name}.status = #{statuses[:published]}" if user.allowed_to_globally?(:view_easy_forms)

      "1=0"
    end

    # @param user [User]
    # @return [Boolean]
    def visible?(user = User.current)
      return true if editable?(user)

      status_published? && user.allowed_to_globally?(:view_easy_forms)
    end

    # @param user [User]
    # @return [Boolean]
    def editable?(user = User.current)
      user.allowed_to_globally?(:manage_easy_forms)
    end

    alias deletable? editable?

    # A form may only be published once every visible field points at a real
    # task attribute. This is the KO criterion from the PRD — it is what keeps
    # submitted data reportable instead of trapped in form-only answers.
    #
    # @return [Boolean]
    def publishable?
      fields.any? && fields.all?(&:mapped?)
    end

    # PRD M11. Tokens of every field sitting in a section whose rule
    # evaluates false for these answers — i.e. fields that were never asked.
    #
    # One implementation, three callers that each need the same answer for a
    # different reason: SubmissionValidator (don't demand a required field
    # nobody was shown), AnswerResolver (discard any value that reached us
    # for one anyway), and the requester view (render no input at all). They
    # deliberately don't share state with each other, so they each ask here.
    #
    # @param answers [Hash] answers keyed by field token
    # @return [Array<String>]
    def tokens_hidden_by_section(answers)
      sections.reject { |section| section.visible?(answers) }
              .flat_map { |section| section.fields.map(&:token) }
    end

    # @param answers [Hash]
    # @return [Array<EasyFormDesigner::FormSection>]
    def visible_sections(answers)
      sections.select { |section| section.visible?(answers) }
    end

    # PRD M11. Tokens of the fields some section's rule actually reads —
    # answering them is what can change which fields the requester is asked,
    # so they are the only ones worth re-rendering the form for.
    #
    # The requester page hands this list to its refresh script, which watches
    # exactly these answers and asks the server for a fresh render when one
    # of them changes. Easy8's issue form marks its own equivalents with a
    # CSS class (`issue_onchange_reload`); a list of tokens is the same idea
    # without needing a hook attribute on a control, which the Design System
    # components cannot carry anyway (their data attributes are a closed
    # whitelist).
    #
    # @return [Array<String>]
    def rule_trigger_tokens
      trigger_ids = sections.filter_map(&:visibility_field_id).uniq
      return [] if trigger_ids.empty?

      fields.select { |field| trigger_ids.include?(field.id) }.map(&:token)
    end

    # @return [Boolean]
    def publish
      self.status = :published
      save
    end

    # @return [Boolean]
    def unpublish
      self.status = :draft
      save
    end

    private

    def tracker_enabled_for_project
      return if project.blank? || tracker.blank?
      return if project.trackers.include?(tracker)

      errors.add(:tracker_id, :invalid)
    end

    def all_fields_mapped
      return if publishable?

      errors.add(:base, :unmapped_field, message: I18n.t("easy_form_designer.error.unmapped_field"))
    end

  end
end
