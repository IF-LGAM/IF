defmodule LesBonsComptes.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :name, :string
    field :email, :string
    field :password, :string

    timestamps()
  end

  @doc """
  Changeset pour la création et la modification d'un utilisateur.
  Applique les validations de présence, de format et de contraintes d'unicité.
  """
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :password])
    |> validate_required([:name, :email, :password], message: "ce champ est obligatoire")
    |> validate_length(:name, min: 2, max: 50, message: "doit contenir entre 2 et 50 caractères")
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/,
      message: "doit être une adresse email valide"
    )
    |> validate_length(:password, min: 6, message: "doit contenir au moins 6 caractères")
    |> unique_constraint(:email, message: "cette adresse email est déjà enregistrée")
  end
end
