Rails.application.routes.draw do
  devise_for :users, controllers: {
    sessions: "users/sessions",
    registrations: "users/registrations"
  }

  get "up" => "rails/health#show", as: :rails_health_check

  root "notes#index"
  get "graph", to: "graphs#show", as: :graph
  get "api/graph", to: "api/graphs#show", as: :api_graph

  resources :tags, only: [:index, :create, :destroy]

  # Toggle a tag on a specific note_link (body: { note_link_id, tag_id })
  post   "link_tags", to: "link_tags#create",  as: :link_tags
  delete "link_tags", to: "link_tags#destroy"

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
      # Returns { link_id, tags } for a given dst_uuid — used by tag sidebar
      get  :link_info
    end
  end
end
