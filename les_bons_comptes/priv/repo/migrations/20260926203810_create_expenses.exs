defmodule LesBonsComptes.Repo.Migrations.CreateExpenses do
  use Ecto.Migration

  def change do
    create table(:expenses) do
      add :title, :string, null: false
      add :amount, :decimal, precision: 10, scale: 2, null: false
      add :date, :date, null: false
      add :description, :string
      add :currency, :string, null: false, default: "EUR"
      add :wallet_id, references(:wallets, on_delete: :delete_all), null: false
      add :payer_id, references(:wallet_members, on_delete: :delete_all), null: false
      add :created_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:expenses, [:wallet_id])
    create index(:expenses, [:payer_id])
    create index(:expenses, [:created_by_id])
    create index(:expenses, [:wallet_id, :date])
  end
end
