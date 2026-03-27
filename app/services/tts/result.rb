module Tts
  Result = Struct.new(
    :audio_data,
    :content_type,
    :duration_ms,
    keyword_init: true
  )
end
