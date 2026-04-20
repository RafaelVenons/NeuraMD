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
  patch "ai/requests/:id/resolve_queue", to: "ai_requests#resolve_queue", as: :resolve_ai_request_queue
  post "ai/requests/retry_visible", to: "ai_requests#retry_visible", as: :retry_visible_ai_requests
  delete "ai/requests/cancel_visible", to: "ai_requests#cancel_visible", as: :cancel_visible_ai_requests
  post "ai/requests/:id/retry", to: "ai_requests#retry", as: :retry_ai_request
  delete "ai/requests/:id", to: "ai_requests#destroy", as: :ai_request_dashboard

  root "graphs#show"
  get "graph", to: "graphs#show", as: :graph

  get "/app", to: "app#shell", as: :app_shell
  get "/app/*path", to: "app#shell", format: false
  get "api/graph", to: "api/graphs#show", as: :api_graph
  get "api/tentacles/runtime", to: "api/tentacles/runtime#index", as: :api_tentacles_runtime
  get "api/notes/:slug", to: "api/notes#show", as: :api_note, constraints: {slug: /[^\/]+/}
  post "api/notes/:slug/draft", to: "api/notes#draft", as: :api_note_draft, constraints: {slug: /[^\/]+/}
  patch "api/notes/:slug/properties", to: "api/notes#update_properties", as: :api_note_properties, constraints: {slug: /[^\/]+/}
  post "api/notes/:slug/tags", to: "api/notes#attach_tag", as: :api_note_tags, constraints: {slug: /[^\/]+/}
  delete "api/notes/:slug/tags/:tag_id", to: "api/notes#detach_tag", as: :api_note_tag, constraints: {slug: /[^\/]+/}
  get "api/tags", to: "api/tags#index", as: :api_tags

  resources :canvas_documents, path: "canvas", except: [:edit, :new] do
    resources :canvas_nodes, only: [:create, :update, :destroy] do
      collection { patch :bulk_update }
    end
    resources :canvas_edges, only: [:create, :update, :destroy]
  end

  resources :note_views, path: "views", except: [:edit, :new] do
    member do
      get :results
    end
    collection do
      patch :reorder
    end
  end

  resources :property_definitions, path: "settings/properties", only: [:index, :create, :update, :destroy] do
    collection do
      patch :reorder
    end
  end

  resources :file_imports, only: [:index, :new, :create, :show, :destroy] do
    member do
      post :retry
      post :confirm
    end
  end
  resources :tags, only: [:index, :create, :destroy]

  post   "note_tags", to: "note_tags#create", as: :note_tags
  delete "note_tags", to: "note_tags#destroy"

  # Toggle a tag on a specific note_link (body: { note_link_id, tag_id })
  post   "link_tags", to: "link_tags#create",  as: :link_tags
  delete "link_tags", to: "link_tags#destroy"

  resources :notes, param: :slug do
    collection do
      get :search
      get :search_suggestions
    end
    member do
      patch :aliases, to: "aliases#update"
      patch :properties, to: "properties#update"
      post :create_from_promise
      post :convert_mention
      post :dismiss_mention
      get  :ai_status, to: "ai#status"
      post :ai_review, to: "ai#review"
      get  :ai_requests, to: "ai#index"
      patch "ai_requests/reorder", to: "ai#reorder", as: :reorder_ai_requests
      get "ai_requests/:request_id", to: "ai#show", as: :ai_request
      patch "ai_requests/:request_id/resolve_queue", to: "ai#resolve_queue", as: :resolve_ai_request_queue
      post "ai_requests/:request_id/retry", to: "ai#retry", as: :retry_ai_request
      delete "ai_requests/:request_id", to: "ai#destroy"
      post "ai_requests/:request_id/create_translated_note", to: "ai#create_translated_note", as: :ai_request_translated_note
      post :restore
      post :autosave    # legacy — kept for compatibility during transition
      post :draft       # server-side draft (60s debounce, no history)
      post :checkpoint  # manual save (permanent, appears in history)
      get  :revisions
      get  "revisions/:revision_id", to: "notes#show_revision", as: :revision
      post "revisions/:revision_id/restore", to: "notes#restore_revision", as: :restore_revision
      # Returns { link_id, tags } for a given dst_uuid — used by tag sidebar
      get  :link_info
      get  :embed
      # TTS endpoints
      get   :tts_status,   to: "tts#status"
      post  :tts_generate,  to: "tts#create"
      get   :tts_show,      to: "tts#show"
      patch :tts_reject,    to: "tts#reject"
      get   :tts_audio,     to: "tts#audio"
      get   :tts_library,   to: "tts#library"
    end

    resource :tentacle, only: [:show, :create, :destroy] do
      get "todos", to: "tentacles/todos#show", as: :todos
      patch "todos", to: "tentacles/todos#update"
      post "children", to: "tentacles/children#create", as: :children
      get   "inbox",       to: "tentacles/inbox#index",        as: :inbox
      post  "inbox/deliver",     to: "tentacles/inbox#deliver",     as: :inbox_deliver
    end
  end

  get "/tentacles",       to: "tentacles/dashboard#index", as: :tentacles_dashboard
  get "/tentacles/multi", to: "tentacles/dashboard#multi", as: :tentacles_multi

  if Rails.env.test?
    namespace :test_support do
      post "ai_requests/:id/transition", to: "ai_requests#transition"
    end
  end

  match "/api/*path", to: "api/base#not_found", via: :all, format: false
end
