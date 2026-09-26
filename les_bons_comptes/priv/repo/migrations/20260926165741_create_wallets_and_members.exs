defmodule LesBonsComptes.Repo.Migrations.CreateWalletsAndMembers do
  use Ecto.Migration

  def change do
    create table(:wallets) do
      add :name, :string, null: false
      add :description, :text
      add :currency, :string, default: "EUR", null: false
      add :creator_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:wallets, [:creator_id])

    create table(:wallet_members) do
      add :wallet_id, references(:wallets, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :name, :string, null: false
      add :email, :string
      add :role, :string, default: "member", null: false

      timestamps()
    end

    create index(:wallet_members, [:wallet_id])
    create index(:wallet_members, [:user_id])

    create unique_index(:wallet_members, [:wallet_id, :user_id],
             where: "user_id IS NOT NULL",
             name: :wallet_members_wallet_id_user_id_index
           )
  end
end
