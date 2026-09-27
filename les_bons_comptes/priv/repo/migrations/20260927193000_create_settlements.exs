defmodule LesBonsComptes.Repo.Migrations.CreateSettlements do
  use Ecto.Migration

  def change do
    create table(:settlements) do
      add :wallet_id, references(:wallets, on_delete: :delete_all), null: false
      add :from_id, references(:wallet_members, on_delete: :delete_all), null: false
      add :to_id, references(:wallet_members, on_delete: :delete_all), null: false
      add :amount, :decimal, precision: 10, scale: 2, null: false
      add :currency, :string, null: false, default: "EUR"
      add :settled_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:settlements, [:wallet_id])
    create index(:settlements, [:from_id])
    create index(:settlements, [:to_id])
    create unique_index(:settlements, [:wallet_id, :from_id, :to_id])
  end
end
