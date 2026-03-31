class NoteTagsController < ApplicationController
  include DomainEvents

  def create
    note = Note.find(params[:note_id])
    tag = Tag.find(params[:tag_id])

    authorize note, :update?

    NoteTag.find_or_create_by!(note:, tag:)
    publish_event("property.changed", note_id: note.id, property: "tags", action: "attached", value: tag.name)
    render json: { ok: true }
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :not_found
  end

  def destroy
    note = Note.find(params[:note_id])
    tag = Tag.find(params[:tag_id])

    authorize note, :update?

    NoteTag.where(note:, tag:).delete_all
    publish_event("property.changed", note_id: note.id, property: "tags", action: "detached", value: tag.name)
    head :no_content
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :not_found
  end
end
