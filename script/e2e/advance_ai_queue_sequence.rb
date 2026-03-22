require "json"

token = ENV.fetch("E2E_TOKEN")
stage = ENV.fetch("E2E_STAGE")
request_ids = ENV.fetch("E2E_REQUEST_IDS").split(",").map(&:strip).reject(&:empty?)
deadline = Time.current + 30.seconds
requests = []

loop do
  requests = request_ids.filter_map { |id| AiRequest.find_by(id:) }
  break if requests.size == request_ids.size || Time.current >= deadline

  sleep 0.25
end

requests.sort_by!(&:created_at)

first, second = requests

def fulfill!(request, body:)
  request.update!(
    status: "succeeded",
    started_at: request.started_at || 5.seconds.ago,
    completed_at: Time.current,
    attempts_count: [request.attempts_count.to_i, 1].max,
    output_text: body,
    response_summary: body.truncate(240),
    error_message: nil,
    last_error_at: nil,
    last_error_kind: nil,
    next_retry_at: nil
  )
  Notes::PromiseFulfillmentService.call(ai_request: request)
end

case stage
when "snapshot"
  # no-op
when "first_running"
  raise "Expected #{request_ids.size} seed_note requests, found #{requests.size}" unless requests.size == request_ids.size
  first.update!(
    status: "running",
    started_at: Time.current,
    attempts_count: [first.attempts_count.to_i, 1].max,
    completed_at: nil,
    error_message: nil,
    last_error_at: nil,
    last_error_kind: nil,
    next_retry_at: nil
  )
when "first_succeeded"
  raise "Expected #{request_ids.size} seed_note requests, found #{requests.size}" unless requests.size == request_ids.size
  fulfill!(first, body: "# #{first.metadata.fetch('promise_note_title')}\n\nConteudo da primeira promise.")
when "second_running"
  raise "Expected #{request_ids.size} seed_note requests, found #{requests.size}" unless requests.size == request_ids.size
  second.update!(
    status: "running",
    started_at: Time.current,
    attempts_count: [second.attempts_count.to_i, 1].max,
    completed_at: nil,
    error_message: nil,
    last_error_at: nil,
    last_error_kind: nil,
    next_retry_at: nil
  )
when "second_succeeded"
  raise "Expected #{request_ids.size} seed_note requests, found #{requests.size}" unless requests.size == request_ids.size
  fulfill!(second, body: "# #{second.metadata.fetch('promise_note_title')}\n\nConteudo da segunda promise.")
else
  raise "Unknown E2E_STAGE=#{stage.inspect}"
end

requests.each(&:reload)

puts JSON.generate(
  requests: requests.map do |request|
    {
      id: request.id,
      title: request.metadata["promise_note_title"],
      status: request.status,
      queue_position: request.queue_position
    }
  end
)
