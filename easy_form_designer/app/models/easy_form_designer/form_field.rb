module EasyFormDesigner
  # One question on a form.
  #
  # Every field must resolve to a real Easy8 task attribute — either a native
  # issue attribute or an IssueCustomField valid for the parent form's
  # project + tracker pair. There is deliberately no "form-only" field type:
  # choice options are derived from the mapped attribute rather than authored
  # here, so an unmapped field has nothing to render.
  class FormField < EasyFormDesigner::ApplicationRecord
    # Widget types supported by the first slice. Widening this list is PRD M2.
    WIDGETS = %w[text long_text select date].freeze

    # Native issue attributes a field may map to.
    NATIVE_ATTRIBUTES = %w[subject description priority_id assigned_to_id due_date start_date].freeze

    belongs_to :form,
               class_name: "EasyFormDesigner::Form",
               inverse_of: :fields

    belongs_to :custom_field,
               class_name: "IssueCustomField",
               optional: true

    safe_attributes(*%w[label help_text token widget required position mapped_attribute custom_field_id])

    validates :label, :token, :widget, presence: true
    validates :widget, inclusion: { in: WIDGETS }
    validates :token, uniqueness: { scope: :form_id }
    validates :mapped_attribute,
              inclusion: { in: NATIVE_ATTRIBUTES },
              allow_blank: true

    validate :exactly_one_mapping
    validate :custom_field_available_for_form

    before_validation :default_token

    scope :sorted, -> { order(:position) }

    delegate :to_s, to: :label

    # @return [Boolean]
    def mapped?
      mapped_attribute.present? || custom_field_id.present?
    end

    # @return [Boolean]
    def native?
      mapped_attribute.present?
    end

    # @return [Boolean]
    def custom?
      custom_field_id.present?
    end

    # Choice options for select-style widgets, read from whatever the field is
    # mapped to. Never authored on the field itself.
    #
    # @return [Array<Array(String, String)>] label/value pairs
    def options
      return [] unless widget == "select"

      if custom?
        custom_field.possible_values.to_a.map { |v| [v, v] }
      else
        native_options
      end
    end

    private

    def native_options
      case mapped_attribute
      when "priority_id"
        IssuePriority.active.map { |p| [p.name, p.id.to_s] }
      when "assigned_to_id"
        form.project.assignable_users.map { |u| [u.name, u.id.to_s] }
      else
        []
      end
    end

    def default_token
      return if token.present? || label.blank?

      base = label.to_s.parameterize(separator: "_").presence || "field"
      candidate = base
      suffix = 1
      taken = form&.fields&.reject { |f| f == self }&.map(&:token) || []
      while taken.include?(candidate)
        suffix += 1
        candidate = "#{base}_#{suffix}"
      end

      self.token = candidate
    end

    def exactly_one_mapping
      return if mapped_attribute.present? ^ custom_field_id.present?

      errors.add(:base, I18n.t("easy_form_designer.error.unmapped_field"))
    end

    # A custom field is only legal here if it survives the project ∩ tracker
    # intersection — the same rule core applies in
    # EasyIssueTemplate#available_custom_fields.
    def custom_field_available_for_form
      return if custom_field_id.blank? || form.blank?

      available = EasyFormDesigner::AvailableAttributes.new(form.project, form.tracker).custom_fields
      return if available.map(&:id).include?(custom_field_id)

      errors.add(:custom_field_id, :invalid)
    end

  end
end
