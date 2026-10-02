require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "introspection_claims is exactly the documented whitelist" do
    assert_equal %i[sub email email_verified first_name last_name updated_at role],
      users(:ada).introspection_claims.keys
  end

  test "sub is a string, as RFC 7662 and the documented response both say" do
    assert_equal users(:ada).id.to_s, users(:ada).introspection_claims[:sub]
  end

  test "role enum reads and stores its own string value" do
    ada = users(:ada)

    assert_equal "staff", ada.role
    assert_predicate ada, :staff?
  end

  test "changing the password revokes every access token and access grant" do
    ada = users(:ada)
    app = oauth_applications(:client)
    token = Doorkeeper::AccessToken.create!(
      application: app, resource_owner_id: ada.id, scopes: "read:profile", expires_in: 15.minutes
    )
    grant = Doorkeeper::AccessGrant.create!(
      application: app, resource_owner_id: ada.id, redirect_uri: app.redirect_uri,
      scopes: "read:profile", expires_in: 10.minutes
    )

    ada.update!(password: "new-password-123", password_confirmation: "new-password-123")

    assert_not_nil token.reload.revoked_at
    assert_not_nil grant.reload.revoked_at
  end

  test "a non-password change leaves tokens alone" do
    ada = users(:ada)
    token = Doorkeeper::AccessToken.create!(
      application: oauth_applications(:client), resource_owner_id: ada.id,
      scopes: "read:profile", expires_in: 15.minutes
    )

    ada.update!(first_name: "Augusta")

    assert_nil token.reload.revoked_at
  end
end
