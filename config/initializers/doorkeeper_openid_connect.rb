# frozen_string_literal: true

# No key is committed. Development and test use the gitignored tmp/ key that
# bin/setup generates; production mounts its own and a boot without one fails.
oidc_signing_key_path = ENV["OIDC_SIGNING_KEY_PATH"].presence
if oidc_signing_key_path.nil?
  raise "OIDC_SIGNING_KEY_PATH is required in production" if Rails.env.production?

  oidc_signing_key_path = Rails.root.join("tmp/oidc-signing-key.pem")
end

# A relative path in the env would otherwise resolve against the process CWD.
oidc_signing_key_path = Rails.root.join(oidc_signing_key_path) unless Pathname.new(oidc_signing_key_path).absolute?

Doorkeeper::OpenidConnect.configure do
  # One fixed identifier: the ID token's `iss` is built with no request, so a
  # request-derived issuer would never match what discovery advertises.
  issuer "#{Rails.env.production? ? 'https' : 'http'}://#{ENV.fetch('APP_HOST', 'localhost:3000')}"

  signing_key File.read(oidc_signing_key_path)

  # The same `sub` introspection sends, so a client can key a user either way.
  subject { |user, _application| user.id.to_s }

  resource_owner_from_access_token { |token| User.find_by(id: token.resource_owner_id) }

  auth_time_from_resource_owner { |user| user.current_sign_in_at }

  # `prompt=login` and `max_age` are how an RP forces re-authentication; without
  # this the gem raises instead of sending the user to the sign-in form.
  reauthenticate_resource_owner do |user, return_to|
    store_location_for user, return_to
    sign_out user
    redirect_to new_user_session_url
  end

  # There is no account picker — one session is one user — and the gem's default
  # raises a config error (500) instead of its own `account_selection_required`.
  select_account_for_resource_owner do |_user, _return_to|
    raise Doorkeeper::OpenidConnect::Errors::AccountSelectionRequired
  end

  # This session's own sign-in time, so `max_age` cannot be satisfied by a
  # fresher login on another device. The claim keeps the user's last login.
  auth_time_from_session { |session, _request| session[:auth_time] }

  # Values come from `User#introspection_claims`, the one whitelist; only the
  # two name claims need OIDC's names.
  claims do
    { email: :email, email_verified: :email_verified, given_name: :first_name,
      family_name: :last_name, updated_at: :updated_at, role: :role }.each do |name, source|
      claim(name, response: %i[id_token user_info]) { |user| user.introspection_claims[source] }
    end
  end
end
