# frozen_string_literal: true

module FileImportsHelper
  def split_level_label(level)
    case level
    when nil, "" then "Todo heading"
    when -1 then "Auto-detect"
    when 0 then "Sem fragmentacao"
    else "Cortar em H#{level}"
    end
  end
end
