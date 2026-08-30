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

    has_many :submissions,
             class_name: "EasyFormDesigner::FormSubmission",
             inverse_of: :form,
             dependent: :nullify

    accepts_nested_attributes_for :fields, allow_destroy: true

    enum :status, { draft: 0, published: 1 }, prefix: true, default: "draft"

    # `fields_attributes` must be listed explicitly: Redmine::SafeAttributes
    # filters `safe_attributes=` against exactly this list, top-level keys
    # only — accepts_nested_attributes_for alone does not make a key safe,
    # it just defines the setter that this list has to permit.
    safe_attributes(*%w[name description project_id tracker_id subject_template
                        description_template fields_attributes])

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
