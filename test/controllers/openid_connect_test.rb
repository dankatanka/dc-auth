require "test_helper"
require "base64"
require "digest"
require "nokogiri"

class OpenidConnectTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def authorize_with_code(scope: "openid profile email", nonce: "oidc-nonce")
    verifier = SecureRandom.urlsafe_base64(64)
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)

    get "/oauth/authorize", params: {
      client_id: @client.uid,
      redirect_uri: @client.redirect_uri,
      response_type: "code",
      scope: scope,
      state: "oidc-state",
      nonce: nonce,
      code_challenge: challenge,
      code_challenge_method: "S256"
    }
    assert_response :success

    forms = Nokogiri::HTML(response.body).css("form[action='/oauth/authorize']")
    authorize_form = forms.find { |form| form.at_css("input[name='_method']").nil? }
    post "/oauth/authorize", params: authorize_form.css("input").to_h { |input| [ input["name"], input["value"] ] }
    assert_response :redirect

    [ verifier, Rack::Utils.parse_query(URI.parse(response.location).query)["code"] ]
  end

  def token_response(verifier, code)
    post "/oauth/token", params: {
      grant_type: "authorization_code",
      code: code,
      redirect_uri: @client.redirect_uri,
      client_id: @client.uid,
      client_secret: "client-secret",
      code_verifier: verifier
    }
    assert_response :success

    JSON.parse(response.body)
  end

  def expected_issuer
    "http://#{ENV.fetch('APP_HOST', 'localhost:3000')}"
  end

  # Verified against the endpoint's own JWKS, because that is what an RP does.
  def decoded_id_token(id_token)
    get "/oauth/discovery/keys"
    assert_response :success
    jwk = JSON.parse(response.body).fetch("keys").first.symbolize_keys

    JWT.decode(id_token, JWT::JWK.import(jwk).public_key, true, algorithm: "RS256").first
  end

  setup do
    @user = users(:ada)
    @client = oauth_applications(:client)
  end

  test "the discovery document describes the provider" do
    get "/.well-known/openid-configuration"
    assert_response :success

    document = JSON.parse(response.body)
    assert_equal expected_issuer, document["issuer"]
    assert_equal "http://www.example.com/oauth/discovery/keys", document["jwks_uri"]
    assert_equal "http://www.example.com/oauth/userinfo", document["userinfo_endpoint"]
    assert_includes document["claims_supported"], "given_name"
    assert_includes document["claims_supported"], "family_name"
    assert_includes document["claims_supported"], "role"
  end

  test "the authorization code flow signs an ID token with the published JWKS" do
    sign_in @user
    verifier, code = authorize_with_code

    claims = decoded_id_token(token_response(verifier, code).fetch("id_token"))

    # The issuer is fixed, so the token exchange agrees with discovery.
    assert_equal expected_issuer, claims["iss"]
    assert_equal @client.uid, claims["aud"]
    assert_equal @user.id.to_s, claims["sub"]
    assert_equal "oidc-nonce", claims["nonce"]
    assert_equal @user.email, claims["email"]
    assert_equal true, claims["email_verified"]
    assert_equal @user.first_name, claims["given_name"]
    assert_equal @user.last_name, claims["family_name"]
    assert_equal @user.role, claims["role"]
    assert_equal @user.updated_at.to_i, claims["updated_at"]
  end

  test "userinfo reports the introspection claims under their OIDC names" do
    sign_in @user
    verifier, code = authorize_with_code
    token = token_response(verifier, code).fetch("access_token")

    get "/oauth/userinfo", headers: { "Authorization" => "Bearer #{token}" }
    assert_response :success

    claims = JSON.parse(response.body)
    assert_equal @user.id.to_s, claims["sub"]
    assert_equal @user.email, claims["email"]
    assert_equal @user.first_name, claims["given_name"]
    assert_equal @user.last_name, claims["family_name"]
  end

  test "claims follow the scopes the client requested" do
    sign_in @user
    verifier, code = authorize_with_code(scope: "openid")

    claims = decoded_id_token(token_response(verifier, code).fetch("id_token"))

    assert_equal @user.id.to_s, claims["sub"]
    assert_nil claims["email"]
    assert_nil claims["given_name"]
  end

  test "prompt=login signs the user out and sends them to the sign-in form" do
    sign_in @user

    get "/oauth/authorize", params: {
      client_id: @client.uid,
      redirect_uri: @client.redirect_uri,
      response_type: "code",
      scope: "openid",
      prompt: "login"
    }

    assert_redirected_to "/users/sign_in"
  end

  test "prompt=login on a signed-out request is satisfied by one sign-in" do
    @user.update!(password: "correct horse")

    get "/oauth/authorize", params: {
      client_id: @client.uid,
      redirect_uri: @client.redirect_uri,
      response_type: "code",
      scope: "openid",
      prompt: "login"
    }
    assert_redirected_to "/users/sign_in"

    post "/users/sign_in", params: { user: { email: @user.email, password: "correct horse" } }
    refute_includes response.location.to_s, "prompt=login"

    follow_redirect!
    assert_response :success
  end

  test "prompt=select_account answers account_selection_required, not a 500" do
    sign_in @user

    get "/oauth/authorize", params: {
      client_id: @client.uid,
      redirect_uri: @client.redirect_uri,
      response_type: "code",
      scope: "openid",
      prompt: "select_account"
    }

    assert_response :redirect
    assert_equal "account_selection_required",
      Rack::Utils.parse_query(URI.parse(response.location).query)["error"]
  end

  # The password form, not `sign_in`: this is the path an RP's `max_age` measures.
  test "max_age is measured against this session, not the user's last login" do
    @user.update!(password: "correct horse")
    post "/users/sign_in", params: { user: { email: @user.email, password: "correct horse" } }

    params = {
      client_id: @client.uid,
      redirect_uri: @client.redirect_uri,
      response_type: "code",
      scope: "openid"
    }

    get "/oauth/authorize", params: params.merge(max_age: 3600)
    assert_response :success

    travel 10.minutes do
      get "/oauth/authorize", params: params.merge(max_age: 60)
    end
    assert_redirected_to "/users/sign_in"
  end

  # Devise's own `sign_in` (password reset, registration) calls Warden's
  # `set_user`, not the authentication path, so that path must stamp it too.
  test "max_age is stamped on a session Devise signs in without authenticating" do
    raw, digest = Devise.token_generator.generate(User, :reset_password_token)
    @user.update!(reset_password_token: digest, reset_password_sent_at: Time.current)

    put "/users/password", params: { user: {
      reset_password_token: raw,
      password: "battery staple",
      password_confirmation: "battery staple"
    } }

    get "/oauth/authorize", params: {
      client_id: @client.uid,
      redirect_uri: @client.redirect_uri,
      response_type: "code",
      scope: "openid",
      max_age: 3600
    }

    assert_response :success
  end

  test "every introspection claim is exposed over OIDC under its own name" do
    renames = { first_name: :given_name, last_name: :family_name }
    expected = @user.introspection_claims.keys.excluding(:sub).map { |name| renames.fetch(name, name) }

    assert_equal expected, Doorkeeper::OpenidConnect.configuration.claims.to_h.keys
  end
end
