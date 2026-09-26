defmodule LesBonsComptes.Expenses.Expense do
  @moduledoc """
  Schéma représentant une dépense effectuée au sein d'un porte-monnaie commun.
  Chaque dépense est reliée à un porte-monnaie, un compte dépenseur (membre payeur)
  et à l'utilisateur qui l'a créée.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias LesBonsComptes.Wallets.Wallet

  schema "expenses" do
    field :title, :string
    field :amount, :decimal
    field :date, :date
    field :description, :string
    field :currency, :string, default: "EUR"

    belongs_to :wallet, LesBonsComptes.Wallets.Wallet
    belongs_to :payer, LesBonsComptes.Wallets.WalletMember, foreign_key: :payer_id
    belongs_to :created_by, LesBonsComptes.Accounts.User, foreign_key: :created_by_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset pour la création ou modification d'une dépense.
  Valide le titre, le montant strictement positif, la date et les associations.
  """
  def changeset(expense, attrs) do
    expense
    |> cast(attrs, [
      :title,
      :amount,
      :date,
      :description,
      :currency,
      :payer_id,
      :wallet_id,
      :created_by_id
    ])
    |> validate_required([:title, :amount, :date, :wallet_id, :payer_id],
      message: "ce champ est obligatoire"
    )
    |> validate_length(:title,
      min: 2,
      max: 100,
      message: "doit contenir entre 2 et 100 caractères"
    )
    |> validate_length(:description, max: 500, message: "ne doit pas dépasser 500 caractères")
    |> validate_number(:amount, greater_than: 0, message: "doit être supérieur à 0")
    |> validate_inclusion(:currency, Wallet.supported_currencies(),
      message: "devise non supportée"
    )
    |> validate_not_in_future()
    |> foreign_key_constraint(:wallet_id)
    |> foreign_key_constraint(:payer_id)
    |> foreign_key_constraint(:created_by_id)
  end

  defp validate_not_in_future(changeset) do
    validate_change(changeset, :date, fn :date, date ->
      if Date.compare(date, Date.utc_today()) == :gt do
        [date: "la date ne peut pas être dans le futur"]
      else
        []
      end
    end)
  end
end
