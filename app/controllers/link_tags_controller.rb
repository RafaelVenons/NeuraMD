class LinkTagsController < ApplicationController
  include DomainEvents

  # POST /link_tags  { note_link_id:, tag_id: }
  def create
    link = NoteLink.find(params[:note_link_id])
    tag  = Tag.find(params[:tag_id])

    authorize link.src_note, :update?

    LinkTag.find_or_create_by!(note_link: link, tag: tag)
    publish_event("property.changed", note_id: link.src_note_id, property: "link_tags", action: "attached", value: tag.name)
    render json: { ok: true }
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :not_found
  end

  # DELETE /link_tags  { note_link_id:, tag_id: }
  def destroy
    link = NoteLink.find(params[:note_link_id])
    tag  = Tag.find(params[:tag_id])

    authorize link.src_note, :update?

    LinkTag.where(note_link: link, tag: tag).delete_all
    publish_event("property.changed", note_id: link.src_note_id, property: "link_tags", action: "detached", value: tag.name)
    head :no_content
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :not_found
  end
end
