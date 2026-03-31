class PropertiesController < ApplicationController
  before_action :set_note

  def update
    authorize @note, :update?

    changes = params.require(:changes).permit!.to_h
    revision = Properties::SetService.call(
      note: @note,
      changes: changes,
      author: current_user,
      strict: false
    )

    @note.reload
    render json: {
      properties: (revision.properties_data || {}).except("_errors"),
      properties_errors: (revision.properties_data || {}).dig("_errors") || {}
    }
  rescue Properties::SetService::UnknownKeyError => e
    render json: {error: e.message}, status: :unprocessable_entity
  end

  private

  def set_note
    @note = Note.active.find_by!(slug: params[:slug])
  end
end
