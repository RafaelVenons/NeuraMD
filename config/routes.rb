Rails.application.routes.draw do
  devise_for :users, controllers: {
    sessions: "users/sessions",
    registrations: "users/registrations"
  }

  get "up" => "rails/health#show", as: :rails_health_check

  root "notes#index"

  resources :notes, param: :slug do
    collection do
      get :search
    end
    member do
      post :autosave    # legacy — kept for compatibility during transition
      post :draft       # server-side draft (60s debounce, no history)
      post :checkpoint  # manual save (permanent, appears in history)
      get  :revisions
      get  "revisions/:revision_id", to: "notes#show_revision", as: :revision
      post "revisions/:revision_id/restore", to: "notes#restore_revision", as: :restore_revision
    end
  end
end
