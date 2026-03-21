ENV["AI_ENABLED"] ||= "true"
ENV["AI_PROVIDER"] ||= "ollama"
ENV["AI_ENABLED_PROVIDERS"] ||= "ollama"
ENV["OLLAMA_API_BASE"] ||= "http://AIrch:11434"
ENV["OLLAMA_MODEL"] ||= "qwen2.5:1.5b"
ENV["AI_PROVIDER_OPEN_TIMEOUT"] ||= "5"
ENV["AI_PROVIDER_READ_TIMEOUT"] ||= "180"
ENV["AI_PROVIDER_WRITE_TIMEOUT"] ||= "30"

require "securerandom"

puts "[phase5] smoke test starting"
puts "[phase5] provider env: #{ENV["AI_PROVIDER"]} / #{ENV["OLLAMA_API_BASE"]} / #{ENV["OLLAMA_MODEL"]}"
puts "[phase5] timeouts: open=#{ENV["AI_PROVIDER_OPEN_TIMEOUT"]}s read=#{ENV["AI_PROVIDER_READ_TIMEOUT"]}s write=#{ENV["AI_PROVIDER_WRITE_TIMEOUT"]}s"

status = Ai::ReviewService.status
puts "[phase5] registry status: #{status.inspect}"

unless status[:enabled]
  abort "[phase5] AI is not enabled for the current environment"
end

sample_text = <<~MARKDOWN.strip
  # Revisao com IA

  Este texto tem alguns erro de concordancia e pontuacao. Ele foi escrito para validar a integracao real com o AIrch.
MARKDOWN

slug = "phase5-ai-smoke-#{SecureRandom.hex(4)}"
note = Note.create!(title: "Phase 5 AI Smoke #{Time.current.to_i}", slug:)

checkpoint = Notes::CheckpointService.call(
  note: note,
  content: sample_text,
  author: User.first
)

request = Ai::ReviewService.enqueue(
  note: note,
  note_revision: checkpoint,
  capability: "grammar_review",
  text: sample_text,
  language: "pt-BR",
  provider_name: ENV["AI_PROVIDER"],
  model_name: ENV["OLLAMA_MODEL"],
  requested_by: User.first
)

puts "[phase5] ai_request queued: #{request.id}"

Ai::ReviewJob.perform_now(request.id)

while request.reload.retrying?
  wait_seconds = [(request.next_retry_at.to_f - Time.current.to_f).ceil, 0].max
  puts "[phase5] retry scheduled in #{wait_seconds}s after transient failure: #{request.error_message}"
  sleep(wait_seconds) if wait_seconds.positive?
  Ai::ReviewJob.perform_now(request.id)
end

puts "[phase5] ai_request status: #{request.status}"
puts "[phase5] provider/model used: #{request.provider}: #{request.model}"
puts "[phase5] output preview:"
puts request.output_text.to_s.lines.first(8).join

unless request.succeeded?
  abort "[phase5] AI review failed: #{request.error_message || request.last_error_kind || request.status}"
end

accepted_revision = Notes::CheckpointService.call(
  note: note,
  content: request.output_text,
  author: User.first,
  accepted_ai_request: request
)

puts "[phase5] accepted checkpoint: #{accepted_revision.id}"
puts "[phase5] accepted checkpoint ai_generated: #{accepted_revision.ai_generated}"
puts "[phase5] ai_request acceptance metadata: #{request.reload.metadata.slice("accepted_checkpoint_revision_id", "accepted_at", "accepted_by_id").inspect}"

unless accepted_revision.ai_generated?
  abort "[phase5] accepted checkpoint was not marked as ai_generated"
end

unless request.metadata["accepted_checkpoint_revision_id"] == accepted_revision.id
  abort "[phase5] ai_request metadata was not linked to the accepted checkpoint"
end

puts "[phase5] smoke test passed"
