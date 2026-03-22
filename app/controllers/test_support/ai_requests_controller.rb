module TestSupport
  class AiRequestsController < ActionController::API
    def transition
      request = AiRequest.find(params[:id])
      transition = params[:transition].to_s

      case transition
      when "running"
        request.update!(
          status: "running",
          started_at: Time.current,
          attempts_count: [request.attempts_count.to_i, 1].max,
          completed_at: nil,
          error_message: nil,
          last_error_at: nil,
          last_error_kind: nil,
          next_retry_at: nil
        )
      when "succeeded"
        body = params[:body].to_s
        body = "# #{request.metadata.fetch('promise_note_title', 'Nota')}\n\nConteudo gerado no suporte de teste." if body.blank?

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
      else
        render json: { error: "Unsupported transition: #{transition}" }, status: :unprocessable_entity
        return
      end

      render json: request.reload.realtime_payload
    end
  end
end
