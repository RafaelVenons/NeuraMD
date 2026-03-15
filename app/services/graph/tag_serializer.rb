module Graph
  class TagSerializer
    def self.call(tag)
      {
        id: tag.id,
        name: tag.name,
        color_hex: tag.color_hex,
        icon: tag.icon,
        tag_scope: tag.tag_scope
      }
    end
  end
end
