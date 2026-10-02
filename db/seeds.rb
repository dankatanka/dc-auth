Doorkeeper::Application.create!(
  name: "admin",
  redirect_uri: "urn:ietf:wg:oauth:2.0:oob",
  scopes: "admin:users admin:apps",
  confidential: true
)

Doorkeeper::Application.create!(
  name: "sample-client",
  redirect_uri: "https://localhost:3001/oauth/callback",
  scopes: "read:profile",
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
