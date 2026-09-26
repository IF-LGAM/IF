defmodule LesBonsComptes.Wallets.WalletMember do
  @moduledoc """
  Représente un participant / membre d'un porte-monnaie commun.
  Un membre peut être associé à un compte utilisateur enregistré (`user_id`),
  ou être un participant sans compte créé directement avec son nom.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "wallet_members" do
    field :name, :string
    field :email, :string
    field :role, :string, default: "member"

    belongs_to :wallet, LesBonsComptes.Wallets.Wallet
    belongs_to :user, LesBonsComptes.Accounts.User

    has_many :expenses, LesBonsComptes.Expenses.Expense,
      foreign_key: :payer_id,
      on_delete: :delete_all

    timestamps()
  end

  @roles ~w(owner admin member)

  @doc """
  Changeset pour la création ou modification d'un membre de porte-monnaie.
  """
  def changeset(member, attrs) do
    member
    |> cast(attrs, [:name, :email, :role])
    |> validate_required([:name, :email, :role], message: "ce champ est obligatoire")
    |> validate_length(:name, min: 1, max: 50, message: "doit contenir entre 1 et 50 caractères")
    |> validate_inclusion(:role, @roles, message: "rôle invalide")
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/,
      message: "doit être une adresse email valide"
    )
    |> foreign_key_constraint(:wallet_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:wallet_id, :user_id],
      name: :wallet_members_wallet_id_user_id_index,
      message: "cet utilisateur fait déjà partie du porte-monnaie"
    )
  end
end
