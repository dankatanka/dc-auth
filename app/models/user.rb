class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :recoverable, :confirmable,
         :trackable, :lockable, :validatable

  enum :role, %i[customer administrator].index_with(&:to_s), validate: true, scopes: false

  validates :first_name, :last_name, presence: true

  has_many :access_grants, class_name: "Doorkeeper::AccessGrant",
           foreign_key: :resource_owner_id, dependent: :destroy, inverse_of: false
  has_many :access_tokens, class_name: "Doorkeeper::AccessToken",
           foreign_key: :resource_owner_id, dependent: :destroy, inverse_of: false

  after_update :revoke_tokens!, if: :saved_change_to_encrypted_password?

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

  def revoke_tokens!
    revoked_at = Time.current
    access_tokens.update_all(revoked_at: revoked_at)
    access_grants.update_all(revoked_at: revoked_at)
  end
end
