Rails.application.routes.draw do
  # Health check endpoint (no authentication required)
  get 'health', to: 'health#show'

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get 'up' => 'rails/health#show', as: :rails_health_check

  # Web UI
  root 'bookmarks#index'
  resources :bookmarks, only: %i[index show new create destroy] do
    collection do
      get :search
    end
  end

  # API v1 namespace
  namespace :api do
    namespace :v1 do
      resources :bookmarks, only: %i[create index show destroy] do
        collection do
          get :search
        end
      end
    end
  end
end
