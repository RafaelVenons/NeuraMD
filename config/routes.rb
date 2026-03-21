Rails.application.routes.draw do
  mount ActionCable.server => "/cable"

  devise_for :users, controllers: {
    sessions: "users/sessions",
    registrations: "users/registrations"
  }

  get "up" => "rails/health#show", as: :rails_health_check
  get "ai/requests", to: "ai_requests#index", as: :ai_requests_dashboard
  patch "ai/requests/reorder", to: "ai_requests#reorder", as: :reorder_ai_requests_dashboard
  get "ai/requests/:id/payload", to: "ai_requests#show", as: :ai_request_payload
  post "ai/requests/retry_visible", to: "ai_requests#retry_visible", as: :retry_visible_ai_requests
  delete "ai/requests/cancel_visible", to: "ai_requests#cancel_visible", as: :cancel_visible_ai_requests
  post "ai/requests/:id/retry", to: "ai_requests#retry", as: :retry_ai_request
  delete "ai/requests/:id", to: "ai_requests#destroy", as: :ai_request_dashboard

  root "graphs#show"
  get "graph", to: "graphs#show", as: :graph
  get "api/graph", to: "api/graphs#show", as: :api_graph

  resources :tags, only: [:index, :create, :destroy]

  post   "note_tags", to: "note_tags#create", as: :note_tags
  delete "note_tags", to: "note_tags#destroy"

  # Toggle a tag on a specific note_link (body: { note_link_id, tag_id })
  post   "link_tags", to: "link_tags#create",  as: :link_tags
  delete "link_tags", to: "link_tags#destroy"

  resources :notes, param: :slug do
    collection do
      get :search
    end
    member do
      post :create_from_promise
      get  :ai_status, to: "ai#status"
      post :ai_review, to: "ai#review"
      get  :ai_requests, to: "ai#index"
      patch "ai_requests/reorder", to: "ai#reorder", as: :reorder_ai_requests
      get  "ai_requests/:request_id", to: "ai#show", as: :ai_request
      post "ai_requests/:request_id/retry", to: "ai#retry", as: :retry_ai_request
      delete "ai_requests/:request_id", to: "ai#destroy"
      post "ai_requests/:request_id/create_translated_note", to: "ai#create_translated_note", as: :ai_request_translated_note
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
