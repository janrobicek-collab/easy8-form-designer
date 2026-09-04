# Feeds the builder's "Maps to" dropdown.
#
# Returns only attributes that are legal for the given project + tracker + widget
# combination, so the UI cannot offer a mapping the model would later reject.
class EasyFormDesignerAttributesController < ApplicationController
  before_action :require_login
  before_action :authorize_global

  def index
    project = Project.find_by(id: params[:project_id])
    tracker = Tracker.find_by(id: params[:tracker_id])

    return render json: { options: [] } if project.nil? || tracker.nil?

    resolver = EasyFormDesigner::AvailableAttributes.new(project, tracker)

    render json: { options: resolver.options_for_widget(params[:widget].to_s) }
  end

end
