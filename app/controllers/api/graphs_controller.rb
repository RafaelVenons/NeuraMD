module Api
  class GraphsController < BaseController
    def show
      authorize Note.new, :index?

      render json: Graph::DatasetBuilder.call(scope: policy_scope(Note))
    end
  end
end
