require "test_helper"

module Api
  module V1
    class ApplicationsControllerTest < ActionController::TestCase
      def authorize_with(application, scopes)
        token = Doorkeeper::AccessToken.create!(application: application, scopes: scopes, expires_in: 15.minutes)
        @request.headers["Authorization"] = "Bearer #{token.token}"
      end

      setup do
        @admin = oauth_applications(:admin)
        authorize_with(@admin, "admin:apps")
      end

      test "a token without the scope is forbidden" do
        authorize_with(oauth_applications(:client), "read:profile")

        get :index

        assert_response :forbidden
      end

      test "index lists applications without their secrets" do
        get :index

        assert_response :success
        body = JSON.parse(response.body)
        assert body.any? { |application| application["uid"] == @admin.uid }
        assert_not body.any? { |application| application.key?("secret") }
      end

      test "create returns the secret once" do
        post :create, params: { application: {
          name: "new-app", redirect_uri: "https://new.example.com/callback", scopes: "read:profile"
        } }

        assert_response :created
        assert JSON.parse(response.body)["secret"].present?
      end

      test "create rejects an unconfigured scope" do
        post :create, params: { application: {
          name: "bad-app", redirect_uri: "https://bad.example.com/callback", scopes: "admin:everything"
        } }

        assert_response :unprocessable_content
        assert JSON.parse(response.body)["errors"].present?
      end

      test "destroy removes the application" do
        doomed = Doorkeeper::Application.create!(
          name: "doomed", redirect_uri: "urn:ietf:wg:oauth:2.0:oob", scopes: "read:profile"
        )

        delete :destroy, params: { id: doomed.id }

        assert_response :no_content
        assert_nil Doorkeeper::Application.find_by(id: doomed.id)
      end
    end
  end
end
