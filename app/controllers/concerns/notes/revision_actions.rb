module Notes
  module RevisionActions
    extend ActiveSupport::Concern

    def revisions
      authorize @note, :show?
      checkpoints = @note.note_revisions.where(revision_kind: :checkpoint).order(created_at: :asc).to_a

      entries = checkpoints.each_with_index.map { |r, i|
        prev_props = i > 0 ? (checkpoints[i - 1].properties_data || {}).except("_errors") : {}
        curr_props = (r.properties_data || {}).except("_errors")

        {
          id: r.id,
          ai_generated: r.ai_generated,
          created_at: r.created_at.iso8601,
          is_head: r.id == @note.head_revision_id,
          content_markdown: r.content_markdown,
          properties_data: curr_props,
          properties_diff: compute_properties_diff(prev_props, curr_props)
        }
      }

      render json: entries.reverse
    end

    def show_revision
      authorize @note, :show?
      @revision = @note.note_revisions.where(revision_kind: :checkpoint).find(params[:revision_id])
      render :show
    end

    def restore_revision
      authorize @note, :update?
      source = @note.note_revisions.where(revision_kind: :checkpoint).find(params[:revision_id])
      result = ::Notes::CheckpointService.call(
        note: @note,
        content: source.content_markdown,
        author: current_user,
        properties_data: source.properties_data
      )
      render json: {saved: true, revision_id: result.revision.id, graph_changed: result.graph_changed}
    rescue => e
      render json: {error: e.message}, status: :unprocessable_entity
    end

    private

    def compute_properties_diff(old_props, new_props)
      all_keys = (old_props.keys + new_props.keys).uniq
      diff = {"added" => {}, "removed" => {}, "changed" => {}}

      all_keys.each do |key|
        if !old_props.key?(key)
          diff["added"][key] = new_props[key]
        elsif !new_props.key?(key)
          diff["removed"][key] = old_props[key]
        elsif old_props[key] != new_props[key]
          diff["changed"][key] = {"from" => old_props[key], "to" => new_props[key]}
        end
      end

      diff
    end
  end
end
