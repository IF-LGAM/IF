defmodule LesBonsComptes.Wallets.Wallet do
  @moduledoc """
  Represents a shared wallet (Tricount).
  Holds an initial owner/creator, title, optional description,
  currency, and participant list (members).
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "wallets" do
    field :name, :string
    field :description, :string
    field :currency, :string, default: "EUR"
    field :status, :string, default: "open"
    field :invitation, :any, virtual: true

    belongs_to :creator, LesBonsComptes.Accounts.User, foreign_key: :creator_id
    has_many :members, LesBonsComptes.Wallets.WalletMember, on_delete: :delete_all
    has_many :invitations, LesBonsComptes.Wallets.WalletInvitation, on_delete: :delete_all
    has_many :expenses, LesBonsComptes.Expenses.Expense, on_delete: :delete_all

    timestamps()
  end

  @currencies ~w(EUR USD GBP CHF CAD)
  @statuses ~w(open pending_settlement closed)

  @doc """
  Changeset for creating or modifying a shared wallet.
  """
  def changeset(wallet, attrs) do
    wallet
    |> cast(attrs, [:name, :description, :currency, :status])
    |> validate_required([:name, :currency], message: "ce champ est obligatoire")
    |> validate_length(:name,
      min: 2,
      max: 100,
      message: "doit contenir entre 2 et 100 caractères"
    )
    |> validate_length(:description, max: 500, message: "ne doit pas dépasser 500 caractères")
    |> validate_inclusion(:currency, @currencies, message: "devise non supportée")
    |> validate_inclusion(:status, @statuses, message: "statut invalide")
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
  Returns the list of supported currencies.
  """
  def supported_currencies, do: @currencies

  @doc """
  Returns currency options formatted for HTML selects.
  """
  def currency_options, do: @currency_options

  @doc """
  Returns the list of supported statuses.
  """
  def supported_statuses, do: @statuses

  @doc """
  Indicates whether the wallet is closed (Step 3: Closed).
  """
  def closed?(%__MODULE__{status: "closed"}), do: true
  def closed?(_), do: false

  @doc """
  Indicates whether the wallet is pending settlement (Step 2).
  """
  def pending_settlement?(%__MODULE__{status: "pending_settlement"}), do: true
  def pending_settlement?(_), do: false

  @doc """
  Indicates whether the wallet is open for declarations (Step 1).
  """
  def open?(%__MODULE__{status: "open"}), do: true

  def open?(%__MODULE__{status: status}) when status in ["pending_settlement", "closed"],
    do: false

  def open?(%__MODULE__{}), do: true
  def open?(_), do: false

  @doc """
  Returns the current step number (1, 2, or 3).
  """
  def step_number(%__MODULE__{status: "pending_settlement"}), do: 2
  def step_number(%__MODULE__{status: "closed"}), do: 3
  def step_number(_), do: 1

  @doc """
  Returns the user-facing label for the current step.
  """
  def status_label(%__MODULE__{status: "pending_settlement"}), do: "Attente des virements"
  def status_label(%__MODULE__{status: "closed"}), do: "Clôturé"
  def status_label(_), do: "Déclarations en cours"

  @doc """
  Indicates whether the wallet can be reopened to the declarations step.
  Closure being permanent, a closed wallet can never be reopened.
  """
  def reopenable?(%__MODULE__{status: "closed"}), do: false
  def reopenable?(%__MODULE__{status: "pending_settlement"}), do: true
  def reopenable?(_), do: false
end
