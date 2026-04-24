module Graph
  class NoteSerializer
    EXCERPT_LIMIT = 180
    AGENT_TAG = "agente-team".freeze
    AGENT_TEMPLATE_TAG = "agente-team-template".freeze
    # Matches #rgb and #rrggbb, case-insensitive. Narrow on purpose — unknown
    # formats (names, hsl(), rgba(), #rrggbbaa) fall back to the role palette.
    HEX_COLOR_PATTERN = /\A#(?:\h{3}|\h{6})\z/

    def self.call(note, incoming_link_count: 0, outgoing_link_count: 0, promise_titles: [], alive_tentacle_note_ids: nil)
      new(
        note,
        incoming_link_count:,
        outgoing_link_count:,
        promise_titles:,
        alive_tentacle_note_ids:
      ).call
    end

    def initialize(note, incoming_link_count:, outgoing_link_count:, promise_titles:, alive_tentacle_note_ids:)
      @note = note
      @incoming_link_count = incoming_link_count
      @outgoing_link_count = outgoing_link_count
      @promise_titles = promise_titles
      @alive_tentacle_note_ids = normalize_alive_set(alive_tentacle_note_ids)
    end

    def call
      payload = {
        id: note.id,
        slug: note.slug,
        title: note.title,
        excerpt: excerpt,
        updated_at: note.updated_at&.iso8601,
        created_at: note.created_at&.iso8601,
        incoming_link_count: incoming_link_count,
        outgoing_link_count: outgoing_link_count,
        has_links: has_links?,
        promise_titles: promise_titles,
        promise_count: promise_titles.size,
        has_promises: promise_titles.any?,
        node_type: node_type,
        properties: properties
      }
      payload[:avatar] = avatar_payload if agent?
      payload
    end

    private

    attr_reader :note, :incoming_link_count, :outgoing_link_count, :promise_titles, :alive_tentacle_note_ids

    def excerpt
      note.head_revision&.search_preview_text(limit: EXCERPT_LIMIT)
    end

    def has_links?
      incoming_link_count.positive? || outgoing_link_count.positive?
    end

    def node_type
      names = tag_names
      return "tentacle" if names.include?("tentacle")
      return "root" if names.any? { |n| n.end_with?("-raiz") }
      return "structure" if names.any? { |n| n.end_with?("-estrutura") }

      "leaf"
    end

    def tag_names
      @tag_names ||= note.tags.map(&:name)
    end

    def properties
      (note.head_revision&.properties_data || {}).except("_errors")
    end

    def agent?
      tag_names.include?(AGENT_TAG) && !tag_names.include?(AGENT_TEMPLATE_TAG)
    end

    def avatar_payload
      {
        variant: stored_property("avatar_variant") || Agents::AvatarPalette::DEFAULT_VARIANT,
        color: validated_color || Agents::AvatarPalette.default_color_for(tag_names),
        hat: validated_hat || Agents::AvatarPalette::DEFAULT_HAT,
        state: avatar_state
      }
    end

    # Invalid values persisted by Properties::SetService in non-strict mode land
    # in properties_data["_errors"][key]. Never publish those — fall back to
    # defaults so the graph contract stays inside the declared catalogs.
    def stored_property(key)
      return nil if property_errors.key?(key)
      value = properties[key]
      value.is_a?(String) && !value.empty? ? value : nil
    end

    def validated_hat
      value = stored_property("avatar_hat")
      Agents::AvatarPalette::HATS.include?(value) ? value : nil
    end

    def validated_color
      value = stored_property("avatar_color")
      value && HEX_COLOR_PATTERN.match?(value) ? value : nil
    end

    def property_errors
      @property_errors ||= (note.head_revision&.properties_data || {}).fetch("_errors", {})
    end

    def avatar_state
      alive_tentacle_note_ids.include?(note.id) ? "awake" : "sleeping"
    end

    def normalize_alive_set(source)
      case source
      when nil then Set.new
      when Set then source
      else Set.new(source)
      end
    end
  end
end
