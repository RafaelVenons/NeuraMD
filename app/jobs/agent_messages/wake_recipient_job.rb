require "net/http"
require "uri"
require "json"

module AgentMessages
  # Wakes the recipient of a freshly created AgentMessage so the inbox
  # is consumed promptly instead of sitting dormant until the agent
  # next boots. Enqueued by AgentMessage#after_create_commit.
  #
  # The job never touches a PTY directly. It POSTs the S2S activate
  # endpoint and lets Tentacles::SessionControl (running in the web
  # process) decide: a live session gets the prompt written via its
  # submit sequence, a dormant note gets a fresh session spawned with
  # the prompt as initial_prompt. That delegation also sidesteps the
  # per-process TentacleRuntime::SESSIONS map — this job runs in the
  # worker and could not see web-hosted sessions anyway.
  class WakeRecipientJob < ApplicationJob
    # Raised when the S2S activate call fails in a way a retry could
    # plausibly fix (5xx, connection refused, timeout). Permanent
    # per-note failures (non-auth 4xx) are logged and not raised.
    class WakeActivationError < StandardError; end

    # Raised on an operator-fixable misconfiguration: missing S2S token,
    # unsafe transport, unset base URL, or an auth rejection (401/403)
    # that points at a broken/rotated token. Not retryable — a broken
    # deploy must surface as a failed job, not vanish behind retries or
    # a silently consumed debounce slot.
    class WakeConfigurationError < StandardError; end

    queue_as :default

    discard_on ActiveJob::DeserializationError
    discard_on ActiveRecord::RecordNotFound

    retry_on WakeActivationError,
      Errno::ECONNREFUSED,
      Net::OpenTimeout,
      Net::ReadTimeout,
      SocketError,
      wait: :polynomially_longer,
      attempts: 5

    AGENT_TAG_PREFIX = "agente-"
    # Short worker-side debounce — just collapses a tight burst of
    # near-simultaneous enqueues. The real liveness-aware decision
    # (live session vs dormant, redundant nudge vs needed wake) happens
    # in SessionControl on the web process via coalesce_wake.
    DEBOUNCE_WINDOW = 5.seconds
    # Slack added on top of DEBOUNCE_WINDOW when scheduling the
    # follow-up re-check, so the debounce slot is reliably free by the
    # time the follow-up runs.
    FOLLOWUP_BUFFER = 5.seconds
    TOKEN_HEADER = "X-NeuraMD-Agent-Token"
    DEFAULT_BASE_URL = "http://127.0.0.1:3000"
    LOOPBACK_HOSTS = %w[127.0.0.1 ::1 localhost].freeze

    def perform(to_note_id)
      # Re-check the gate at run time, not just at enqueue: a job (or a
      # scheduled follow-up) may already be queued when an operator
      # disables tentacle operations for a rollback or incident. The
      # callback gate alone would let those queued jobs still POST.
      return unless Tentacles::Authorization.enabled?

      note = Note.active.find_by(id: to_note_id)
      return unless note
      return unless agent_note?(note)
      return if note.slug.blank?

      # A wake at time T "covers" every message pending at T — the woken
      # agent reads its whole inbox and sees them all. A message still
      # pending but created on/before the last wake is the agent being
      # slow, not a missed wake; re-waking for it would re-activate a
      # backlog already in flight. Only a message created after the last
      # wake is genuinely uncovered and justifies another wake.
      covered_through = AgentWakeState.find_by(note_id: note.id)&.last_wake_attempt_at
      uncovered = AgentMessage.where(to_note_id: note.id, delivered_at: nil)
      uncovered = uncovered.where("created_at > ?", covered_through) if covered_through
      return unless uncovered.exists?

      ensure_wake_state(note)
      claimed_at = claim_wake_slot(note)
      return unless claimed_at

      pending_count = AgentMessage.where(to_note_id: note.id, delivered_at: nil).count
      outcome =
        begin
          activate(note, pending_count)
        rescue StandardError
          # 5xx, network, config, and non-auth 4xx all land here — the
          # wake was not delivered, so the slot must not stay advanced
          # or the triggering message gets falsely marked covered.
          release_wake_slot(note, claimed_at: claimed_at)
          raise
        end

      case outcome
      when :delivered
        # A prompt actually reached a session — the advanced slot
        # legitimately marks these messages covered. Re-check past the
        # debounce window for messages that land while the slot is held;
        # the uncovered rule keeps a slow agent from being re-poked.
        schedule_followup(note)
      when :coalesced, :not_delivered
        # SessionControl returned 2xx but the prompt did NOT actually
        # land in a session — either a redundant nudge was skipped
        # (coalesced) or the spawn could not confirm initial_prompt
        # delivery (PTY readiness race; routed_prompt_delivered=false).
        # Release the slot so the triggering message stays uncovered;
        # the follow-up will try again once coalescing has expired and
        # the session has had a chance to settle.
        release_wake_slot(note, claimed_at: claimed_at)
        schedule_followup(note)
      end
    end

    private

    def agent_note?(note)
      note.tags.pluck(:name).any? { |name| name.start_with?(AGENT_TAG_PREFIX) }
    end

    # Ensures the wake-state row exists so claim_wake_slot's conditional
    # UPDATE has a target. Retries once on the insert race where a
    # concurrent job created the row first.
    def ensure_wake_state(note)
      AgentWakeState.find_or_create_by!(note_id: note.id)
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    # Debounce per recipient: a burst of N messages collapses into one
    # wake. The conditional UPDATE is atomic — only one concurrent job
    # wins inside the window, because the winner flips
    # last_wake_attempt_at out of range before the losers' UPDATEs
    # re-evaluate the WHERE. Returns the claim timestamp on success
    # (caller passes it to release_wake_slot for the CAS check), or nil
    # when the burst is already covered.
    def claim_wake_slot(note)
      now = Time.current
      rows = AgentWakeState
        .where(note_id: note.id)
        .where("last_wake_attempt_at IS NULL OR last_wake_attempt_at <= :window_start",
          window_start: DEBOUNCE_WINDOW.ago)
        .update_all(last_wake_attempt_at: now, updated_at: now)

      rows.positive? ? now : nil
    end

    # Clears the debounce slot after a failed wake so the next attempt
    # is not suppressed. Conditional on `claimed_at` (compare-and-swap):
    # an older job whose activate took longer than the debounce window
    # could otherwise erase the claim a newer job has already placed
    # for later messages. We only zero the slot when it still holds the
    # value WE set — never a fresher claimant's.
    # Best-effort: a failure here is logged but never masks the original
    # error that triggered the release.
    def release_wake_slot(note, claimed_at:)
      AgentWakeState
        .where(note_id: note.id, last_wake_attempt_at: claimed_at)
        .update_all(last_wake_attempt_at: nil, updated_at: Time.current)
    rescue StandardError => e
      Rails.logger.error(
        "AgentMessages::WakeRecipientJob: failed to release wake slot for #{note.slug}: " \
        "#{e.class}: #{e.message}"
      )
    end

    def schedule_followup(note)
      self.class.set(wait: DEBOUNCE_WINDOW + FOLLOWUP_BUFFER).perform_later(note.id)
    end

    # Returns :delivered when a prompt actually reached a session (2xx,
    # not coalesced) and :coalesced when SessionControl skipped a
    # redundant write. Raises WakeConfigurationError on an
    # operator-fixable misconfiguration (missing token, unsafe
    # transport, unset base URL, 401/403 auth rejection),
    # WakeActivationError on a transient 5xx or a non-auth 4xx, and lets
    # network errors propagate so retry_on can take over. Every
    # non-:delivered outcome must leave the wake slot eligible for
    # release — "covered" means a prompt was delivered, nothing less.
    def activate(note, pending_count)
      token = resolve_token
      if token.blank?
        # A missing token is a broken deploy, not a transient fault or a
        # per-note problem — fail loudly so it surfaces instead of
        # vanishing into a silently consumed debounce slot.
        raise WakeConfigurationError, "AGENT_S2S_TOKEN is not configured; cannot wake #{note.slug}"
      end

      uri = URI.parse("#{base_url}/api/s2s/tentacles/#{URI.encode_www_form_component(note.slug)}/activate")
      unless safe_transport?(uri)
        raise WakeConfigurationError,
          "refusing S2S token over plaintext HTTP to non-loopback host #{uri.host}; " \
          "cannot wake #{note.slug}"
      end

      # coalesce_wake lets SessionControl skip a redundant nudge to a
      # live session it just woke — the liveness-aware dedup the worker
      # cannot do itself.
      payload = {initial_prompt: wake_prompt(note, pending_count), coalesce_wake: true}
      body, status = post_json(uri, payload, token)

      return wake_outcome(body) if status.between?(200, 299)

      if status >= 500
        # Transient — the runtime may be down. Raise so the job retries.
        raise WakeActivationError, "activate failed for #{note.slug} (HTTP #{status}): #{body}"
      end

      if [401, 403].include?(status)
        # Auth rejection is a broken/rotated token — a deploy-level
        # failure that disables wakes for every agent, not a per-note
        # problem. Fail loudly like the other misconfigurations.
        raise WakeConfigurationError,
          "S2S activate rejected the agent token (HTTP #{status}) for #{note.slug}: #{body}"
      end

      # Other 4xx — 404 (note gone), 409 (stale boot config / dirty
      # worktree), 422 (bad config). The wake was not delivered, so the
      # triggering message must stay uncovered; raise so the rescue
      # releases the slot. retry_on gives operator-fixable cases
      # (409/422) a bounded recovery window; a genuinely permanent 4xx
      # just fails after the retry cap, with the slot released.
      raise WakeActivationError, "activate failed for #{note.slug} (HTTP #{status}): #{body}"
    end

    # Maps a 2xx S2S activate response body into the wake outcome.
    # :coalesced       SessionControl skipped a redundant write (recently
    #                  nudged) — the triggering message was NOT delivered.
    # :not_delivered   Fresh spawn happened but the initial_prompt did
    #                  not confirm delivery (PTY readiness race) — also
    #                  not actually delivered.
    # :delivered       Prompt landed in a session (either the reuse
    #                  write or the spawn's confirmed initial_prompt).
    # The caller only keeps the wake slot advanced for :delivered;
    # everything else releases + schedules a follow-up so the message
    # stays uncovered (Codex finding: "covered" means delivered).
    def wake_outcome(body)
      parsed = JSON.parse(body.to_s)
      parsed = {} unless parsed.is_a?(Hash)
      return :coalesced if parsed["wake_coalesced"] == true
      return :not_delivered if parsed["routed_prompt_delivered"] == false

      :delivered
    rescue JSON::ParserError
      :delivered
    end

    def wake_prompt(note, pending_count)
      "Você tem #{pending_count} mensagem(ns) pendente(s) na sua inbox. " \
        "Rode read_agent_inbox(slug: \"#{note.slug}\", mark_delivered: true) e " \
        "responda conforme a Carta comum dos agentes."
    end

    # The worker cannot assume it shares a host with the web process,
    # so the loopback default is only acceptable in development/test.
    # Anywhere else an explicit NEURAMD_S2S_URL is required, and its
    # absence fails loudly instead of burning retries against an
    # unreachable 127.0.0.1.
    def base_url
      configured = ENV["NEURAMD_S2S_URL"].to_s.strip
      return configured unless configured.empty?

      unless Rails.env.development? || Rails.env.test?
        raise WakeConfigurationError,
          "NEURAMD_S2S_URL must be set outside development/test — a worker that does " \
          "not share a host with the web process cannot reach it on loopback"
      end

      DEFAULT_BASE_URL
    end

    # ENV wins over credentials — autodeploy's `git reset --hard` would
    # wipe an uncommitted credentials.yml.enc update, so production
    # injects the token via systemd drop-in env.
    def resolve_token
      env_value = ENV["AGENT_S2S_TOKEN"].to_s.strip
      return env_value unless env_value.empty?

      Rails.application.credentials.agent_s2s_token
    end

    def safe_transport?(uri)
      return true if uri.scheme == "https"
      return true if uri.scheme == "http" && LOOPBACK_HOSTS.include?(uri.host.to_s)

      false
    end

    def post_json(uri, payload, token)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = 30

      request = Net::HTTP::Post.new(uri.request_uri, {
        "Content-Type" => "application/json",
        TOKEN_HEADER => token
      })
      request.body = payload.to_json

      response = http.request(request)
      [response.body, response.code.to_i]
    end
  end
end
