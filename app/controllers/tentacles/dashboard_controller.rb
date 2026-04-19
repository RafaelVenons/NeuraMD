module Tentacles
  class DashboardController < ApplicationController
    before_action :ensure_tentacles_enabled!

    def index
      @sessions = active_sessions
    end

    def multi
      ids = parse_ids(params[:ids])
      return redirect_to tentacles_dashboard_path, alert: "Nenhum tentáculo selecionado." if ids.empty?

      @panels = ids.filter_map { |id| panel_for(id) }
      redirect_to tentacles_dashboard_path, alert: "Tentáculos não encontrados." if @panels.empty?
    end

    private

    def parse_ids(raw)
      Array(raw).flat_map { |v| v.to_s.split(",") }.map(&:strip).reject(&:blank?).uniq
    end

    def active_sessions
      TentacleRuntime::SESSIONS.each_pair.filter_map do |id, session|
        note = Note.active.find_by(id: id)
        next unless note

        {
          tentacle_id: id,
          note: note,
          started_at: session.started_at,
          alive: session.alive?,
          pid: session.pid,
          command: session.instance_variable_get(:@command)
        }
      end.sort_by { |row| row[:started_at] || Time.current }.reverse
    end

    def panel_for(id)
      note = Note.active.find_by(id: id)
      return nil unless note

      session = TentacleRuntime.get(id)
      { tentacle_id: id, note: note, alive: session&.alive? || false }
    end

    def ensure_tentacles_enabled!
      return if Tentacles::Authorization.enabled?

      redirect_to root_path, alert: "Tentáculos desativados neste ambiente."
    end
  end
end
