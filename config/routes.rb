Rails.application.routes.draw do
  devise_for :users, controllers: {
    sessions: "users/sessions",
    registrations: "users/registrations"
  }

  get "up" => "rails/health#show", as: :rails_health_check

  root "notes#index"

  resources :notes, param: :slug do
    member do
      post :autosave
      get  :revisions
    end
  end
end
