defmodule LesBonsComptes.Repo.Migrations.AlterUsersTableUseHashedPassword do
  use Ecto.Migration

  def change do
    alter table(:users) do
      remove :password, :string
      add :hashed_password, :string, null: false
    end
  end
end
