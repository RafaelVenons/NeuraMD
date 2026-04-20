module Tentacles
  class InboxController < ApplicationController
    before_action :ensure_tentacles_enabled!
    before_action :set_note

    def index
      only_pending = ActiveModel::Type::Boolean.new.cast(params[:only_pending])
      limit = params[:limit].presence&.to_i
      limit = AgentMessages::Inbox::DEFAULT_LIMIT if limit.blank? || limit <= 0

      messages = AgentMessages::Inbox.for(@note, limit: limit, only_pending: only_pending).to_a
      pending_count = AgentMessage.inbox(@note).where(delivered_at: nil).count

      render json: {
        slug: @note.slug,
        count: messages.size,
        pending_count: pending_count,
        messages: messages.map { |m| serialize(m) }
      }
    end

    def deliver
      raw_ids = params[:ids]
      raw_ids = raw_ids.values if raw_ids.is_a?(ActionController::Parameters)
      ids = Array(raw_ids).map(&:to_s).reject(&:blank?)
      flipped = AgentMessages::Inbox.mark_delivered!(@note, ids: ids)
      render json: {slug: @note.slug, marked_delivered: flipped}
    end

    private

    def ensure_tentacles_enabled!
      return if Tentacles::Authorization.enabled?

      render json: {error: "Tentacles disabled in this environment."}, status: :forbidden
    end

    def set_note
      @note = Note.active.find_by(slug: params[:note_slug])
      render json: {error: "Note not found."}, status: :not_found unless @note
    end

    def serialize(message)
      {
        id: message.id,
        from_slug: message.from_note.slug,
        from_title: message.from_note.title,
        content: message.content,
        delivered: message.delivered?,
        delivered_at: message.delivered_at&.iso8601,
        created_at: message.created_at.iso8601
      }
    end
  end
end
