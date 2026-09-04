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
    # an explicit PRD M2 requirement, now built — see the "user" widget below.
    UNSUPPORTED_CF_FORMATS = %w[easy_computed_token autoincrement version].freeze

    # Which widget may drive which native attribute. Assignee is offered only
    # under "user" (a searchable lookup), not "select" (a plain dropdown of
    # every assignable user) — the whole point of adding the richer widget.
    #
    # status_id/category_id (PRD M8's D1) are offered here rather than kept
    # preset-only: an author may equally want a visible Status/Category
    # dropdown, not just a hidden stamp.
    NATIVE_BY_WIDGET = {
      "text" => %w[subject],
      "long_text" => %w[description],
      "select" => %w[priority_id status_id category_id],
      "date" => %w[due_date start_date],
      "number" => %w[estimated_hours],
      "radio" => %w[priority_id status_id category_id],
      "user" => %w[assigned_to_id],
      # PRD M13. A file field has exactly one possible target and no
      # custom-field alternative — Redmine's attachment-format custom field
      # reparents the file onto a custom VALUE, which isn't what "a
      # screenshot on the ticket" means to anyone reading the task.
      "file" => [EasyFormDesigner::FormField::ATTACHMENTS_ATTRIBUTE],
    }.freeze

    # Which widget may drive which custom-field format. "multi_select" and
    # "checkbox" have no native counterpart today (no native attribute is
    # multi-valued or boolean), so they're custom-field only — the absent key
    # in NATIVE_BY_WIDGET above already yields that via #fetch(widget, []).
    CF_FORMATS_BY_WIDGET = {
      "text" => %w[string link int float],
      "long_text" => %w[text],
      "select" => %w[list enumeration bool],
      "date" => %w[date],
      "number" => %w[int float],
      "radio" => %w[list enumeration bool],
      "multi_select" => %w[list enumeration user],
      "checkbox" => %w[bool],
      "user" => %w[user],
    }.freeze

    # Widgets whose underlying custom field must have multiple: true. Every
    # other widget requires multiple: false — a single-value widget can't
    # offer more than one selection, and a multi-value field mapped there
    # would silently lose all but one submitted value.
    MULTI_WIDGETS = %w[multi_select].freeze

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
      return false unless CF_FORMATS_BY_WIDGET.fetch(widget, []).include?(custom_field.field_format)

      MULTI_WIDGETS.include?(widget) == custom_field.multiple?
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
      when "estimated_hours" then l(:field_estimated_hours)
      when "status_id" then l(:field_status)
      when "category_id" then l(:field_category)
      when EasyFormDesigner::FormField::ATTACHMENTS_ATTRIBUTE then l(:label_attachment_plural)
      else name.humanize
      end
    end

    def l(key)
      ::I18n.t(key)
    end

  end
end
