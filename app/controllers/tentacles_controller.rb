class TentaclesController < ApplicationController
  before_action :ensure_tentacles_enabled!
  before_action :set_note

  KNOWN_COMMANDS = {
    "bash" => ["bash", "-l"],
    "claude" => ["claude"]
  }.freeze

  def show
    @tentacle_id = @note.id
    @session = TentacleRuntime.get(@tentacle_id)
    @worktree = WorktreeService.path_for(tentacle_id: @note.id)
    @outgoing_links = @note.active_outgoing_links.includes(:dst_note).to_a.select { |l| l.dst_note && !l.dst_note.deleted? }
    @incoming_links = @note.active_incoming_links.includes(:src_note).to_a.select { |l| l.src_note && !l.src_note.deleted? }
  end

  def create
    command = resolve_command(params[:command])
    cwd = WorktreeService.ensure(tentacle_id: @note.id)
    note = @note
    author = current_user
    session = TentacleRuntime.start(
      tentacle_id: @note.id,
      command: command,
      cwd: cwd,
      on_exit: ->(transcript:, command:, started_at:, ended_at:, **) do
        Tentacles::TranscriptService.persist(
          note: note,
          transcript: transcript,
          command: command,
          started_at: started_at,
          ended_at: ended_at,
          author: author
        )
      end
    )

    respond_to do |fmt|
      fmt.json do
        render json: {
          tentacle_id: @note.id,
          pid: session.pid,
          cwd: cwd,
          command: command,
          alive: session.alive?
        }
      end
      fmt.html { redirect_to note_tentacle_path(@note.slug) }
    end
  end

  def destroy
    TentacleRuntime.stop(tentacle_id: @note.id)

    respond_to do |fmt|
      fmt.json { render json: { stopped: true } }
      fmt.html { redirect_to note_tentacle_path(@note.slug), notice: "Tentáculo encerrado." }
    end
  end

  private

  def ensure_tentacles_enabled!
    return if Tentacles::Authorization.enabled?

    respond_to do |fmt|
      fmt.json { render json: { error: "Tentacles disabled in this environment." }, status: :forbidden }
      fmt.html { redirect_to root_path, alert: "Tentáculos desativados neste ambiente." }
    end
  end

  def set_note
    @note = Note.active.find_by!(slug: params[:note_slug])
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "Nota não encontrada."
  end

  def resolve_command(raw)
    key = raw.to_s.strip.downcase
    KNOWN_COMMANDS.fetch(key, KNOWN_COMMANDS.fetch("bash"))
  end
end
