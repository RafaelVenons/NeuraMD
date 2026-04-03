class NoteViewsController < ApplicationController
  before_action :set_note_view, only: [:show, :update, :destroy, :results]
  layout "application"

  def index
    authorize NoteView
    @note_views = NoteView.ordered
  end

  def show
    authorize @note_view
  end

  def create
    @note_view = NoteView.new(view_params)
    authorize @note_view

    if @note_view.save
      render json: view_json(@note_view), status: :created
    else
      render json: {errors: @note_view.errors.full_messages}, status: :unprocessable_entity
    end
  end

  def update
    authorize @note_view

    if @note_view.update(view_params)
      render json: view_json(@note_view)
    else
      render json: {errors: @note_view.errors.full_messages}, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @note_view
    @note_view.destroy!
    head :no_content
  end

  def results
    authorize @note_view

    scope = policy_scope(Note).with_latest_content
      .joins("LEFT JOIN note_revisions search_revisions ON search_revisions.id = notes.head_revision_id")
      .group("notes.id, search_revisions.id")

    parsed = @note_view.parsed_filter
    scope = Search::Dsl::Executor.call(scope: scope, tokens: parsed.tokens) if parsed.tokens.any?
    scope = apply_sort(scope)

    page = [params.fetch(:page, 1).to_i, 1].max
    limit = 50
    notes = scope.offset((page - 1) * limit).limit(limit + 1).to_a

    render json: {
      notes: notes.first(limit).map { |n| view_note_json(n) },
      has_more: notes.length > limit,
      page: page,
      dsl_errors: parsed.errors
    }
  end

  def reorder
    authorize NoteView

    ids = params.require(:ids)
    ids.each_with_index do |id, index|
      NoteView.where(id: id).update_all(position: index)
    end

    head :no_content
  end

  private

  def set_note_view
    @note_view = NoteView.find(params[:id])
  end

  def view_params
    permitted = params.require(:note_view).permit(:name, :filter_query, :display_type, columns: [])
    permitted[:sort_config] = parse_sort_config if params.dig(:note_view, :sort_config).present?
    permitted
  end

  def parse_sort_config
    raw = params.dig(:note_view, :sort_config)
    return {} if raw.blank?
    raw.is_a?(String) ? JSON.parse(raw) : raw.to_unsafe_h
  rescue JSON::ParserError
    {}
  end

  def apply_sort(scope)
    field = @note_view.sort_field
    dir = @note_view.sort_direction == :asc ? "ASC" : "DESC"

    if NoteView::BUILTIN_SORT_FIELDS.include?(field)
      scope.order(Arel.sql("notes.#{field} #{dir}"))
    else
      safe_key = NoteView.connection.quote_string(field)
      scope.order(Arel.sql("search_revisions.properties_data->>'#{safe_key}' #{dir} NULLS LAST"))
    end
  end

  def view_json(view)
    {
      id: view.id,
      name: view.name,
      filter_query: view.filter_query,
      display_type: view.display_type,
      sort_config: view.sort_config,
      columns: view.columns,
      position: view.position
    }
  end

  def view_note_json(note)
    revision = note.head_revision
    {
      id: note.id,
      slug: note.slug,
      title: note.title,
      created_at: note.created_at.iso8601,
      updated_at: note.updated_at.iso8601,
      properties: revision&.properties_data || {},
      excerpt: revision&.search_preview_text(limit: 200).to_s
    }
  end
end
