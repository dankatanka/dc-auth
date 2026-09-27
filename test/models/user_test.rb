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
end
