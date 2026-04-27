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
        RecentChangesTool,
        CreateNoteTool,
        UpdateNoteTool,
        PatchNoteTool,
        ManagePropertyTool,
        ImportMarkdownTool,
        MergeNotesTool,
        FindAnemicNotesTool,
        BulkRemoveTagTool,
        SendAgentMessageTool,
        ReadAgentInboxTool,
        SpawnChildTentacleTool,
        ActivateTentacleSessionTool,
        RouteHumanToTool,
        TalkToManagerTool,
        ReadManagerRepliesTool,
        AcervoSnapshotTool,
        AgentStatusTool
      ]
    end
  end
end
