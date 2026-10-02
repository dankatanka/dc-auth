require "test_helper"
require "base64"
require "digest"

class TokenValidationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def authorization_code
    verifier = SecureRandom.urlsafe_base64(64)
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
    params = {
      client_id: @client.uid,
      redirect_uri: @client.redirect_uri,
      response_type: "code",
      scope: "read:profile",
      state: "proof-state",
      code_challenge: challenge,
      code_challenge_method: "S256"
    }

    get "/oauth/authorize", params: params
    assert_response :success

    post "/oauth/authorize", params: params
    assert_response :redirect

    [ verifier, Rack::Utils.parse_query(URI.parse(response.location).query)["code"] ]
  end

  def access_token_for(verifier, code)
    post "/oauth/token", params: {
      grant_type: "authorization_code",
      code: code,
      redirect_uri: @client.redirect_uri,
      client_id: @client.uid,
      client_secret: @client.secret,
      code_verifier: verifier
    }
    assert_response :success

    JSON.parse(response.body)["access_token"]
  end

  def introspect(token)
    post "/oauth/introspect", params: { token: token },
      headers: { "Authorization" => "Basic #{Base64.strict_encode64("#{@verifier.uid}:#{@verifier.secret}")}" }
    assert_response :success

    JSON.parse(response.body)
  end

  setup do
    @user = users(:ada)
    @client = oauth_applications(:client)
    @verifier = oauth_applications(:verifier)
  end

  test "a second app validates a real user token end to end" do
    sign_in @user

    verifier, code = authorization_code
    assert code.present?

    token = access_token_for(verifier, code)
    assert token.present?

    claims = introspect(token)
    assert claims["active"], claims.inspect
    assert_equal @user.id.to_s, claims["sub"]
    assert_equal @user.email, claims["email"]
    assert_equal "administrator", claims["role"]
    assert_equal true, claims["email_verified"]
  end
end
