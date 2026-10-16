defmodule LesBonsComptes.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :name, :string
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true

    timestamps()
  end

  @doc """
  Changeset for user registration and validation.
  Applies presence, format, and uniqueness validations, and securely hashes the password.
  """
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :password])
    |> validate_required([:name, :email, :password], message: "ce champ est obligatoire")
    |> validate_length(:name, min: 2, max: 50, message: "doit contenir entre 2 et 50 caractères")
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/,
      message: "doit être une adresse email valide"
    )
    |> validate_length(:password, min: 6, max: 72, message: "doit contenir au moins 6 caractères")
    |> unique_constraint(:email, message: "un compte existe déjà")
    |> hash_password()
  end

  defp hash_password(changeset) do
    password = get_change(changeset, :password)

    if password && changeset.valid? do
      changeset
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  Verifies if the given password matches the stored hash.
  Protects against timing attacks.
  """
  def valid_password?(%__MODULE__{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and is_binary(password) do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end
end
