module Api
  class GraphController < ApplicationController
    def show
      authorize Note.new, :index?

      render json: Links::GraphPayloadService.call(scope: policy_scope(Note))
    end
  end
end
