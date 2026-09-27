Rails.application.routes.draw do
  # No applications or authorized_applications controllers: registering an app
  # is the only route to the admin scopes, and self-service registration is a
  # privilege-escalation hole.
  use_doorkeeper do
    skip_controllers :applications, :authorized_applications
  end

  devise_for :users
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
end
