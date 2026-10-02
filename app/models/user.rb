class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :recoverable, :confirmable,
         :trackable, :lockable, :validatable

  # Positional form is required on Rails 8; the hash maps names to their own
  # string values, which the plain array form does not — it serializes integers
  # into the string column while still reading back the name.
  enum :role, %i[user staff admin].index_with(&:to_s), validate: true, scopes: false

  validates :first_name, :last_name, presence: true

  has_many :access_grants, class_name: "Doorkeeper::AccessGrant",
           foreign_key: :resource_owner_id, dependent: :destroy, inverse_of: false
  has_many :access_tokens, class_name: "Doorkeeper::AccessToken",
           foreign_key: :resource_owner_id, dependent: :destroy, inverse_of: false

  after_update :revoke_tokens_on_password_change, if: :saved_change_to_encrypted_password?

  def introspection_claims
    {
      sub: id.to_s,
      email: email,
      email_verified: confirmed_at.present?,
      first_name: first_name,
      last_name: last_name,
      updated_at: updated_at.to_i,
      role: role
    }
  end

  private

  def revoke_tokens_on_password_change
    revoked_at = Time.current
    access_tokens.update_all(revoked_at: revoked_at)
    access_grants.update_all(revoked_at: revoked_at)
  end
end
