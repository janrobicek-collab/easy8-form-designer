module EasyFormDesigner
  # Validates one set of submitted answers against the form that produced them,
  # before IssueBuilder is allowed to touch an Issue.
  #
  # Returns errors keyed by FIELD TOKEN, which is the whole point of this class
  # existing. Everything here was previously either absent (PRD M7's format
  # rules) or enforced too late to attribute: custom-field constraints fired
  # inside issue.save and arrived as one joined sentence in a flash, leaving the
  # requester to guess which of a dozen inputs was actually wrong.
  #
  # Tiers run per field, and "required" stops the rest — reporting "is
  # invalid" on top of "cannot be blank" for the same empty input is noise,
  # not information. The remaining tiers all run and accumulate, since an
  # answer can fail more than one of them independently:
  #
  #   1. required        — moved here from the controller, widget-aware
  #   2. authored rule   — PRD M7: email, URL, numeric range, date range
  #   3. the mapped custom field's OWN rules, delegated to core
  #
  # Tier 3 is delegation on purpose. Redmine already knows how to validate a
  # custom value (regexp, min_length, max_length, not_a_number) and its checks
  # were already running on every submission — just unattributably. Reusing
  # CustomField#validate_field_value means an admin-configured constraint and an
  # M7 rule surface identically, and there is no second implementation of the
  # same rules to drift.
  class SubmissionValidator

    # PRD M7's URL rule requires an explicit scheme, which is deliberately
    # stricter than Redmine's own LinkFormat (that accepts a bare
    # "example.com" and prepends http:// when rendering). The reason is
    # client/server agreement: the requester form renders this rule as
    # <input type="url">, and the browser's own check demands a scheme. A
    # looser server regex would accept values the browser had already
    # rejected, so the two must match or the field behaves differently
    # depending on whether JS ran.
    URL_REGEXP = %r{\Ahttps?://\S+\z}i

    # Email uses core's own pattern rather than a hand-rolled one — this is the
    # exact regexp Easy8 validates every user's address with
    # (EmailAddress#address, app/models/email_address.rb). Already anchored.
    EMAIL_REGEXP = URI::MailTo::EMAIL_REGEXP

    attr_reader :form, :answers

    # @param form [EasyFormDesigner::Form]
    # @param answers [Hash] raw answers keyed by field token
    def initialize(form, answers)
      @form = form
      @answers = (answers || {}).stringify_keys
    end

    # @return [Boolean]
    def valid?
      errors.empty?
    end

    # @return [Hash{String => Array<String>}] field token => messages
    def errors
      @errors ||= answerable_fields.each_with_object({}) do |field, acc|
        messages = messages_for(field)
        acc[field.token] = messages if messages.any?
      end
    end

    private

    # Fields the requester could actually have answered. Two kinds are
    # excluded, for the same underlying reason — an error on a field nobody
    # was shown is a dead end, not something anyone can act on:
    #
    # * PRD M8 `hidden?` fields, whose value comes from a preset;
    # * PRD M11 fields in a section whose rule evaluates false for THESE
    #   answers (this runs before AnswerResolver and deliberately shares no
    #   state with it, so it asks the form directly).
    #
    # @return [Array<EasyFormDesigner::FormField>]
    def answerable_fields
      hidden_by_section = form.tokens_hidden_by_section(answers)

      form.fields.reject { |field| field.hidden? || hidden_by_section.include?(field.token) }
    end

    # @return [Array<String>]
    def messages_for(field)
      value = answers[field.token]

      return [blank_message] if missing?(field, value)

      # An optional field left empty is simply unanswered — it must not trip a
      # format rule. Note this also means a Redmine-required custom field
      # mapped to an OPTIONAL form field is not caught here; that combination
      # is unsatisfiable by design and surfaces from issue.save instead, where
      # the controller attributes it back to this field via its cf_<id> tag.
      return [] if blank?(value)

      format_messages(field, value) + range_messages(field, value) + date_range_messages(field, value) +
        custom_field_messages(field, value)
    end

    # A checkbox always submits something ("1" or "0" — see the hidden_field_tag
    # paired with it on the requester form), so it is never blank. "Required" on
    # a checkbox therefore has to mean "must be checked", the ordinary meaning
    # of a required consent box, rather than merely "answered".
    #
    # @return [Boolean]
    def missing?(field, value)
      return false unless field.required?
      return value != "1" if field.widget == "checkbox"

      blank?(value)
    end

    # Array(...) so a multi-value widget submitting [""] — an empty selection
    # rather than no selection — counts as unanswered. [""].blank? is false,
    # so a plain blank? check would let it through as a real answer.
    #
    # @return [Boolean]
    def blank?(value)
      Array(value).reject(&:blank?).empty?
    end

    # @return [Array<String>]
    def format_messages(field, value)
      case field.validation_format
      when "email"
        EMAIL_REGEXP.match?(value.to_s.strip) ? [] : [l("easy_form_designer.error.invalid_email")]
      when "url"
        URL_REGEXP.match?(value.to_s.strip) ? [] : [l("easy_form_designer.error.invalid_url")]
      else
        []
      end
    end

    # @return [Array<String>]
    def range_messages(field, value)
      return [] unless field.range?

      # "2,5" => 2.5, matching how core's own FloatFormat normalises a decimal
      # comma before validating. Without this, a Czech-locale requester typing
      # the separator their keyboard produces gets "is not a number".
      number = Kernel.Float(value.to_s.strip.tr(",", "."), exception: false)
      return [l("activerecord.errors.messages.not_a_number")] if number.nil?

      messages = []
      if field.min_value.present? && number < field.min_value
        messages << l("activerecord.errors.messages.greater_than_or_equal_to",
                      count: EasyFormDesigner::FormField.format_bound(field.min_value))
      end
      if field.max_value.present? && number > field.max_value
        messages << l("activerecord.errors.messages.less_than_or_equal_to",
                      count: EasyFormDesigner::FormField.format_bound(field.max_value))
      end

      messages
    end

    # A date bound — fixed or "N days from today" — evaluated against the day
    # of SUBMISSION, not the day the rule was authored. There is no
    # client-side hint for this one: unlike TextField/NumberField,
    # DesignSystem::Components::Datepicker has no min/max keyword at all, so
    # this tier is the only check that ever runs.
    #
    # @return [Array<String>]
    def date_range_messages(field, value)
      return [] unless field.date_range?

      date = parse_date(value)
      return [l("easy_form_designer.error.invalid_date")] if date.nil?

      min = field.effective_min_date
      max = field.effective_max_date
      return [] if (min.nil? || date >= min) && (max.nil? || date <= max)

      [date_range_message(min, max)]
    end

    # One message, phrased for whichever shape of rule is actually configured
    # — not "must not be after X" regardless of context. A field with only a
    # floor reads "must be after"; only a ceiling reads "must be before"; both
    # together read as a single "must be between" naming the whole window,
    # rather than reporting just the one bound that happened to be violated
    # and leaving the other implicit.
    #
    # @return [String]
    def date_range_message(min, max)
      if min && max
        l("easy_form_designer.error.date_out_of_range", min: min.iso8601, max: max.iso8601)
      elsif min
        l("easy_form_designer.error.date_too_early", date: min.iso8601)
      else
        l("easy_form_designer.error.date_too_late", date: max.iso8601)
      end
    end

    # @return [Date, nil]
    def parse_date(value)
      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    # Core's own validation for the mapped custom field. Returns messages that
    # are already localised, so they are passed through untouched.
    #
    # The raw answer goes in unchanged — exactly what IssueBuilder will later
    # assign — so this validates the same input that will actually be written,
    # not a normalised copy of it. For a multiple: true field that means an
    # Array, which is already the shape the multi_select param produces.
    #
    # @return [Array<String>]
    def custom_field_messages(field, value)
      return [] unless field.custom?

      field.custom_field.validate_field_value(value)
    end

    # @return [String]
    def blank_message
      l("activerecord.errors.messages.blank")
    end

    def l(key, **options)
      ::I18n.t(key, **options)
    end

  end
end
