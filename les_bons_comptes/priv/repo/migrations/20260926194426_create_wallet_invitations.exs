defmodule LesBonsComptes.Repo.Migrations.CreateWalletInvitations do
  use Ecto.Migration

  def change do
    create table(:wallet_invitations) do
      add :status, :string, null: false, default: "pending"
      add :email, :string, null: false
      add :wallet_id, references(:wallets, on_delete: :delete_all), null: false
      add :inviter_id, references(:users, on_delete: :nilify_all), null: false
      add :invitee_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:wallet_invitations, [:wallet_id])
    create index(:wallet_invitations, [:inviter_id])
    create index(:wallet_invitations, [:invitee_id])
    create index(:wallet_invitations, [:invitee_id, :status])

    create unique_index(:wallet_invitations, [:wallet_id, :invitee_id],
             where: "status = 'pending'",
             name: :wallet_invitations_unique_pending_wallet_invitee
           )
  end
end
