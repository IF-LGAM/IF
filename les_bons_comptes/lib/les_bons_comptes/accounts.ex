defmodule LesBonsComptes.Accounts do
  @moduledoc """
  Business context for user account management (Accounts).
  Centralizes database interactions for the User entity.
  """

  import Ecto.Query, warn: false
  alias LesBonsComptes.Repo
  alias LesBonsComptes.Accounts.User

  @doc """
  Returns the list of all registered users in the database.
  """
  def list_users do
    Repo.all(from u in User, order_by: [desc: u.inserted_at])
  end

  @doc """
  Fetches a single user by ID. Raises if the user does not exist.
  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Fetches a single user by ID. Returns nil if the user does not exist.
  """
  def get_user(id), do: Repo.get(User, id)

  @doc """
  Fetches a single user by email address.
  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Authenticates a user with email and plain password.
  Returns `{:ok, user}` if the password matches, or `{:error, :unauthorized}` otherwise.
  """
  def authenticate_user(email, password) when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)

    if User.valid_password?(user, password) do
      {:ok, user}
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Creates a user in the database with the given attributes.
  Returns `{:ok, %User{}}` on success or `{:error, %Ecto.Changeset{}}` if validation fails.
  """
  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns a changeset for tracking or validating user changes.
  """
  def change_user(%User{} = user, attrs \\ %{}) do
    User.changeset(user, attrs)
  end
end
