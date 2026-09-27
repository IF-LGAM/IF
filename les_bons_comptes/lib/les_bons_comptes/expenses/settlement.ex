defmodule LesBonsComptes.Expenses.Settlement do
  @moduledoc """
  Schéma représentant un virement/remboursement validé et enregistré entre deux membres.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "settlements" do
    field :amount, :decimal
    field :currency, :string, default: "EUR"
    field :settled_at, :utc_datetime

    belongs_to :wallet, LesBonsComptes.Wallets.Wallet
    belongs_to :from, LesBonsComptes.Wallets.WalletMember, foreign_key: :from_id
    belongs_to :to, LesBonsComptes.Wallets.WalletMember, foreign_key: :to_id
    belongs_to :from_member, LesBonsComptes.Wallets.WalletMember, foreign_key: :from_id, define_field: false
    belongs_to :to_member, LesBonsComptes.Wallets.WalletMember, foreign_key: :to_id, define_field: false

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset pour la persistance d'un remboursement.
  """
  def changeset(settlement, attrs) do
    settlement
    |> cast(attrs, [:wallet_id, :from_id, :to_id, :amount, :currency, :settled_at])
    |> validate_required([:wallet_id, :from_id, :to_id, :amount, :currency, :settled_at],
      message: "ce champ est obligatoire"
    )
    |> validate_number(:amount, greater_than: 0, message: "doit être supérieur à 0")
    |> foreign_key_constraint(:wallet_id)
    |> foreign_key_constraint(:from_id)
    |> foreign_key_constraint(:to_id)
    |> unique_constraint([:wallet_id, :from_id, :to_id],
      message: "ce virement a déjà été enregistré"
    )
  end
end
