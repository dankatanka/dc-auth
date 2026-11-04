class HomeController < ApplicationController
  before_action :authenticate_user!
  # ponytail: post-auth destination until the profile service exists, which
  # owns the settings UI; then this and its view delete and sign-in lands there.
end
