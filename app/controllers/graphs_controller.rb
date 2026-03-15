class GraphsController < ApplicationController
  def show
    authorize Note.new, :index?
  end
end
