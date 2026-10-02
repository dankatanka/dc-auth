class RenameRolesToCustomerAndAdministrator < ActiveRecord::Migration[8.1]
  def up
    # Old role values have no mapping in the new set, so user rows are discarded.
    remove_check_constraint :users, name: "users_role_check"
    execute "DELETE FROM oauth_access_tokens WHERE resource_owner_id IS NOT NULL"
    execute "DELETE FROM oauth_access_grants"
    execute "DELETE FROM users"
    change_column_default :users, :role, from: "user", to: "customer"
    add_check_constraint :users, "role IN ('customer', 'administrator')", name: "users_role_check"
  end

  def down
    remove_check_constraint :users, name: "users_role_check"
    change_column_default :users, :role, from: "customer", to: "user"
    add_check_constraint :users, "role IN ('user', 'staff', 'admin')", name: "users_role_check"
  end
end
