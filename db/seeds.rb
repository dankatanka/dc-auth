Doorkeeper::Application.create!(
  name: "admin",
  redirect_uri: "urn:ietf:wg:oauth:2.0:oob",
  scopes: "admin:users admin:apps openid profile email",
  confidential: true
)

dashboard = Doorkeeper::Application.create!(
  name: "dashboard",
  redirect_uri: "http://localhost:3000/oauth/callback",
  scopes: "admin:users admin:apps openid profile email",
  confidential: true
)

# The secret is hashed at rest, so this is the only place it is readable.
puts "dashboard: AUTH_SERVICE_CLIENT_ID=#{dashboard.uid} AUTH_SERVICE_CLIENT_SECRET=#{dashboard.plaintext_secret}"

Doorkeeper::Application.create!(
  name: "sample-client",
  redirect_uri: "https://localhost:3001/oauth/callback",
  scopes: "openid profile email",
  confidential: true
)

{ "administrator@example.com" => "administrator", "customer@example.com" => "customer" }.each do |email, role|
  User.create!(
    email: email,
    first_name: email.split("@").first.capitalize,
    last_name: "Example",
    role: role,
    password: "password123",
    password_confirmation: "password123",
    confirmed_at: Time.current
  )
end
