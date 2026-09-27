source "https://rubygems.org"

# The only pinned gem. Everything else tracks latest.
gem "rails", "~> 8.1.4"

# Use postgresql as the database for Active Record
gem "pg"

# Use the Puma web server
gem "puma"

# Use JavaScript with Vite
gem "vite_rails"

# Build JSON APIs
gem "jbuilder"

gem "bcrypt"

# Auth
gem "devise"
gem "doorkeeper"

# Use the database-backed adapters for Rails.cache and Active Job
gem "solid_cache"
gem "solid_queue"

# Reduces boot times through caching
gem "bootsnap", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma
gem "thruster", require: false

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
end

group :development do
  gem "foreman", require: false
  gem "web-console"
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
end
