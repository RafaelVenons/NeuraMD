class Users::RegistrationsController < Devise::RegistrationsController
  layout "auth"

  protected

  def after_sign_up_path_for(resource)
    graph_path
  end
end
