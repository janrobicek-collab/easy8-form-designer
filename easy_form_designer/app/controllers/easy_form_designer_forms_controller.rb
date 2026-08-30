# Admin-facing form library and builder.
class EasyFormDesignerFormsController < ApplicationController
  before_action :require_login
  before_action :authorize_global
  before_action :find_form, only: %i[show edit update destroy publish unpublish]

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
    @form.safe_attributes = form_params
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
        }
      end,
    }
  end

end
