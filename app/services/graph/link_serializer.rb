module Graph
  class LinkSerializer
    def self.call(link)
      {
        id: link.id,
        src_note_id: link.src_note_id,
        dst_note_id: link.dst_note_id,
        hier_role: link.hier_role,
        context: link.context,
        created_at: link.created_at&.iso8601
      }
    end
  end
end
