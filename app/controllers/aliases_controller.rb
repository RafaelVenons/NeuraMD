class AliasesController < ApplicationController
  before_action :set_note

  def update
    authorize @note, :update?

    aliases = Array(params[:aliases])
    result = Aliases::SetService.call(
      note: @note,
      aliases: aliases,
      author: current_user
    )

    render json: {aliases: result.aliases}
  rescue ActiveRecord::RecordInvalid => e
    render json: {error: e.message}, status: :unprocessable_entity
  end

  private

  def set_note
    @note = Note.active.find_by!(slug: params[:slug])
  end
end
