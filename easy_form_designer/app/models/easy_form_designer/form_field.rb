module EasyFormDesigner
  # One question on a form.
  #
  # Every field must resolve to a real Easy8 task attribute — either a native
  # issue attribute or an IssueCustomField valid for the parent form's
  # project + tracker pair. There is deliberately no "form-only" field type:
  # choice options are derived from the mapped attribute rather than authored
  # here, so an unmapped field has nothing to render.
  class FormField < EasyFormDesigner::ApplicationRecord
    # Widget types supported so far. PRD M2's full set, plus "file" (PRD M13).
    WIDGETS = %w[text long_text select date number radio multi_select checkbox user file].freeze

    # PRD M13. A file field is the one widget whose answer isn't a value at
    # all — it's one or more uploaded files that become real Attachments on
    # the created task. It maps to the "attachments" pseudo-attribute below
    # and is handled by its own path in IssueBuilder, never through the
    # native-attribute or custom-value hashes.
    FILE_WIDGETS = %w[file].freeze

    # Widgets whose choices are label/value pairs resolved from the mapped
    # attribute (a custom field's possible_values, or a hardcoded native
    # list) — see #options.
    CHOICE_WIDGETS = %w[select radio multi_select].freeze

    # Native issue attributes a field may map to. status_id/category_id (PRD
    # M8's D1) are overwhelmingly used as HIDDEN presets — "silently stamp
    # status/category" is the PRD's own example — but are not restricted to
    # that: an author may equally offer either as a visible dropdown.
    #
    # "attachments" (PRD M13) is a pseudo-attribute, not a real Issue setter:
    # uploads reach the task through acts_as_attachable's save_attachments,
    # never through `issue.attachments=` (which would replace the collection
    # rather than append to it). Listing it here keeps a file field inside
    # the existing "every field maps to something real" model — see
    # ATTACHMENTS_ATTRIBUTE and IssueBuilder#attach_files.
    NATIVE_ATTRIBUTES = %w[subject description priority_id assigned_to_id due_date start_date
                           estimated_hours status_id category_id attachments].freeze

    # The pseudo-attribute a "file" widget maps to. Named once here because
    # three separate places have to agree on it: the duplicate-mapping
    # exception below, AvailableAttributes' widget table, and IssueBuilder's
    # carve-out from the generic native-attribute assignment loop.
    ATTACHMENTS_ATTRIBUTE = "attachments".freeze

    # PRD M11 — the EasyQuery filter type each native attribute has, so a
    # section's visibility rule offers exactly the operators that attribute
    # offers in any other Easy8 filter.
    #
    # These are not chosen here: each one mirrors what EasyIssueQuery itself
    # declares in its own `add_available_filter` call, so the two can't drift
    # into disagreeing about what (say) a due date is. "attachments" is
    # absent deliberately — a file field's answer is uploads, and there is no
    # filter type for that.
    NATIVE_FILTER_TYPES = {
      "subject" => :text,
      "description" => :text,
      "priority_id" => :list,
      "status_id" => :list_status,
      "category_id" => :list_optional,
      "assigned_to_id" => :list_autocomplete,
      "due_date" => :date_period,
      "start_date" => :date_period,
      "estimated_hours" => :float,
    }.freeze

    # PRD M7 — format rules a field author may attach to a field, on top of the
    # `required` flag. Deliberately a short closed list: each entry needs both a
    # matching check in SubmissionValidator and a matching input type on the
    # requester form, so this is not a place to accept arbitrary regexes.
    VALIDATION_FORMATS = %w[email url].freeze

    # Email and URL are single-line string semantics, so the rule is offered on
    # the "text" widget only — a multi-line Long text, or a Dropdown whose
    # choices come from the mapped attribute, cannot meaningfully carry one.
    VALIDATION_FORMAT_WIDGETS = %w[text].freeze

    # Likewise a numeric range only means anything on the number widget.
    RANGE_WIDGETS = %w[number].freeze

    # A date bound only means anything on the date widget. There is no
    # "datetime" widget to extend this to — Redmine has no custom-field format
    # for one, so M2 dropped it entirely (see AvailableAttributes).
    DATE_RANGE_WIDGETS = %w[date].freeze

    # PRD M8 — a preset "day offset from today" only means anything on the
    # date widget, mirroring DATE_RANGE_WIDGETS above.
    PRESET_OFFSET_WIDGETS = %w[date].freeze

    # The HTML input type each format rule renders as on the requester form, so
    # the browser checks before a round trip. Kept next to VALIDATION_FORMATS
    # rather than in the view: adding a rule without deciding how it renders is
    # exactly the kind of half-wiring that produces a rule enforced on one side
    # only. A missing key yields nil, which ds_text_field treats as "no type".
    HTML_INPUT_TYPES = { "email" => :email, "url" => :url }.freeze

    belongs_to :form,
               class_name: "EasyFormDesigner::Form",
               inverse_of: :fields

    belongs_to :custom_field,
               class_name: "IssueCustomField",
               optional: true

    # PRD M11 / REQ-16. Every field belongs to a section — Form guarantees a
    # new form gets a default one (#ensure_default_section) and the builder
    # never offers a way to add a field with none selected.
    belongs_to :section,
               class_name: "EasyFormDesigner::FormSection",
               inverse_of: :fields,
               optional: false

    safe_attributes(*%w[label help_text token widget required position mapped_attribute custom_field_id
                        validation_format min_value max_value
                        min_date max_date min_date_offset_days max_date_offset_days
                        hidden preset_value preset_offset_days section_id])

    validates :label, :token, :widget, presence: true
    validates :widget, inclusion: { in: WIDGETS }
    validates :token, uniqueness: { scope: :form_id }
    validates :mapped_attribute,
              inclusion: { in: NATIVE_ATTRIBUTES },
              allow_blank: true

    validates :validation_format,
              inclusion: { in: VALIDATION_FORMATS },
              allow_blank: true

    validate :exactly_one_mapping
    validate :section_belongs_to_form
    validate :custom_field_available_for_form
    validate :attribute_not_already_mapped_by_another_field
    validate :validation_format_matches_widget
    validate :range_matches_widget
    validate :range_bounds_ordered
    validate :date_bounds_matches_widget
    validate :date_bounds_not_double_specified
    validate :date_bounds_ordered
    validate :preset_not_double_specified
    validate :preset_offset_matches_widget
    validate :hidden_requires_preset
    validate :preset_value_valid_for_mapping
    validate :file_widget_cannot_be_hidden

    before_validation :default_token
    before_validation :clear_required_when_hidden
    before_destroy :clear_dependent_section_rules

    scope :sorted, -> { order(:position) }

    delegate :to_s, to: :label

    # Renders a numeric bound the way the author typed it.
    #
    # BigDecimal#to_s is not usable here: it produces scientific notation, so
    # the 40 someone entered comes back as "0.4e2" — which is what both the
    # builder's Maximum input and the requester's error message would have
    # shown. to_s("F") fixes that but still yields "40.0", so a whole number is
    # narrowed to an integer first.
    #
    # @param bound [BigDecimal, nil]
    # @return [String, nil]
    def self.format_bound(bound)
      return nil if bound.blank?

      bound.frac.zero? ? bound.to_i.to_s : bound.to_s("F")
    end

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

    # PRD M13. This field's answer is uploaded files, not a value — so it
    # takes IssueBuilder's dedicated attachment path and is excluded from the
    # generic native-attribute assignment loop, even though it is `native?`.
    #
    # @return [Boolean]
    def file?
      FILE_WIDGETS.include?(widget)
    end

    # PRD M11. The EasyQuery filter type this field's answer behaves as —
    # which is what decides the operators a visibility rule may use on it
    # (EasyQuery.operators_by_filter_type). A custom field is asked directly
    # rather than mapped by format here, so a format this engine has never
    # heard of still answers correctly.
    #
    # nil means the field cannot drive a rule: a file field's answer is
    # uploaded files, and an unmapped field has no attribute to speak for.
    #
    # @return [Symbol, nil]
    def filter_type
      return nil if file?

      if custom?
        # The query argument is only used by formats that scope their VALUES
        # by project; nil is safe because only the :type key is read here.
        custom_field.query_filter_options(nil)[:type]
      else
        NATIVE_FILTER_TYPES[mapped_attribute]
      end
    end

    # A format rule (email/URL) is attached to this field.
    #
    # @return [Boolean]
    def validation_format?
      validation_format.present?
    end

    # At least one numeric bound is set. Either bound alone is a legitimate
    # rule — "at least 1" and "at most 40" are both useful without the other.
    #
    # @return [Boolean]
    def range?
      min_value.present? || max_value.present?
    end

    # At least one date bound — fixed or relative — is set.
    #
    # @return [Boolean]
    def date_range?
      min_date.present? || max_date.present? || min_date_offset_days.present? || max_date_offset_days.present?
    end

    # The earliest date this field accepts, resolved against `today` — which
    # is deliberately a parameter, not a hardcoded Date.current, so a spec can
    # assert a fixed offset's behaviour without freezing the system clock.
    #
    # @param today [Date]
    # @return [Date, nil]
    def effective_min_date(today: Date.current)
      min_date || (today + min_date_offset_days if min_date_offset_days)
    end

    # @param today [Date]
    # @return [Date, nil]
    def effective_max_date(today: Date.current)
      max_date || (today + max_date_offset_days if max_date_offset_days)
    end

    # A preset — fixed value or day offset — is configured. Unconditional on
    # `hidden?`: a VISIBLE field may also carry a default the requester sees
    # pre-filled and may change (PRD M8's other half).
    #
    # @return [Boolean]
    def preset?
      preset_value.present? || preset_offset_days.present?
    end

    # Resolves this field's preset to the value AnswerResolver actually writes
    # onto a hidden field's answer (or seeds a visible field's answer with, on
    # first render). `today` is deliberately a parameter, for the same reason
    # effective_min_date/effective_max_date take one — a spec can assert an
    # offset's behaviour without freezing the system clock.
    #
    # @param today [Date]
    # @return [String, Array<String>, nil]
    def effective_preset_value(today: Date.current)
      return (today + preset_offset_days).to_s if preset_offset_days.present?
      return preset_value_list if widget == "multi_select"

      preset_value
    end

    # Choices for the builder's preset picker. A superset of #options: it also
    # covers "user" (whose choices come from whatever the field is mapped to,
    # same as a choice widget, but "user" is not itself a CHOICE_WIDGET) and
    # "checkbox" (whose two states are never authored anywhere — hardcoded
    # here the same way core hardcodes Yes/No for a bool custom field).
    #
    # @return [Array<Array(String, String)>] label/value pairs, or [] for a
    #   widget with no fixed set of choices (its preset is typed, not picked)
    def preset_options
      case widget
      when *CHOICE_WIDGETS
        options
      when "checkbox"
        [[::I18n.t(:general_text_yes_capitalize), "1"], [::I18n.t(:general_text_no_capitalize), "0"]]
      when "user"
        user_preset_options
      else
        []
      end
    end

    # A multi_select preset is a newline-separated list in the same text
    # column every other preset uses — the idiom core itself uses for
    # CustomField#possible_values= (splits on /[\n\r]+/) rather than JSON in a
    # flat column. Every other widget's preset is the single scalar value.
    # Public: both #effective_preset_value and the builder's form_json read
    # this same list, and a multi_select preset needs to travel to the Vue
    # builder as an array, not the raw newline-joined string.
    #
    # @return [Array<String>]
    def preset_value_list
      return [] if preset_value.blank?

      widget == "multi_select" ? preset_value.split(/[\n\r]+/).map(&:strip).reject(&:blank?) : [preset_value]
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
      when "status_id"
        form.tracker.issue_statuses.map { |s| [s.name, s.id.to_s] }
      when "category_id"
        form.project.issue_categories.map { |c| [c.name, c.id.to_s] }
      else
        []
      end
    end

    # @return [Array<Array(String, String)>] label/value pairs
    def user_preset_options
      records =
        if custom?
          custom_field.possible_values_options(form)
        else
          form.project.assignable_users.map { |u| [u.name, u.id.to_s] }
        end

      # Filters out core's own "<< me >>" sentinel (UserFormat#possible_values_options,
      # field_format.rb) — it would resolve to the FORM AUTHOR here, not the
      # requester, because a preset is chosen once at design time and reused
      # for every future submission. An author picking "Me" as a preset would
      # silently stamp every task with themselves as assignee regardless of
      # who actually submits — the opposite of what "Me" means when picking a
      # value for yourself in a filter.
      records.reject { |label, _value| label.to_s.start_with?("<<") }
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

    # Required is meaningless on a field the requester never sees — its
    # answer always comes from AnswerResolver's preset, never from input the
    # requester could fail to provide. Forced rather than merely disallowed,
    # so flipping "Hidden" on in the builder doesn't leave a stale, silently
    # ineffective Required switch behind.
    def clear_required_when_hidden
      self.required = false if hidden?
    end

    # PRD M11. A section rule pointing at a field that no longer exists can't
    # be evaluated. All THREE columns have to go, not just the id: clearing
    # the reference alone would leave the operator and value behind, and the
    # section would then fail its own all-or-nothing rule validation the next
    # time anyone saved it — a form that can't be saved because of a field
    # somebody deleted a week ago.
    #
    # The section becoming unconditionally visible is the deliberate choice
    # here: showing fields that were meant to be conditional is recoverable
    # and obvious to the author, whereas silently hiding them is neither.
    def clear_dependent_section_rules
      EasyFormDesigner::FormSection
        .where(visibility_field_id: id)
        .update_all(visibility_field_id: nil, visibility_operator: nil, visibility_value: nil)
    end

    def exactly_one_mapping
      return if mapped_attribute.present? ^ custom_field_id.present?

      errors.add(:base, I18n.t("easy_form_designer.error.unmapped_field"))
    end

    # Mirrors Form's own tracker_enabled_for_project check, applied here so a
    # request that crafts a section_id belonging to a different form can't
    # get past it — accepts_nested_attributes_for's own scoping already
    # prevents this through the normal builder save path, but this makes it
    # non-bypassable for anything posting straight at the controller.
    def section_belongs_to_form
      return if section.blank? || form.blank?
      return if section.form_id == form_id

      errors.add(:section_id, :invalid)
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
      # "attachments" joins subject/description as an exception, for a
      # different reason: several file fields on one form each ADD to the same
      # attachment collection (see IssueBuilder#attach_files), so two of them
      # is a legitimate design, not the silent-overwrite hazard this check
      # exists to catch.
      return if mapped_attribute.in?(%W[subject description #{ATTACHMENTS_ATTRIBUTE}])

      siblings = form.fields.reject { |f| f == self }

      conflict =
        if custom_field_id.present?
          siblings.any? { |f| f.custom_field_id == custom_field_id }
        elsif mapped_attribute.present?
          siblings.any? { |f| f.mapped_attribute == mapped_attribute }
        end

      errors.add(:base, I18n.t("easy_form_designer.error.duplicate_mapping")) if conflict
    end

    # The same shape of guard AvailableAttributes applies to widget/attribute
    # compatibility, applied here to widget/rule compatibility. The builder only
    # offers a rule on a widget that supports it; this makes that non-bypassable
    # for anything posting straight at the controller.
    def validation_format_matches_widget
      return if validation_format.blank?
      return if VALIDATION_FORMAT_WIDGETS.include?(widget)

      errors.add(:validation_format, :invalid)
    end

    def range_matches_widget
      return unless range?
      return if RANGE_WIDGETS.include?(widget)

      errors.add(:base, I18n.t("easy_form_designer.error.range_not_supported"))
    end

    # An inverted range can never be satisfied, so it would reject every
    # submission with a message the requester has no way to act on. Caught at
    # authoring time instead, where the person who can actually fix it is
    # looking.
    def range_bounds_ordered
      return if min_value.blank? || max_value.blank?
      return if min_value <= max_value

      errors.add(:base, I18n.t("easy_form_designer.error.invalid_range"))
    end

    def date_bounds_matches_widget
      return unless date_range?
      return if DATE_RANGE_WIDGETS.include?(widget)

      errors.add(:base, I18n.t("easy_form_designer.error.date_range_not_supported"))
    end

    # A fixed date and a day offset are two different ways to express the same
    # side of the range — never both at once, or effective_min_date/
    # effective_max_date would have to silently pick a winner.
    def date_bounds_not_double_specified
      if min_date.present? && min_date_offset_days.present?
        errors.add(:base, I18n.t("easy_form_designer.error.date_bound_conflict"))
      end
      return unless max_date.present? && max_date_offset_days.present?

      errors.add(:base, I18n.t("easy_form_designer.error.date_bound_conflict"))
    end

    # Only the two directly comparable shapes are checked here: two fixed
    # dates, or two offsets (an offset's order relative to another offset
    # never changes, whatever "today" turns out to be). A fixed date mixed
    # with an offset is deliberately NOT checked at authoring time — whether
    # min_date: 2026-09-01 conflicts with max_date_offset_days: 5 depends on
    # what day the rule is actually evaluated on, so today's verdict could be
    # wrong tomorrow. An admin who builds an unsatisfiable mixed rule anyway
    # will see it as every submission getting rejected, which is a visible,
    # investigable symptom rather than a silently wrong authoring-time check.
    def date_bounds_ordered
      if min_date.present? && max_date.present? && min_date > max_date
        errors.add(:base, I18n.t("easy_form_designer.error.invalid_date_range"))
      end
      return unless min_date_offset_days.present? && max_date_offset_days.present?
      return if min_date_offset_days <= max_date_offset_days

      errors.add(:base, I18n.t("easy_form_designer.error.invalid_date_range"))
    end

    # A fixed preset and a day offset are two different ways to express the
    # same thing — never both at once, mirroring date_bounds_not_double_specified,
    # or effective_preset_value would have to silently pick a winner.
    def preset_not_double_specified
      return unless preset_value.present? && preset_offset_days.present?

      errors.add(:base, I18n.t("easy_form_designer.error.preset_conflict"))
    end

    def preset_offset_matches_widget
      return if preset_offset_days.blank?
      return if PRESET_OFFSET_WIDGETS.include?(widget)

      errors.add(:base, I18n.t("easy_form_designer.error.preset_offset_not_supported"))
    end

    # PRD M8 (D3): a hidden field's value comes ONLY from its preset — there
    # is no requester input to fall back on, so a hidden field with no preset
    # would render nothing and write nothing. Enforced unconditionally here,
    # the same way exactly_one_mapping is unconditional rather than only
    # checked at publish time.
    def hidden_requires_preset
      return unless hidden?
      # A hidden FILE field is rejected by file_widget_cannot_be_hidden with a
      # message that actually explains itself; adding "needs a preset value"
      # on top would just send the author hunting for a setting that can't
      # exist for this widget.
      return if file?
      return if preset?

      errors.add(:base, I18n.t("easy_form_designer.error.preset_required_when_hidden"))
    end

    # Checked against whatever the field is mapped to, at design time — an
    # illegal preset would otherwise fail at every future submission instead
    # of once, here, in front of the person who can actually fix it. Skipped
    # entirely while unmapped: #options/#preset_options both read the mapping
    # to know what's legal, and exactly_one_mapping already reports the
    # missing mapping on its own.
    def preset_value_valid_for_mapping
      return unless mapped?
      return if preset_value.blank?
      # A fixed value alongside an offset is already reported by
      # preset_not_double_specified — don't also validate it as a fixed value
      # for a widget (date) where it was never meant to be one.
      return if preset_offset_days.present?

      case widget
      when *CHOICE_WIDGETS
        validate_choice_preset
      when "checkbox"
        errors.add(:preset_value, :invalid) unless preset_value.in?(%w[0 1])
      when "number"
        errors.add(:preset_value, :not_a_number) unless numeric_string?(preset_value)
      when "date"
        errors.add(:preset_value, :invalid) if Date.safe_parse(preset_value).nil?
      when "user"
        validate_user_preset
      end
    end

    # PRD M13. There is no such thing as a preset file, so a file field can
    # never be hidden. hidden_requires_preset would already reject it — but
    # with "needs a preset value", which sends the author looking for a
    # setting that cannot exist. Say the true thing instead.
    def file_widget_cannot_be_hidden
      return unless file? && hidden?

      errors.add(:base, I18n.t("easy_form_designer.error.file_cannot_be_hidden"))
    end

    def validate_choice_preset
      legal = preset_options.map { |(_label, value)| value.to_s }
      invalid = preset_value_list.reject { |v| legal.include?(v.to_s) }

      errors.add(:preset_value, :invalid) if invalid.any?
    end

    def validate_user_preset
      errors.add(:preset_value, :invalid) unless Principal.exists?(id: preset_value)
    end

    # @return [Boolean]
    def numeric_string?(value)
      Float(value)
      true
    rescue ArgumentError, TypeError
      false
    end

  end
end
