module EasyFormDesigner
  # Resolves which task attributes a form field may map to, for one
  # project + tracker pair.
  #
  # The custom-field half is the intersection of three sets — the same rule core
  # applies in EasyIssueTemplate#available_custom_fields. Trusting either the
  # project list or the tracker list alone is wrong: a field assigned to the
  # project but not enabled on the tracker will never appear on the issue, and
  # vice versa.
  class AvailableAttributes
    # Formats that cannot be driven from a form field. Mirrors
    # EasyIssueTemplate::UNSUPPORTED_CF_FORMATS, minus "user": a user lookup is
    # an explicit PRD M2 requirement, so it is excluded here only because the
    # first slice has no user widget yet — revisit when M2 widens.
    UNSUPPORTED_CF_FORMATS = %w[easy_computed_token autoincrement user version].freeze

    # Which widget may drive which native attribute.
    NATIVE_BY_WIDGET = {
      "text" => %w[subject],
      "long_text" => %w[description],
      "select" => %w[priority_id assigned_to_id],
      "date" => %w[due_date start_date],
    }.freeze

    # Which widget may drive which custom-field format.
    CF_FORMATS_BY_WIDGET = {
      "text" => %w[string link int float],
      "long_text" => %w[text],
      "select" => %w[list enumeration bool],
      "date" => %w[date],
    }.freeze

    attr_reader :project, :tracker

    # @param project [Project, nil]
    # @param tracker [Tracker, nil]
    def initialize(project, tracker)
      @project = project
      @tracker = tracker
    end

    # Custom fields usable for this project + tracker pair.
    #
    # @return [Array<IssueCustomField>]
    def custom_fields
      @custom_fields ||= begin
        results = IssueCustomField.where.not(field_format: UNSUPPORTED_CF_FORMATS).sorted.to_a
        results &= project.all_issue_custom_fields if project
        results &= tracker.custom_fields.to_a if tracker
        results
      end
    end

    # Native issue attributes usable on this pair.
    #
    # @return [Array<String>]
    def native_attributes
      EasyFormDesigner::FormField::NATIVE_ATTRIBUTES
    end

    # Everything a field of the given widget may map to.
    #
    # @param widget [String]
    # @return [Hash{Symbol => Array}]
    def for_widget(widget)
      {
        native: NATIVE_BY_WIDGET.fetch(widget, []),
        custom_fields: custom_fields.select { |cf| compatible_format?(widget, cf) },
      }
    end

    # Shape consumed by the builder's "Maps to" dropdown.
    #
    # @param widget [String]
    # @return [Array<Hash>]
    def options_for_widget(widget)
      set = for_widget(widget)

      natives = set[:native].map do |name|
        { type: "native", value: name, label: native_label(name) }
      end

      customs = set[:custom_fields].map do |cf|
        { type: "custom_field", value: cf.id, label: "#{cf.name} (cf_#{cf.id})" }
      end

      natives + customs
    end

    # @return [Boolean]
    def any?
      custom_fields.any? || native_attributes.any?
    end

    private

    # @return [Boolean]
    def compatible_format?(widget, custom_field)
      CF_FORMATS_BY_WIDGET.fetch(widget, []).include?(custom_field.field_format)
    end

    # @return [String]
    def native_label(name)
      case name
      when "subject" then l(:field_subject)
      when "description" then l(:field_description)
      when "priority_id" then l(:field_priority)
      when "assigned_to_id" then l(:field_assigned_to)
      when "due_date" then l(:field_due_date)
      when "start_date" then l(:field_start_date)
      else name.humanize
      end
    end

    def l(key)
      ::I18n.t(key)
    end

  end
end
