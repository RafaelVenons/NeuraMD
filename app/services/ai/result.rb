module Ai
  Result = Struct.new(
    :content,
    :provider,
    :model,
    :tokens_in,
    :tokens_out,
    keyword_init: true
  )
end
