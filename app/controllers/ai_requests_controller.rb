class AiRequestsController < ApplicationController
  before_action :set_filters
  before_action :set_request, only: [:show, :retry, :destroy, :resolve_queue]

  SORT_OPTIONS = {
    "newest" => "Mais recentes",
    "oldest" => "Mais antigas",
    "attempts_desc" => "Mais tentativas",
    "latency_desc" => "Maior latência",
    "retry_due_first" => "Retry mais urgente"
  }.freeze

  def index
    authorize AiRequest

    if request.format.json?
      requests = queue_scope.reject(&:queue_hidden?).first(limit_param)
      recent_history = recent_history_scope.limit(limit_param)
      return render json: {
        requests: requests.map { |ai_request| serialize_request(ai_request) },
        recent_history: recent_history.map { |ai_request| serialize_request(ai_request) }
      }
    end

    @requests = scoped_requests.limit(limit_param)
    @provider_options = policy_scope(AiRequest).distinct.order(:provider).pluck(:provider).compact_blank
    @model_options = policy_scope(AiRequest).distinct.order(:model).pluck(:model).compact_blank
    @sort_options = SORT_OPTIONS
    @summary = build_summary(@requests)
    alerts = build_alerts(@summary)
    @primary_alert = alerts.first
    @secondary_alerts = alerts.drop(1)

    render partial: "dashboard_content", layout: false if partial_request?
  end

  def show
    authorize @request
    render json: serialize_request(@request)
  end

  def reorder
    authorize AiRequest, :update?

    requests = AiRequest.reorder_globally!(
      ordered_request_ids: params[:ordered_request_ids]
    )

    render json: {
      requests: requests.map { |ai_request| serialize_request(ai_request.reload) }
    }
  end

  def retry
    authorize @request

    Ai::ReviewService.retry_request!(@request)

    respond_to do |format|
      format.json { render json: serialize_request(@request.reload) }
      format.html do
        redirect_to dashboard_path_for(status: nil),
          notice: "Request de IA reenfileirada."
      end
    end
  rescue Ai::Error => e
    respond_to do |format|
      format.json { render json: {error: e.message}, status: :unprocessable_entity }
      format.html do
        redirect_to dashboard_path_for(status: params[:status].presence),
          alert: e.message
      end
    end
  end

  def resolve_queue
    authorize @request

    @request.mark_queue_hidden!
    render json: serialize_request(@request.reload)
  end

  def destroy
    authorize @request

    cleanup_result = nil
    request =
      if @request.capability == "seed_note"
        cleanup_result = Notes::PromiseCleanupService.call(ai_request: @request)
        @request.mark_queue_hidden!
        @request.reload
      else
        Ai::ReviewService.cancel_request!(@request)
      end

    respond_to do |format|
      format.json do
        render json: serialize_request(request).merge(
          undone: cleanup_result.present?,
          promise_note_id: request.metadata["promise_note_id"],
          promise_note_deleted: cleanup_result&.note_deleted || false,
          restored_content: cleanup_result&.source_content,
          graph_changed: cleanup_result&.graph_changed || false
        )
      end
      format.html do
        redirect_to dashboard_path_for(status: "canceled"),
          notice: "Request de IA cancelada."
      end
    end
  rescue Ai::Error => e
    respond_to do |format|
      format.json { render json: {error: e.message}, status: :unprocessable_entity }
      format.html do
        redirect_to dashboard_path_for(status: params[:status].presence),
          alert: e.message
      end
    end
  end

  def retry_visible
    authorize AiRequest, :retry?

    retried = 0
    scoped_requests.find_each do |request|
      next unless request.failed? || request.canceled?

      Ai::ReviewService.retry_request!(request)
      retried += 1
    end

    redirect_to dashboard_path_for(status: nil),
      notice: "#{retried} request(s) de IA reenfileirada(s)."
  rescue Ai::Error => e
    redirect_to dashboard_path_for(status: params[:status].presence),
      alert: e.message
  end

  def cancel_visible
    authorize AiRequest, :destroy?

    canceled = 0
    scoped_requests.find_each do |request|
      next unless request.queued? || request.running? || request.retrying?

      Ai::ReviewService.cancel_request!(request)
      canceled += 1
    end

    redirect_to dashboard_path_for(status: "canceled"),
      notice: "#{canceled} request(s) de IA cancelada(s)."
  rescue Ai::Error => e
    redirect_to dashboard_path_for(status: params[:status].presence),
      alert: e.message
  end

  private

  def set_request
    @request = policy_scope(AiRequest).includes(note_revision: :note).find(params[:id])
  end

  def scoped_requests
    scope = policy_scope(AiRequest).includes(note_revision: :note)
    scope = scope.where(status: @status_filter) if @status_filter.present?
    scope = scope.where(provider: @provider_filter) if @provider_filter.present?
    scope = scope.where(model: @model_filter) if @model_filter.present?
    apply_sort(scope)
  end

  def queue_scope
    policy_scope(AiRequest)
      .includes(note_revision: :note)
      .where(status: %w[queued running retrying failed succeeded])
      .recent_first
  end

  def recent_history_scope
    policy_scope(AiRequest)
      .includes(note_revision: :note)
      .where(status: %w[queued running retrying failed succeeded canceled])
      .recent_first
  end

  def build_summary(requests)
    visible_count = requests.size
    active_count = requests.count { |request| %w[queued running retrying].include?(request.status) }
    failed_count = requests.count(&:failed?)
    succeeded_count = requests.count(&:succeeded?)
    retrying_count = requests.count(&:retrying?)
    duration_values = requests.filter_map(&:duration_ms)

    {
      visible_count: visible_count,
      active_count: active_count,
      failed_count: failed_count,
      succeeded_count: succeeded_count,
      retrying_count: retrying_count,
      queue_count: requests.count(&:queued?),
      running_count: requests.count(&:running?),
      canceled_count: requests.count(&:canceled?),
      avg_duration_ms: duration_values.any? ? (duration_values.sum / duration_values.size.to_f).round : nil,
      max_duration_ms: duration_values.max,
      provider_count: requests.map(&:provider).compact_blank.uniq.size,
      model_count: requests.map(&:model).compact_blank.uniq.size,
      transient_failures_count: requests.count { |request| request.failed? && request.last_error_kind == "transient" },
      stuck_count: requests.count(&:stuck?)
    }
  end

  def build_alerts(summary)
    alerts = []

    if summary[:stuck_count].positive?
      alerts << {
        priority: 100,
        level: "critical",
        title: "Requests presas exigem intervenção",
        kicker: "Incidente principal",
        body: "#{summary[:stuck_count]} execução(ões) parecem travadas entre fila, execução ou retry.",
        primary_action: {
          label: "Abrir incidentes",
          path: dashboard_scope_path(status: nil, sort: "retry_due_first"),
          method: :get,
          style: "primary"
        }
      }
    end

    if summary[:failed_count] >= 3
      alerts << {
        priority: 70,
        level: "warning",
        title: "Acúmulo de falhas visíveis",
        kicker: "Falhas em alta",
        body: "#{summary[:failed_count]} falha(s) no recorte atual. Vale reprocessar ou revisar provider/model.",
        primary_action: {
          label: "Filtrar falhas",
          path: dashboard_scope_path(status: "failed", sort: "newest"),
          method: :get,
          style: "ghost"
        },
        secondary_action: {
          label: "Reprocessar falhas",
          path: retry_visible_ai_requests_path(status: "failed", provider: @provider_filter.presence, model: @model_filter.presence, sort: "newest", limit: params[:limit].presence),
          method: :post,
          style: "primary"
        }
      }
    end

    if summary[:retrying_count] >= 2 || summary[:transient_failures_count] >= 2
      alerts << {
        priority: 60,
        level: "warning",
        title: "Retry congestionado",
        kicker: "Fila de recuperação",
        body: "#{summary[:retrying_count]} request(s) em retry e #{summary[:transient_failures_count]} falha(s) transitória(s) no recorte atual.",
        primary_action: {
          label: "Filtrar retries",
          path: dashboard_scope_path(status: "retrying", sort: "retry_due_first"),
          method: :get,
          style: "ghost"
        },
        secondary_action: {
          label: "Cancelar retries",
          path: cancel_visible_ai_requests_path(status: "retrying", provider: @provider_filter.presence, model: @model_filter.presence, sort: "retry_due_first", limit: params[:limit].presence),
          method: :delete,
          style: "danger"
        }
      }
    end

    if summary[:active_count].zero? && summary[:failed_count].zero? && summary[:stuck_count].zero?
      alerts << {
        priority: 10,
        level: "ok",
        title: "Painel estável",
        kicker: "Sem incidentes",
        body: "Sem requests ativas, falhas acumuladas ou sinais de travamento nos filtros atuais.",
        primary_action: {
          label: "Ver histórico completo",
          path: dashboard_scope_path(status: nil, sort: "newest"),
          method: :get,
          style: "ghost"
        }
      }
    end

    alerts.sort_by { |alert| -alert[:priority].to_i }
  end

  def limit_param
    value = params[:limit].to_i
    return 50 if value <= 0

    [value, 200].min
  end

  def set_filters
    @status_filter = params[:status].to_s.presence
    @provider_filter = params[:provider].to_s.presence
    @model_filter = params[:model].to_s.presence
    @sort_filter = params[:sort].to_s.presence_in(SORT_OPTIONS.keys) || "newest"
  end

  def dashboard_path_for(status: @status_filter)
    ai_requests_dashboard_path(
      status: status.presence,
      provider: @provider_filter.presence,
      model: @model_filter.presence,
      sort: @sort_filter.presence,
      limit: params[:limit].presence
    )
  end

  def dashboard_scope_path(status:, sort: @sort_filter)
    ai_requests_dashboard_path(
      status: status.presence,
      provider: @provider_filter.presence,
      model: @model_filter.presence,
      sort: sort.presence,
      limit: params[:limit].presence
    )
  end

  def apply_sort(scope)
    case @sort_filter
    when "oldest"
      scope.order(created_at: :asc)
    when "attempts_desc"
      scope.order(attempts_count: :desc, created_at: :desc)
    when "latency_desc"
      scope.order(Arel.sql("CASE WHEN started_at IS NULL THEN 1 ELSE 0 END ASC, EXTRACT(EPOCH FROM (COALESCE(completed_at, NOW()) - started_at)) DESC"))
    when "retry_due_first"
      scope.order(Arel.sql("CASE WHEN next_retry_at IS NULL THEN 1 ELSE 0 END ASC, next_retry_at ASC, created_at DESC"))
    else
      scope.recent_first
    end
  end

  def partial_request?
    params[:partial] == "1"
  end

  def serialize_request(request)
    request.realtime_payload
  end
end
