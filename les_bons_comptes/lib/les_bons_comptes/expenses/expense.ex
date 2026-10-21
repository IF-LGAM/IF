defmodule LesBonsComptes.Expenses.Expense do
  @moduledoc """
  Schema representing an expense recorded within a shared wallet.
  Each expense is linked to a wallet, a payer member account,
  and the user who created it.
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
  Changeset for creating or modifying an expense.
  Validates title, strictly positive amount, date, and associations.
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
    # =========================================================================
    # TODO TP (Étape 3.1) : Définir les validations Ecto pour une dépense
    # -------------------------------------------------------------------------
    # En Elixir, un changeset est une transformation de données par tuyaux (|>).
    # Décommentez et comprenez le pipeline de validation ci-dessous :
    #
    # 1. Rendre obligatoires :title, :amount, :date, :wallet_id, :payer_id :
    # |> validate_required([:title, :amount, :date, :wallet_id, :payer_id],
    #   message: "ce champ est obligatoire"
    # )
    #
    # 2. Valider la longueur de :title (entre 2 et 100 caractères) :
    # |> validate_length(:title, min: 2, max: 100, message: "doit contenir entre 2 et 100 caractères")
    #
    # 3. Valider que :amount est strictement positif (> 0) :
    # |> validate_number(:amount, greater_than: 0, message: "doit être supérieur à 0")
    #
    # 4. Valider que la devise et la date sont cohérentes :
    # |> validate_inclusion(:currency, Wallet.supported_currencies(), message: "devise non supportée")
    # |> validate_not_in_future()
    # =========================================================================
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
