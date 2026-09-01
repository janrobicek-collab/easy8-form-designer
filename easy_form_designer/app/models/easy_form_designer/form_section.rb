module EasyFormDesigner
  # A named group of fields on a form, optionally gated behind a visibility
  # rule (PRD M11).
  #
  # The rule is what makes this more than cosmetic grouping: one field's
  # ANSWER decides whether this section's fields are asked at all. That is a
  # different thing from a field's own `hidden` flag (PRD M8), which the
  # author fixes at design time and which always carries exactly one preset
  # value. A conditionally-hidden section's fields have no value — they
  # simply weren't asked — so AnswerResolver DISCARDS them rather than
  # stamping anything. The two concepts must not be conflated.
  class FormSection < EasyFormDesigner::ApplicationRecord
    # Operators that need two values rather than one (EasyQuery's "between").
    RANGE_OPERATORS = %w[><].freeze

    # Operators whose value is a day count, not something to compare against.
    DAY_COUNT_OPERATORS = %w[t- >t- <t- ><t-].freeze

    # Operators whose value is Easy8's period hash rather than a list.
    COMPOSITE_PERIOD_OPERATORS = %w[date_period_1 date_period_2].freeze

    # Operators for which a membership check against the field's own options
    # is meaningful. A "contains" rule takes free text even on a list field,
    # so restricting every operator to the option list would be wrong.
    MEMBERSHIP_OPERATORS = %w[= ! &].freeze

    belongs_to :form,
               class_name: "EasyFormDesigner::Form",
               inverse_of: :sections

    # The field this section's rule reads. Deliberately no dependent option
    # here — FormField#clear_dependent_section_rules owns that cleanup,
    # because nulling this column alone would leave the operator and value
    # behind and trip #rule_all_or_nothing on the next save.
    belongs_to :visibility_field,
               class_name: "EasyFormDesigner::FormField",
               optional: true

    has_many :fields,
             -> { order(:position) },
             class_name: "EasyFormDesigner::FormField",
             foreign_key: :section_id,
             inverse_of: :section,
             dependent: :destroy

    # `token` is settable because the builder sends one for a brand-new
    # section (as it already does for a new field), which is what lets the
    # controller match its temporary key back to the saved row — see
    # EasyFormDesignerFormsController#temp_key_to_section_id.
    safe_attributes(*%w[name token position visibility_field_id visibility_operator
                        visibility_value visibility_values])

    validates :name, presence: true
    validates :token, presence: true, uniqueness: { scope: :form_id }

    validate :rule_all_or_nothing
    validate :visibility_field_belongs_to_form
    validate :visibility_field_can_drive_a_rule
    validate :visibility_field_not_itself_conditional
    validate :visibility_operator_allowed_for_field
    validate :visibility_value_shape
    validate :visibility_value_legal_for_field

    before_validation :default_token
    before_validation :clear_value_for_hidden_value_operators

    scope :sorted, -> { order(:position) }

    delegate :to_s, to: :name

    # @return [Boolean]
    def rule?
      visibility_field_id.present?
    end

    # The rule's value(s). Stored as JSON, exactly as
    # EasyAutomations::Condition#parsed_value stores its own: "between" needs
    # two values, "=" can take several, and the period operators take a hash
    # rather than a list.
    #
    # A plain scalar written by hand (or by an older client) is tolerated
    # rather than blowing up — note JSON.parse("315") is legal and yields a
    # number, so the rescue only catches genuinely non-JSON text.
    #
    # @return [Array, Hash]
    def parsed_value
      return [] if visibility_value.blank?

      JSON.parse(visibility_value)
    rescue JSON::ParserError
      [visibility_value]
    end

    alias visibility_values parsed_value

    # The builder sends and receives an array; the column holds JSON. Keeping
    # the encoding here means no caller has to remember to do it.
    #
    # @param values [Array, Hash]
    def visibility_values=(values)
      values = values.compact_blank if values.is_a?(Array)

      self.visibility_value = values.blank? ? nil : values.to_json
    end

    # The EasyQuery filter type this rule operates on, which is what decides
    # the operators available to it.
    #
    # @return [Symbol, nil]
    def filter_type
      visibility_field&.filter_type
    end

    # Every operator this rule may legally use — straight from EasyQuery, so
    # a date field offers periods and a list field offers is/is not, exactly
    # as the same field would in any other Easy8 filter.
    #
    # @return [Array<String>]
    def available_operators
      EasyQuery.operators_by_filter_type[filter_type] || []
    end

    # Whether this section's fields are asked at all, for one set of answers.
    #
    # A section with no rule is always visible — that is the whole point of
    # an ungated group.
    #
    # @param answers [Hash] answers keyed by field token
    # @return [Boolean]
    def visible?(answers)
      return true unless rule?
      return true if visibility_field.blank?

      answers = (answers || {}).stringify_keys

      EasyFormDesigner::RuleEvaluator.new(
        operator: visibility_operator,
        values: parsed_value,
        answer: answers[visibility_field.token],
        filter_type: filter_type
      ).call
    end

    private

    # Same derivation as FormField#default_token, for the same reason: the
    # author names the thing, and the template refers to it by a stable
    # machine-safe handle.
    def default_token
      return if token.present? || name.blank?

      base = name.to_s.parameterize(separator: "_").presence || "section"
      candidate = base
      suffix = 1
      taken = form&.sections&.reject { |s| s == self }&.map(&:token) || []
      while taken.include?(candidate)
        suffix += 1
        candidate = "#{base}_#{suffix}"
      end

      self.token = candidate
    end

    # A rule needs a field and an operator; it needs a value too unless the
    # operator is one that takes none ("is set", "today", …). Anything in
    # between isn't "no rule", it's a rule nobody can evaluate.
    def rule_all_or_nothing
      specified = [visibility_field_id, visibility_operator.presence, visibility_value.presence]
      return if specified.all?(&:blank?)

      required = [visibility_field_id, visibility_operator.presence]
      required << visibility_value.presence unless value_optional?
      return if required.all?(&:present?)

      errors.add(:base, I18n.t("easy_form_designer.error.incomplete_visibility_rule"))
    end

    def visibility_field_belongs_to_form
      return if visibility_field.blank? || form.blank?
      return if visibility_field.form_id == form_id

      errors.add(:visibility_field_id, :invalid)
    end

    # A field with no filter type has no operators to offer — a file field,
    # whose answer is uploads, or one that isn't mapped to anything yet.
    def visibility_field_can_drive_a_rule
      return if visibility_field.blank? || filter_type.present?

      errors.add(:base, I18n.t("easy_form_designer.error.visibility_field_unsupported"))
    end

    # The check EasyAutomations::Condition#validate_operator makes, against
    # the same table: an operator is legal here exactly when it is legal for
    # this field's type in any other Easy8 filter.
    def visibility_operator_allowed_for_field
      return if visibility_field.blank? || visibility_operator.blank?
      return if available_operators.include?(visibility_operator)

      errors.add(:visibility_operator, :invalid)
    end

    # Operator-specific value shapes, mirroring what sql_for_field reads:
    # "between" needs two values, and the relative-date operators need a day
    # count rather than something to compare against.
    def visibility_value_shape
      return if visibility_field.blank? || visibility_operator.blank? || value_optional?

      values = parsed_value

      if RANGE_OPERATORS.include?(visibility_operator) && Array(values).compact_blank.size != 2
        errors.add(:base, I18n.t("easy_form_designer.error.range_needs_two_values"))
      end

      return unless DAY_COUNT_OPERATORS.include?(visibility_operator)
      return if Array(values).first.to_s.match?(/\A-?\d+\z/)

      errors.add(:base, I18n.t("easy_form_designer.error.operator_needs_day_count"))
    end

    # No chained conditionals in v1: a rule whose own input might not have
    # been asked is a materially harder problem (what does "equals" mean when
    # the field was never shown?), and the PRD doesn't ask for it. Refuse it
    # outright rather than half-supporting it.
    #
    # REQ-16 made a field's section mandatory, so `referenced_section` is
    # never actually blank for a persisted field — the guard stays only as a
    # defensive no-op against an in-memory FormField that hasn't been
    # assigned one yet.
    def visibility_field_not_itself_conditional
      return if visibility_field.blank?

      referenced_section = visibility_field.section
      return if referenced_section.blank? || !referenced_section.rule?

      errors.add(:base, I18n.t("easy_form_designer.error.chained_visibility_rule"))
    end

    # The same question M8's preset validation already answers — "what values
    # can this field legally hold?" — reusing the same source of truth rather
    # than a second implementation that could drift from it.
    #
    # Only for the operators where membership is the point: a "contains" or
    # "starts with" rule takes free text even on a list field, and a
    # free-text or number field has no fixed option list at all.
    def visibility_value_legal_for_field
      return if visibility_field.blank? || visibility_value.blank?
      return unless MEMBERSHIP_OPERATORS.include?(visibility_operator)

      legal = visibility_field.preset_options.map { |(_label, value)| value.to_s }
      return if legal.empty?

      submitted = Array(parsed_value).map(&:to_s)
      return if submitted.any? && (submitted - legal).empty?

      errors.add(:visibility_value, :invalid)
    end

    # EasyAutomations::Condition does exactly this, for the same reason: an
    # operator like "is set" or "today" carries its own meaning, so a value
    # left behind from a previous choice would be misleading dead data.
    def clear_value_for_hidden_value_operators
      self.visibility_value = nil if value_optional?
    end

    # @return [Boolean]
    def value_optional?
      EasyQuery.hidden_values_by_operator.include?(visibility_operator)
    end

  end
end
