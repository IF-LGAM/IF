defmodule LesBonsComptes.Accounts do
  @moduledoc """
  Contexte métier pour la gestion des comptes utilisateurs (Accounts).
  Centralise les interactions avec la base de données pour l'entité User.
  """

  import Ecto.Query, warn: false
  alias LesBonsComptes.Repo
  alias LesBonsComptes.Accounts.User

  @doc """
  Retourne la liste de tous les utilisateurs enregistrés en base.
  """
  def list_users do
    Repo.all(from u in User, order_by: [desc: u.inserted_at])
  end

  @doc """
  Récupère un utilisateur via son identifiant ID. Lève une erreur si introuvable.
  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Récupère un utilisateur via son identifiant ID. Retourne nil si introuvable.
  """
  def get_user(id), do: Repo.get(User, id)

  @doc """
  Récupère un utilisateur via son adresse email.
  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Authentifie un utilisateur avec son email et mot de passe en clair.
  Retourne `{:ok, user}` si le mot de passe correspond, ou `{:error, :unauthorized}` sinon.
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
  Crée un utilisateur en base à partir des attributs donnés.
  Retourne `{:ok, %User{}}` en cas de succès ou `{:error, %Ecto.Changeset{}}` si la validation échoue.
  """
  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Génère un changeset pour pré-remplir ou valider un formulaire utilisateur.
  """
  def change_user(%User{} = user, attrs \\ %{}) do
    User.changeset(user, attrs)
  end
end
