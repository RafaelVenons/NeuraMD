class NoteTagsController < ApplicationController
  def create
    note = Note.find(params[:note_id])
    tag = Tag.find(params[:tag_id])

    authorize note, :update?

    NoteTag.find_or_create_by!(note:, tag:)
    render json: { ok: true }
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :not_found
  end

  def destroy
    note = Note.find(params[:note_id])
    tag = Tag.find(params[:tag_id])

    authorize note, :update?

    NoteTag.where(note:, tag:).delete_all
    head :no_content
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :not_found
  end
end
