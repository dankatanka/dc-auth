class AddOidcScopesToApplications < ActiveRecord::Migration[8.1]
  # The live model can change under a migration; this snapshot of the table cannot.
  class Application < ActiveRecord::Base
    self.table_name = "oauth_applications"
  end

  OIDC_SCOPES = %w[openid profile email].freeze
  RETIRED_SCOPES = %w[read:profile].freeze

  # The admin API cannot update an app's scopes, so this is the only way an
  # existing client gains OIDC; the retired scope must go with it.
  def up
    Application.find_each do |application|
      scopes = (application.scopes.to_s.split - RETIRED_SCOPES) | OIDC_SCOPES
      application.update_columns(scopes: scopes.join(" "))
    end
  end

  def down
    Application.find_each do |application|
      application.update_columns(scopes: (application.scopes.to_s.split - OIDC_SCOPES).join(" "))
    end
  end
end
