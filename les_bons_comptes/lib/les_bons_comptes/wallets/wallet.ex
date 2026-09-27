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
    field :status, :string, default: "open"

    belongs_to :creator, LesBonsComptes.Accounts.User, foreign_key: :creator_id
    has_many :members, LesBonsComptes.Wallets.WalletMember, on_delete: :delete_all
    has_many :invitations, LesBonsComptes.Wallets.WalletInvitation, on_delete: :delete_all
    has_many :expenses, LesBonsComptes.Expenses.Expense, on_delete: :delete_all

    timestamps()
  end

  @currencies ~w(EUR USD GBP CHF CAD)
  @statuses ~w(open pending_settlement closed)

  @doc """
  Changeset pour la création ou modification d'un porte-monnaie commun.
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
  Retourne la liste des devises supportées.
  """
  def supported_currencies, do: @currencies

  @doc """
  Retourne les options de devise formatées pour les select HTML.
  """
  def currency_options, do: @currency_options

  @doc """
  Retourne la liste des statuts supportés.
  """
  def supported_statuses, do: @statuses

  @doc """
  Indique si le porte-monnaie est clos (Étape 3 : Clôturé).
  """
  def closed?(%__MODULE__{status: "closed"}), do: true
  def closed?(_), do: false

  @doc """
  Indique si le porte-monnaie est en attente de virements (Étape 2).
  """
  def pending_settlement?(%__MODULE__{status: "pending_settlement"}), do: true
  def pending_settlement?(_), do: false

  @doc """
  Indique si le porte-monnaie est ouvert aux déclarations (Étape 1).
  """
  def open?(%__MODULE__{status: "open"}), do: true
  def open?(%__MODULE__{status: status}) when status in ["pending_settlement", "closed"], do: false
  def open?(%__MODULE__{}), do: true
  def open?(_), do: false

  @doc """
  Retourne le numéro d'étape actuel (1, 2 ou 3).
  """
  def step_number(%__MODULE__{status: "pending_settlement"}), do: 2
  def step_number(%__MODULE__{status: "closed"}), do: 3
  def step_number(_), do: 1

  @doc """
  Retourne le libellé utilisateur de l'étape courante.
  """
  def status_label(%__MODULE__{status: "pending_settlement"}), do: "Attente des virements"
  def status_label(%__MODULE__{status: "closed"}), do: "Clôturé"
  def status_label(_), do: "Déclarations en cours"

  @doc """
  Indique si le porte-monnaie peut être rouvert vers l'étape de déclarations.
  La clôture étant définitive, un porte-monnaie clos ne peut jamais être rouvert.
  """
  def reopenable?(%__MODULE__{status: "closed"}), do: false
  def reopenable?(%__MODULE__{status: "pending_settlement"}), do: true
  def reopenable?(_), do: false
end
