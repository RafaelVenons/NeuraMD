# frozen_string_literal: true

module Mcp
  module Tools
    def self.all
      [
        SearchNotesTool,
        ReadNoteTool,
        ListTagsTool,
        NotesByTagTool,
        NoteGraphTool,
        CreateNoteTool,
        UpdateNoteTool,
        PatchNoteTool,
        ManagePropertyTool,
        ImportMarkdownTool,
        MergeNotesTool,
        FindAnemicNotesTool
      ]
    end
  end
end
