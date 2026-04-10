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

  def parse_error_phase(error_message)
    return ["desconhecida", error_message] if error_message.blank?

    if error_message.start_with?("[converting]")
      ["conversao", error_message.sub("[converting] ", "")]
    elsif error_message.start_with?("[importing]")
      ["importacao", error_message.sub("[importing] ", "")]
    elsif error_message.start_with?("[unexpected]")
      ["inesperada", error_message.sub("[unexpected] ", "")]
    else
      ["desconhecida", error_message]
    end
  end
end
