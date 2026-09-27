defmodule LesBonsComptes.Repo.Migrations.AddStatusToWallets do
  use Ecto.Migration

  def change do
    alter table(:wallets) do
      add :status, :string, default: "open", null: false
    end
  end
end
