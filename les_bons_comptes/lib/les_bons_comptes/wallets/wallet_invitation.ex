defmodule LesBonsComptes.Wallets.WalletInvitation do
  @moduledoc """
  Represents an invitation to join a shared wallet.
  An invited user must accept the invitation to become an active member.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "wallet_invitations" do
    field :status, :string, default: "pending"
    field :email, :string

    belongs_to :wallet, LesBonsComptes.Wallets.Wallet
    belongs_to :inviter, LesBonsComptes.Accounts.User
    belongs_to :invitee, LesBonsComptes.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @statuses ~w(pending accepted declined cancelled)

  @doc """
  Changeset for creating or updating an invitation.
  """
  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:email, :status])
    |> validate_required([:email, :status], message: "ce champ est obligatoire")
    |> validate_inclusion(:status, @statuses, message: "statut d'invitation invalide")
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/,
      message: "doit être une adresse email valide"
    )
    |> foreign_key_constraint(:wallet_id)
    |> foreign_key_constraint(:inviter_id)
    |> foreign_key_constraint(:invitee_id)
    |> unique_constraint([:wallet_id, :invitee_id],
      name: :wallet_invitations_unique_pending_wallet_invitee,
      message: "une invitation est déjà en attente pour cet utilisateur"
    )
  end
end
