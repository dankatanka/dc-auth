require "test_helper"

module Api
  module V1
    class UsersControllerTest < ActionController::TestCase
      def authorize_with(application, scopes)
        token = Doorkeeper::AccessToken.create!(application: application, scopes: scopes, expires_in: 15.minutes)
        @request.headers["Authorization"] = "Bearer #{token.token}"
      end

      setup do
        @admin = oauth_applications(:admin)
        @ada = users(:ada)
      end

      test "a token without the scope is forbidden" do
        authorize_with(oauth_applications(:client), "read:profile")

        get :index

        assert_response :forbidden
      end

      test "index lists users" do
        authorize_with(@admin, "admin:users")

        get :index

        assert_response :success
        assert_equal [ @ada.id ], JSON.parse(response.body).map { |user| user["id"] }
      end

      test "show reads a single user" do
        authorize_with(@admin, "admin:users")

        get :show, params: { id: @ada.id }

        assert_response :success
        assert_equal "ada@example.com", JSON.parse(response.body)["email"]
      end

      test "create makes an unconfirmed user with the default role" do
        authorize_with(@admin, "admin:users")

        post :create, params: { user: {
          email: "new@example.com", first_name: "New", last_name: "User",
          password: "password-123", password_confirmation: "password-123"
        } }

        assert_response :created
        created = User.find_by(email: "new@example.com")
        assert_equal "customer", created.role
        assert_nil created.confirmed_at
      end

      test "update changes the role" do
        authorize_with(@admin, "admin:users")

        patch :update, params: { id: @ada.id, user: { role: "administrator" } }

        assert_response :success
        assert_equal "administrator", @ada.reload.role
      end

      test "an unknown role gets an error body, not a 500" do
        authorize_with(@admin, "admin:users")

        patch :update, params: { id: @ada.id, user: { role: "nope" } }

        assert_response :unprocessable_content
        assert JSON.parse(response.body)["errors"].present?
      end

      test "destroy_tokens revokes every token and grant" do
        token = Doorkeeper::AccessToken.create!(
          application: oauth_applications(:client), resource_owner_id: @ada.id,
          scopes: "read:profile", expires_in: 15.minutes
        )
        grant = Doorkeeper::AccessGrant.create!(
          application: oauth_applications(:client), resource_owner_id: @ada.id,
          redirect_uri: "https://client.example.com/callback", scopes: "read:profile", expires_in: 10.minutes
        )
        authorize_with(@admin, "admin:users")

        delete :destroy_tokens, params: { id: @ada.id }

        assert_response :no_content
        assert_not_nil token.reload.revoked_at
        assert_not_nil grant.reload.revoked_at
      end
    end
  end
end
