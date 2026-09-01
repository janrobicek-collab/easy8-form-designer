# Admin-facing form library and builder.
class EasyFormDesignerFormsController < ApplicationController
  before_action :require_login
  before_action :authorize_global
  before_action :find_form, only: %i[show edit update destroy publish unpublish preset_options]

  helper :custom_fields
  helper_method :form_json

  def index
    @forms = EasyFormDesigner::Form.visible(User.current).sorted.includes(:project, :tracker)
  end

  def show
    render :edit
  end

  # Step 1 — the gateway. The builder cannot load until a project and tracker
  # are chosen, because those two scope every later mapping decision.
  def new
    @form = EasyFormDesigner::Form.new(author: User.current)
  end

  # Step 2/3 — field layout and template authoring. Rendered as a mount point
  # for the Vue builder; the ERB is only the shell.
  def edit; end
  def create
    @form = EasyFormDesigner::Form.new(author: User.current)
    @form.safe_attributes = form_params

    if @form.save
      redirect_to edit_easy_form_designer_form_path(@form)
    else
      render :new, status: :unprocessable_content
    end
  end

  # The builder saves over JSON (fetch), never a classic HTML form post.
  # Responding with JSON directly here — instead of the usual redirect — is
  # not just a style choice: fetch() follows a same-origin redirect
  # automatically and, per the Fetch spec, preserves the original method for
  # anything other than POST. A PATCH here redirected to the `edit` GET-only
  # route would have the browser silently re-issue the PATCH against it and
  # 404 — reporting a spurious failure for a save that had already succeeded.
  def update
    @form.safe_attributes = section_params_resolved(form_params)
    saved = @form.save
    @form.reload if saved

    respond_to do |format|
      if saved
        format.html do
          flash[:notice] = l(:notice_successful_update)
          redirect_to edit_easy_form_designer_form_path(@form)
        end
        format.json { render json: form_json(@form) }
      else
        format.html { render :edit, status: :unprocessable_content }
        format.json { render json: { errors: @form.errors.full_messages }, status: :unprocessable_content }
      end
    end
  end

  def destroy
    @form.destroy
    redirect_to easy_form_designer_forms_path
  end

  def publish
    if @form.publishable? && @form.publish
      flash[:notice] = l(:notice_successful_update)
    else
      flash[:error] = @form.errors.full_messages.presence&.join(", ") ||
                      l("easy_form_designer.error.unmapped_field")
    end

    redirect_to edit_easy_form_designer_form_path(@form)
  end

  def unpublish
    @form.unpublish
    redirect_to edit_easy_form_designer_form_path(@form)
  end

  # Feeds the builder's preset-value picker (PRD M8). Scoped per-FORM, not
  # per project/tracker pair the way EasyFormDesignerAttributesController is:
  # a preset's legal choices depend on the CHOSEN MAPPING, and
  # possible_values_options needs a real Form as its scoping object — the
  # same object FormField#options already passes it. Kept as a separate
  # endpoint from /form-designer/attributes rather than folded in: presets
  # depend on the mapping the author already picked, so combining them would
  # mean computing assignable_users and every candidate custom field's
  # possible_values for every mapping option on every widget change, not just
  # the one actually selected.
  #
  # A transient, unsaved FormField reuses every bit of format normalisation
  # #preset_options already does (including the enumeration/bool
  # possible_values_options fix), rather than a second implementation of the
  # same logic living here.
  def preset_options
    field = EasyFormDesigner::FormField.new(
      form: @form,
      widget: params[:widget].to_s,
      mapped_attribute: params[:mapped_attribute].presence,
      custom_field_id: params[:custom_field_id].presence
    )

    # preset_options returns [label, value] pairs (the same shape #options
    # uses); rendered as objects here to match every other JSON option list
    # this engine serves (see MappingOption / options_for_widget).
    #
    # `operators` and `filter_type` ride along for PRD M11's rule editor:
    # both answer "what can this field hold, and how may it be compared?"
    # about the same field, so asking twice would be two round trips for one
    # question. The operator list is EasyQuery's own, so a date field offers
    # periods and a list field offers is/is not — exactly what the same field
    # offers in any other Easy8 filter.
    render json: {
      options: field.preset_options.map { |(label, value)| { label: label, value: value } },
      filter_type: field.filter_type,
      operators: operator_options(field.filter_type),
    }
  end

  private

  def find_form
    @form = EasyFormDesigner::Form.find(params[:id])
    render_403 unless @form.visible?(User.current)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def form_params
    params.require(:easy_form_designer_form).permit!
  rescue ActionController::ParameterMissing
    {}
  end

  # PRD M11. Every operator a field's filter type allows, labelled from
  # EasyQuery's own operator table — the same pairs EasyQuery#operators_for_select
  # builds for a filter's operator dropdown, so the wording matches the rest
  # of the product in both languages without this engine translating anything.
  #
  # `needs_value` mirrors EasyQuery.hidden_values_by_operator so the client
  # knows to hide the value control rather than re-deriving that list.
  #
  # @param filter_type [Symbol, nil]
  # @return [Array<Hash>]
  def operator_options(filter_type)
    Array(EasyQuery.operators_by_filter_type[filter_type]).filter_map do |operator|
      label = EasyQuery.operators[operator]

      # An operator EasyQuery has no label for is not a plain dropdown
      # choice: date_period_1/date_period_2 are the two MODES of Easy8's
      # composite date-period widget (DatePeriod / DatePeriodTo in
      # dynamic_filters/enums/query.ts), which is why they carry no label.
      # Listing them here would put the raw string "date_period_1" in front
      # of an author. RuleEvaluator still evaluates them, so a rule built
      # elsewhere keeps working; they reappear here with the period picker.
      next if label.blank?

      label, options = label if label.is_a?(Array) # e.g. "l2w" => [:label_last_n_weeks, {count: 2}]

      {
        value: operator,
        label: l(label, **(options || {})),
        needs_value: EasyQuery.hidden_values_by_operator.exclude?(operator),
      }
    end
  end

  # PRD M11. A section and a field assigned to it are created in the SAME
  # save, so the field can't carry a real section_id yet — the section has no
  # id until it's persisted. The builder therefore references a brand-new
  # section by a temporary key ("new-1"), and this resolves those to real ids
  # before the fields are assigned.
  #
  # Sections are saved first, in their own pass, precisely so their ids exist
  # by the time the fields need them. The alternative — nesting fields inside
  # sections_attributes — would let Rails set the FK automatically but breaks
  # the "move a field to another section" case, since nested attributes
  # reject a child id belonging to a different parent.
  #
  # @param attrs [Hash, ActionController::Parameters]
  # @return [Hash]
  def section_params_resolved(attrs)
    attrs = attrs.to_h.with_indifferent_access
    sections = attrs[:sections_attributes]
    return attrs if sections.blank?

    @form.safe_attributes = { "sections_attributes" => persistable_sections(sections) }
    return attrs unless @form.save

    attrs.except(:sections_attributes).tap do |remaining|
      remaining[:fields_attributes] = remap_section_ids(remaining[:fields_attributes], sections)
    end
  end

  # Strips the two things a temp-keyed section carries that ActiveRecord
  # can't take: `temp_key` (not a column at all) and a non-numeric `id`
  # (which nested attributes would try to look up and fail to find).
  #
  # @return [Array<Hash>]
  def persistable_sections(sections)
    each_attribute_entry(sections).map do |attrs|
      cleaned = attrs.except(:temp_key)
      cleaned = cleaned.except(:id) unless cleaned[:id].to_s.match?(/\A\d+\z/)
      cleaned
    end
  end

  # @return [Array, Hash, nil] whatever shape came in, with temp keys replaced
  def remap_section_ids(fields_attributes, sections)
    return fields_attributes if fields_attributes.blank?

    mapping = temp_key_to_section_id(sections)
    return fields_attributes if mapping.empty?

    each_attribute_entry(fields_attributes) do |field|
      key = field[:section_id]
      field[:section_id] = mapping[key.to_s] if key.present? && mapping.key?(key.to_s)
    end

    fields_attributes
  end

  # A temp key is matched back to its saved row by TOKEN — the builder sends
  # one explicitly for a new section, exactly as it already does for a new
  # field, so nothing here has to re-derive it and risk disagreeing with
  # FormSection#default_token about collision suffixes.
  #
  # @return [Hash{String => Integer}]
  def temp_key_to_section_id(sections)
    saved_by_token = @form.sections.reload.index_by(&:token)

    each_attribute_entry(sections).each_with_object({}) do |attrs, acc|
      temp_key = attrs[:temp_key].presence || attrs[:id].presence
      next if temp_key.blank? || temp_key.to_s.match?(/\A\d+\z/) # already a real id

      section = saved_by_token[attrs[:token].to_s]
      acc[temp_key.to_s] = section.id if section
    end
  end

  # fields_attributes/sections_attributes arrive as an Array from the JSON
  # builder, but Rails also accepts the index-keyed Hash form — handle both
  # rather than assuming the caller is always our own Vue app.
  #
  # @return [Array<Hash>]
  def each_attribute_entry(attributes, &block)
    entries = attributes.is_a?(Hash) ? attributes.values : Array(attributes)
    entries.each(&block) if block

    entries
  end

  # Shape consumed by the Vue builder — both to hydrate on initial page load
  # (embedded into edit.html.erb) and to re-sync local state after a save
  # (the JSON body of the update response), so the two never drift apart.
  #
  # @return [Hash]
  def form_json(form)
    {
      id: form.id,
      subject_template: form.subject_template,
      description_template: form.description_template,
      fields: form.fields.sorted.map do |field|
        {
          id: field.id,
          position: field.position,
          label: field.label,
          help_text: field.help_text,
          token: field.token,
          widget: field.widget,
          required: field.required,
          mapped_attribute: field.mapped_attribute,
          custom_field_id: field.custom_field_id,
          validation_format: field.validation_format,
          # Strings, not raw BigDecimals: the builder keeps bounds as strings so
          # a cleared input stays distinguishable from a real 0, and
          # .format_bound is what keeps 40 from arriving as "0.4e2" or "40.0".
          min_value: EasyFormDesigner::FormField.format_bound(field.min_value),
          max_value: EasyFormDesigner::FormField.format_bound(field.max_value),
          # Date columns serialise to plain ISO strings via Rails' own
          # Date#as_json — exactly the shape DSDatepicker's v-model expects, so
          # no formatting helper is needed here the way format_bound is for
          # BigDecimal.
          min_date: field.min_date,
          max_date: field.max_date,
          min_date_offset_days: field.min_date_offset_days,
          max_date_offset_days: field.max_date_offset_days,
          # PRD M8. preset_value is a plain string column for every widget
          # except multi_select, which needs to travel to the builder as an
          # array — the same newline-split #preset_value_list logic
          # effective_preset_value uses when actually resolving it.
          hidden: field.hidden,
          preset_value: field.widget == "multi_select" ? field.preset_value_list : field.preset_value,
          preset_offset_days: field.preset_offset_days,
          # PRD M11. Null means top-level / ungrouped.
          section_id: field.section_id,
        }
      end,
      sections: form.sections.sorted.map do |section|
        {
          id: section.id,
          position: section.position,
          name: section.name,
          token: section.token,
          visibility_field_id: section.visibility_field_id,
          visibility_operator: section.visibility_operator,
          # The column holds JSON; the builder works in arrays.
          visibility_values: section.visibility_values,
        }
      end,
    }
  end

end
