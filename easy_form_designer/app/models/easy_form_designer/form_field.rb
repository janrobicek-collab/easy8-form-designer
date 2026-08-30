module EasyFormDesigner
  # One question on a form.
  #
  # Every field must resolve to a real Easy8 task attribute — either a native
  # issue attribute or an IssueCustomField valid for the parent form's
  # project + tracker pair. There is deliberately no "form-only" field type:
  # choice options are derived from the mapped attribute rather than authored
  # here, so an unmapped field has nothing to render.
  class FormField < EasyFormDesigner::ApplicationRecord
    # Widget types supported so far. PRD M2's full set.
    WIDGETS = %w[text long_text select date number radio multi_select checkbox user].freeze

    # Widgets whose choices are label/value pairs resolved from the mapped
    # attribute (a custom field's possible_values, or a hardcoded native
    # list) — see #options.
    CHOICE_WIDGETS = %w[select radio multi_select].freeze

    # Native issue attributes a field may map to.
    NATIVE_ATTRIBUTES = %w[subject description priority_id assigned_to_id due_date start_date
                           estimated_hours].freeze

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
    validate :attribute_not_already_mapped_by_another_field

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

    # Choice options for select-style widgets (dropdown, radio, multi-select),
    # read from whatever the field is mapped to. Never authored on the field
    # itself.
    #
    # @return [Array<Array(String, String)>] label/value pairs
    def options
      return [] unless CHOICE_WIDGETS.include?(widget)

      if custom?
        # possible_values_options, not the raw possible_values column —
        # possible_values only holds anything for "list"/"bool" formats.
        # "enumeration" (and "user") formats keep their choices in a real
        # association (CustomFieldEnumeration records, Principal records)
        # and possible_values is always nil for them; reading it directly
        # silently produced zero options — a Radio buttons field mapped to
        # an enumeration custom field rendered with no inputs at all, not
        # an error. possible_values_options is the one format-aware entry
        # point that handles every supported format correctly. `form` is
        # passed as the scoping object because it responds to #project the
        # way an Issue would, letting formats that scope by project (e.g.
        # UserFormat) resolve the same way they would on a real issue.
        #
        # The return shape is not consistent across formats, so it has to be
        # normalised here: ListFormat#possible_values_options returns flat
        # values ("Windows", "Linux", ...), while EnumerationFormat and
        # UserFormat return [label, value] pairs.
        custom_field.possible_values_options(form).map { |option| option.is_a?(Array) ? option : [option, option] }
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

    # Two fields writing the same attribute silently overwrite one another —
    # IssueBuilder's native_attributes/custom_field_values hashes are keyed
    # by attribute, so whichever field is processed last simply wins, with
    # no error shown to the admin who built the form or the requester who
    # filled it in. Subject and Description are the sole exceptions: their
    # compiled templates already take precedence over a directly-mapped
    # field (see IssueBuilder#build_issue), so a plain "last one wins" there
    # isn't the same silent-data-loss risk it would be for, say, two fields
    # both mapped to Priority.
    def attribute_not_already_mapped_by_another_field
      return if form.blank?
      return if mapped_attribute.in?(%w[subject description])

      siblings = form.fields.reject { |f| f == self }

      conflict =
        if custom_field_id.present?
          siblings.any? { |f| f.custom_field_id == custom_field_id }
        elsif mapped_attribute.present?
          siblings.any? { |f| f.mapped_attribute == mapped_attribute }
        end

      errors.add(:base, I18n.t("easy_form_designer.error.duplicate_mapping")) if conflict
    end

  end
end
