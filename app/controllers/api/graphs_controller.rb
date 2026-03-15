module Api
  class GraphsController < ApplicationController
    def show
      authorize Note.new, :index?

      render json: Graph::DatasetBuilder.call(scope: policy_scope(Note))
    end
  end
end
