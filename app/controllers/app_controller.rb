class AppController < ApplicationController
  layout "app_shell"

  def shell
    render :shell
  end
end
