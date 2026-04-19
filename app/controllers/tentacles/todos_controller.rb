module Tentacles
  class TodosController < ApplicationController
    before_action :set_note

    def show
      render json: { todos: TodosService.read(@note) }
    end

    def update
      todos_param = params.require(:todos)
      array = todos_param.respond_to?(:to_unsafe_h) ? todos_param.map(&:to_unsafe_h) : Array(todos_param)
      updated = TodosService.write(note: @note, todos: array, author: current_user)
      render json: { todos: updated }
    end

    private

    def set_note
      @note = Note.active.find_by!(slug: params[:note_slug])
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Nota não encontrada." }, status: :not_found
    end
  end
end
