class Users::SessionsController < Devise::SessionsController
  layout "auth"

  protected

  def after_sign_in_path_for(resource)
    graph_path
  end
end
