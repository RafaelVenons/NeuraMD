module Search
  class NoteQueryService
    DEFAULT_LIMIT = 20
    MAX_LIMIT = 50
    REGEX_STATEMENT_TIMEOUT = "150ms"

    Result = Struct.new(
      :notes,
      :page,
      :limit,
      :query,
      :regex,
      :has_more,
      :error,
      keyword_init: true
    )

    def self.call(scope:, query:, regex: false, page: 1, limit: DEFAULT_LIMIT, property_filters: nil)
      new(scope:, query:, regex:, page:, limit:, property_filters:).call
    end

    def initialize(scope:, query:, regex:, page:, limit:, property_filters: nil)
      @scope = scope
      @query = query.to_s.strip
      @regex = ActiveModel::Type::Boolean.new.cast(regex)
      @page = [page.to_i, 1].max
      @limit = [[limit.to_i, 1].max, MAX_LIMIT].min
      @limit = DEFAULT_LIMIT if limit.to_i <= 0
      @property_filters = property_filters.is_a?(Hash) ? property_filters.select { |_, v| v.present? || v == false } : {}
    end

    def call
      return empty_query_result if query.blank?

      regex ? regex_result : ranked_result
    rescue RegexpError
      result_with_error("Regex invalida")
    rescue ActiveRecord::StatementInvalid => error
      if error.message.match?(/statement timeout|invalid regular expression/i)
        result_with_error("Busca muito cara para executar agora")
      else
        raise
      end
    end

    private

    attr_reader :scope, :query, :regex, :page, :limit, :property_filters

    def empty_query_result
      relation = joined_scope.order(updated_at: :desc)
      build_result(load_page(relation))
    end

    def ranked_result
      relation = joined_scope
        .where(ranked_where_sql)
        .select(Arel.sql(ranked_select_sql))
        .order(Arel.sql(ranked_order_sql))

      build_result(load_page(relation))
    end

    def regex_result
      Regexp.new(query)

      notes = nil
      scope.transaction do
        scope.connection.execute("SET LOCAL statement_timeout = '#{REGEX_STATEMENT_TIMEOUT}'")
        notes = load_page(
          joined_scope
            .where("notes.title ~* :pattern OR COALESCE(search_revisions.content_plain, '') ~* :pattern", pattern: query)
            .select("notes.*, search_revisions.content_plain AS search_content_plain")
            .order(updated_at: :desc)
        )
      end

      build_result(notes)
    end

    def joined_scope
      @joined_scope ||= begin
        base = scope
          .merge(Note.with_latest_content)
          .joins("LEFT JOIN note_revisions search_revisions ON search_revisions.id = notes.head_revision_id")
          .joins("LEFT JOIN note_aliases search_aliases ON search_aliases.note_id = notes.id")
          .includes(:head_revision)
          .group("notes.id, search_revisions.id")
        apply_property_filters(base)
      end
    end

    def apply_property_filters(relation)
      return relation if property_filters.blank?

      property_filters.each do |key, value|
        relation = relation.where("search_revisions.properties_data @> ?", {key => value}.to_json)
      end
      relation
    end

    def load_page(relation)
      relation.offset(offset).limit(limit + 1).to_a
    end

    def build_result(notes)
      Result.new(
        notes: notes.first(limit),
        page: page,
        limit: limit,
        query: query,
        regex: regex,
        has_more: notes.length > limit
      )
    end

    def result_with_error(message)
      Result.new(
        notes: [],
        page: page,
        limit: limit,
        query: query,
        regex: regex,
        has_more: false,
        error: message
      )
    end

    def offset
      (page - 1) * limit
    end

    def ranked_select_sql
      <<~SQL.squish
        notes.*,
        search_revisions.content_plain AS search_content_plain,
        #{title_similarity_sql} AS title_similarity,
        #{content_similarity_sql} AS content_similarity,
        #{content_rank_sql} AS content_rank
      SQL
    end

    def ranked_where_sql
      <<~SQL.squish
        unaccent(notes.title) ILIKE unaccent(#{quoted_pattern})
        OR unaccent(COALESCE(search_revisions.content_plain, '')) ILIKE unaccent(#{quoted_pattern})
        OR #{title_similarity_sql} > 0.12
        OR #{content_similarity_sql} > 0.08
        OR to_tsvector('simple', COALESCE(search_revisions.content_plain, '')) @@ #{ts_query_sql}
        OR unaccent(search_aliases.name) ILIKE unaccent(#{quoted_pattern})
        OR #{alias_similarity_sql} > 0.12
      SQL
    end

    def ranked_order_sql
      <<~SQL.squish
        CASE
          WHEN unaccent(notes.title) ILIKE unaccent(#{quoted_pattern}) THEN 0
          WHEN unaccent(COALESCE(search_revisions.content_plain, '')) ILIKE unaccent(#{quoted_pattern}) THEN 1
          ELSE 2
        END ASC,
        GREATEST((#{title_similarity_sql} * 2.0), #{content_similarity_sql}, (#{content_rank_sql} * 1.5)) DESC,
        notes.updated_at DESC
      SQL
    end

    def quoted_query
      @quoted_query ||= scope.connection.quote(query)
    end

    def quoted_pattern
      @quoted_pattern ||= scope.connection.quote("%#{Note.sanitize_sql_like(query)}%")
    end

    def title_similarity_sql
      "similarity(unaccent(notes.title), unaccent(#{quoted_query}))"
    end

    def content_similarity_sql
      "similarity(unaccent(COALESCE(search_revisions.content_plain, '')), unaccent(#{quoted_query}))"
    end

    def ts_query_sql
      "websearch_to_tsquery('simple', #{quoted_query})"
    end

    def alias_similarity_sql
      "similarity(unaccent(COALESCE(search_aliases.name, '')), unaccent(#{quoted_query}))"
    end

    def content_rank_sql
      "ts_rank_cd(to_tsvector('simple', COALESCE(search_revisions.content_plain, '')), #{ts_query_sql})"
    end
  end
end
