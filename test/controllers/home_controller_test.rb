require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "anonymous visitor is sent to the sign-in form" do
    get "/"

    assert_redirected_to "/users/sign_in"
  end

  test "signed-in visitor sees who they are" do
    sign_in users(:ada)

    get "/"

    assert_response :success
    assert_select "body", /ada@example\.com/
  end

  test "signing in lands on the home page" do
    users(:ada).update!(password: "correct horse")

    post "/users/sign_in", params: { user: { email: "ada@example.com", password: "correct horse" } }

    assert_redirected_to "/"
  end
end
