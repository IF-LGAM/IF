defmodule LesBonsComptes.Wallets.Wallet do
  @moduledoc """
  Représente un porte-monnaie commun (Tricount).
  Possède un créateur (propriétaire initial), un titre, une description optionnelle,
  une devise et une liste de participants (membres).
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "wallets" do
    field :name, :string
    field :description, :string
    field :currency, :string, default: "EUR"

    belongs_to :creator, LesBonsComptes.Accounts.User, foreign_key: :creator_id
    has_many :members, LesBonsComptes.Wallets.WalletMember, on_delete: :delete_all
    has_many :invitations, LesBonsComptes.Wallets.WalletInvitation, on_delete: :delete_all
    has_many :expenses, LesBonsComptes.Expenses.Expense, on_delete: :delete_all

    timestamps()
  end

  @currencies ~w(EUR USD GBP CHF CAD)

  @doc """
  Changeset pour la création ou modification d'un porte-monnaie commun.
  """
  def changeset(wallet, attrs) do
    wallet
    |> cast(attrs, [:name, :description, :currency])
    |> validate_required([:name, :currency], message: "ce champ est obligatoire")
    |> validate_length(:name,
      min: 2,
      max: 100,
      message: "doit contenir entre 2 et 100 caractères"
    )
    |> validate_length(:description, max: 500, message: "ne doit pas dépasser 500 caractères")
    |> validate_inclusion(:currency, @currencies, message: "devise non supportée")
    |> foreign_key_constraint(:creator_id)
  end

  @currency_options [
    {"Euro (€)", "EUR"},
    {"Dollar américain ($)", "USD"},
    {"Livre sterling (£)", "GBP"},
    {"Franc suisse (CHF)", "CHF"},
    {"Dollar canadien ($)", "CAD"}
  ]

  @doc """
  Retourne la liste des devises supportées.
  """
  def supported_currencies, do: @currencies

  @doc """
  Retourne les options de devise formatées pour les select HTML.
  """
  def currency_options, do: @currency_options
end
