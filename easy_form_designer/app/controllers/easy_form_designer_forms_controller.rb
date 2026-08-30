# Admin-facing form library and builder.
class EasyFormDesignerFormsController < ApplicationController
  before_action :require_login
  before_action :authorize_global
  before_action :find_form, only: %i[show edit update destroy publish unpublish]

  helper :custom_fields

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


  def update
    @form.safe_attributes = form_params

    if @form.save
      flash[:notice] = l(:notice_successful_update)
      redirect_to edit_easy_form_designer_form_path(@form)
    else
      render :edit, status: :unprocessable_content
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

end
