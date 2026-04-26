Rails.application.routes.draw do
  mount ActionCable.server => "/cable"

  devise_for :users, controllers: {
    sessions: "users/sessions",
    registrations: "users/registrations"
  }

  get "up" => "rails/health#show", as: :rails_health_check

  match "/mcp", to: "mcp#handle", via: %i[get post delete], as: :mcp_gateway

  root to: redirect("/app")

  get "/app", to: "app#shell", as: :app_shell
  get "/app/*path", to: "app#shell", format: false

  get "api/graph", to: "api/graphs#show", as: :api_graph
  get "api/notes/search", to: "api/notes/search#index", as: :api_notes_search

  namespace :api do
    patch "property_definitions/reorder", to: "property_definitions#reorder", as: :reorder_property_definitions
    resources :property_definitions, only: [:index, :create, :update, :destroy]
    resources :file_imports, only: [:index]
    resources :ai_requests, only: [:index]
  end

  get    "api/tentacles/runtime",  to: "api/tentacles/runtime#index",  as: :api_tentacles_runtime
  get    "api/tentacles/sessions", to: "api/tentacles/sessions#index", as: :api_tentacles_sessions
  post   "api/tentacles/drain",    to: "api/tentacles/drain#create",   as: :api_tentacles_drain

  # Service-to-service tentacle control surface. Token-authed (see
  # Api::S2s::BaseController), for agents (notably the Gerente)
  # activating peer tentacles without a human opening each in the UI.
  scope "api/s2s" do
    constraints slug: /[^\/]+/ do
      post   "tentacles/:slug/activate", to: "api/s2s/tentacles/sessions#activate", as: :api_s2s_tentacle_activate
      delete "tentacles/:slug",          to: "api/s2s/tentacles/sessions#destroy",  as: :api_s2s_tentacle_destroy
    end
  end

  scope "api" do
    constraints slug: /[^\/]+/ do
      get    "notes/:slug",                           to: "api/notes#show",             as: :api_note
      post   "notes/:slug/draft",                     to: "api/notes#draft",            as: :api_note_draft
      post   "notes/:slug/checkpoint",                to: "api/notes#checkpoint",       as: :api_note_checkpoint
      patch  "notes/:slug/properties",                to: "api/notes#update_properties", as: :api_note_properties
      post   "notes/:slug/tags",                      to: "api/notes#attach_tag",       as: :api_note_tags
      delete "notes/:slug/tags/:tag_id",              to: "api/notes#detach_tag",       as: :api_note_tag
      get    "notes/:slug/revisions",                 to: "api/notes#revisions",        as: :api_note_revisions
      post   "notes/:slug/revisions/:revision_id/restore", to: "api/notes#restore_revision", as: :api_note_revision_restore
      get    "notes/:slug/links",                     to: "api/notes#links",            as: :api_note_links
      get    "notes/:slug/ai_requests",               to: "api/notes#ai_requests",      as: :api_note_ai_requests
      get    "notes/:slug/tts",                       to: "api/notes#tts",              as: :api_note_tts

      get    "notes/:slug/tentacle",                  to: "api/tentacles/sessions#show",    as: :api_note_tentacle
      post   "notes/:slug/tentacle",                  to: "api/tentacles/sessions#create",  as: :api_note_tentacle_create
      delete "notes/:slug/tentacle",                  to: "api/tentacles/sessions#destroy", as: :api_note_tentacle_destroy
      get    "notes/:slug/tentacle/inbox",            to: "api/tentacles/inbox#index",      as: :api_note_tentacle_inbox
      post   "notes/:slug/tentacle/inbox/deliver",    to: "api/tentacles/inbox#deliver",    as: :api_note_tentacle_inbox_deliver
      post   "notes/:slug/tentacle/children",         to: "api/tentacles/children#create",  as: :api_note_tentacle_children
    end
  end

  get "api/tags", to: "api/tags#index", as: :api_tags

  resources :file_imports, only: [:index, :new, :create, :show, :destroy] do
    member do
      post :retry
      post :confirm
    end
  end

  if Rails.env.test?
    namespace :test_support do
      post "ai_requests/:id/transition", to: "ai_requests#transition"
    end
  end

  match "/api/*path", to: "api/base#not_found", via: :all, format: false
end
