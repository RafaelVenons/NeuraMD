module Notes
  module MentionActions
    extend ActiveSupport::Concern

    def convert_mention
      authorize @note, :show?
      source_note = Note.active.find_by!(slug: params[:source_slug])
      authorize source_note, :update?

      result = Mentions::LinkService.call(
        source_note: source_note,
        target_note: @note,
        matched_term: params[:matched_term],
        author: current_user
      )

      mentions_result = Mentions::UnlinkedService.call(note: @note)
      render json: {
        linked: true,
        graph_changed: result.graph_changed,
        mentions_html: render_to_string(partial: "notes/mentions_content", formats: [:html],
          locals: {mentions: mentions_result.mentions})
      }
    end

    def dismiss_mention
      authorize @note, :show?
      source_note = Note.active.find_by!(slug: params[:source_slug])

      MentionExclusion.find_or_create_by!(
        note: @note,
        source_note: source_note,
        matched_term: params[:matched_term]
      )

      mentions_result = Mentions::UnlinkedService.call(note: @note)
      render json: {
        dismissed: true,
        mentions_html: render_to_string(partial: "notes/mentions_content", formats: [:html],
          locals: {mentions: mentions_result.mentions})
      }
    end
  end
end
