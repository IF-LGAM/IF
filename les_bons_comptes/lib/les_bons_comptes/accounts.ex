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
