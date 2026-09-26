defmodule LesBonsComptes.Wallets do
  @moduledoc """
  Contexte métier pour la gestion des porte-monnaies communs (Wallets / Tricounts).
  Gère la création du porte-monnaie, l'association des participants, l'initialisation
  des droits (propriétaire) et les validations métier associées.
  """

  import Ecto.Query, warn: false
  alias LesBonsComptes.Repo
  alias LesBonsComptes.Accounts
  alias LesBonsComptes.Accounts.User
  alias LesBonsComptes.Wallets.{Wallet, WalletMember}

  @doc """
  Retourne tous les porte-monnaies auxquels l'utilisateur participe
  (soit comme créateur, soit comme membre enregistré).
  """
  def list_wallets_for_user(user_id) when is_integer(user_id) do
    from(w in Wallet,
      left_join: m in assoc(w, :members),
      where: w.creator_id == ^user_id or m.user_id == ^user_id,
      distinct: true,
      order_by: [desc: w.inserted_at],
      preload: [:creator, :members]
    )
    |> Repo.all()
  end

  @doc """
  Récupère un porte-monnaie par son ID avec ses membres et son créateur. Lève si introuvable.
  """
  def get_wallet!(id) do
    Wallet
    |> Repo.get!(id)
    |> Repo.preload([:creator, members: from(m in WalletMember, order_by: [asc: m.id])])
  end

  @doc """
  Récupère un porte-monnaie par son ID. Retourne nil si introuvable.
  """
  def get_wallet(id) do
    case Repo.get(Wallet, id) do
      nil ->
        nil

      wallet ->
        Repo.preload(wallet, [:creator, members: from(m in WalletMember, order_by: [asc: m.id])])
    end
  end

  @doc """
  Initialise un changeset pour un nouveau porte-monnaie.
  """
  def change_wallet(%Wallet{} = wallet, attrs \\ %{}) do
    Wallet.changeset(wallet, attrs)
  end

  @doc """
  Crée un porte-monnaie commun (IF-31), valide ses données (IF-32),
  initialise le propriétaire avec ses droits "owner" (IF-36)
  et associe les membres/participants supplémentaires (IF-30).

  L'opération est transactionnelle via `Ecto.Multi`.
  Si une donnée est invalide, la transaction est annulée.

  ## Paramètres
  - `creator`: Le `%User{}` connecté qui crée le porte-monnaie.
  - `wallet_attrs`: Les attributs du porte-monnaie (`name`, `description`, `currency`).
  - `participants`: Liste de maps pour les autres membres, ex:
    `[%{name: "Alice", email: "alice@example.com", user_id: 2}, %{name: "Bob"}]`
  """
  def create_wallet(%User{} = creator, wallet_attrs, participants \\ []) do
    Repo.transaction(fn ->
      wallet_changeset =
        %Wallet{creator_id: creator.id}
        |> Wallet.changeset(wallet_attrs)

      case Repo.insert(wallet_changeset) do
        {:ok, wallet} ->
          owner_changeset =
            %WalletMember{wallet_id: wallet.id, user_id: creator.id}
            |> WalletMember.changeset(%{
              name: creator.name,
              email: creator.email,
              role: "owner"
            })

          case Repo.insert(owner_changeset) do
            {:ok, _owner} ->
              case insert_additional_members(wallet, creator, participants) do
                :ok ->
                  get_wallet!(wallet.id)

                {:error, :member, member_changeset} ->
                  Repo.rollback({:member, member_changeset})
              end

            {:error, owner_changeset} ->
              Repo.rollback({:owner_member, owner_changeset})
          end

        {:error, changeset} ->
          Repo.rollback({:wallet, changeset})
      end
    end)
    |> case do
      {:ok, wallet} -> {:ok, wallet}
      {:error, {:wallet, changeset}} -> {:error, :wallet, changeset}
      {:error, {:member, changeset}} -> {:error, :member, changeset}
      {:error, {:owner_member, changeset}} -> {:error, :owner_member, changeset}
      {:error, reason} -> {:error, :general, reason}
    end
  end

  defp insert_additional_members(wallet, creator, participants) do
    filtered =
      participants
      |> Enum.reject(fn p ->
        # Ignore uniquement les entrées totalement vides ou le créateur lui-même
        p_name = p[:name] || p["name"]
        p_email = p[:email] || p["email"]
        p_user_id = p[:user_id] || p["user_id"]

        is_blank_entry =
          (is_nil(p_name) or String.trim(to_string(p_name)) == "") and
            (is_nil(p_email) or String.trim(to_string(p_email)) == "") and
            is_nil(p_user_id)

        is_blank_entry or (p_user_id && p_user_id == creator.id)
      end)

    Enum.reduce_while(filtered, :ok, fn participant, :ok ->
      raw_name = participant[:name] || participant["name"]
      user_id = participant[:user_id] || participant["user_id"]
      user = if user_id, do: Accounts.get_user(user_id), else: nil

      name =
        if(is_binary(raw_name), do: String.trim(raw_name), else: raw_name) || (user && user.name)

      email = participant[:email] || participant["email"] || (user && user.email)

      changeset =
        %WalletMember{wallet_id: wallet.id, user_id: user_id}
        |> WalletMember.changeset(%{
          name: name,
          email: email,
          role: participant[:role] || participant["role"] || "member"
        })

      case Repo.insert(changeset) do
        {:ok, _member} -> {:cont, :ok}
        {:error, err_changeset} -> {:halt, {:error, :member, err_changeset}}
      end
    end)
  end

  @doc """
  Ajoute un nouveau participant à un porte-monnaie avec vérification que l'utilisateur est le propriétaire.
  """
  def add_member(%User{} = user, %Wallet{} = wallet, attrs) do
    if owner?(wallet, user) do
      add_member(wallet, attrs)
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Ajoute un nouveau participant à un porte-monnaie existant.
  """
  def add_member(%Wallet{} = wallet, attrs) do
    user_id = attrs[:user_id] || attrs["user_id"]
    user = if user_id, do: Accounts.get_user(user_id), else: nil
    name = attrs[:name] || attrs["name"] || (user && user.name)
    email = attrs[:email] || attrs["email"] || (user && user.email)
    role = attrs[:role] || attrs["role"] || "member"

    %WalletMember{wallet_id: wallet.id, user_id: user_id}
    |> WalletMember.changeset(%{
      name: name,
      email: email,
      role: role
    })
    |> Repo.insert()
  end

  @doc """
  Retire un participant d'un porte-monnaie avec vérification que l'utilisateur est le propriétaire.
  Le propriétaire ne peut pas être retiré de son propre porte-monnaie.
  """
  def remove_member(%User{} = user, %Wallet{} = wallet, member_id) do
    if owner?(wallet, user) do
      case Repo.get_by(WalletMember, id: member_id, wallet_id: wallet.id) do
        nil ->
          {:error, :not_found}

        %WalletMember{role: "owner"} ->
          {:error, :cannot_remove_owner}

        %WalletMember{} = member ->
          Repo.delete(member)
      end
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Permet à un membre (non-propriétaire) de quitter volontairement un porte-monnaie commun.
  """
  def leave_wallet(%User{} = user, %Wallet{} = wallet) do
    case Repo.get_by(WalletMember, wallet_id: wallet.id, user_id: user.id) do
      nil ->
        {:error, :not_found}

      %WalletMember{role: "owner"} ->
        {:error, :owner_cannot_leave}

      %WalletMember{} = member ->
        Repo.delete(member)
    end
  end

  @doc """
  Vérifie si un utilisateur est le propriétaire du porte-monnaie.
  """
  def owner?(%Wallet{} = wallet, %User{} = user) do
    wallet.creator_id == user.id
  end

  def owner?(%Wallet{} = wallet, user_id) when is_integer(user_id) do
    wallet.creator_id == user_id
  end

  def owner?(_, _), do: false

  @doc """
  Valide l'ajout d'un nouveau participant par email pour un créateur ou propriétaire donné.
  Vérifie que l'email est présent, valide, n'appartient pas au propriétaire,
  n'est pas déjà dans la liste des participants, et correspond à un compte inscrit.
  Retourne `{:ok, user}` ou `{:error, message}`.
  """
  def validate_new_participant(existing_participants, %User{} = current_user, email) do
    email = String.trim(to_string(email || ""))

    cond do
      email == "" ->
        {:error, "L'adresse email est obligatoire."}

      not (email =~ ~r/^[^\s]+@[^\s]+\.[^\s]+$/) ->
        {:error, "Veuillez saisir une adresse email valide."}

      email == current_user.email ->
        {:error, "Vous êtes déjà le propriétaire de ce porte-monnaie."}

      Enum.any?(existing_participants, fn
        %{email: p_email} when is_binary(p_email) ->
          String.downcase(p_email) == String.downcase(email)

        _ ->
          false
      end) ->
        {:error, "Cet utilisateur fait déjà partie des participants."}

      user = Accounts.get_user_by_email(email) ->
        {:ok, user}

      true ->
        {:error,
         "Aucun utilisateur inscrit avec l'email #{email}. La personne doit posséder un compte sur la plateforme."}
    end
  end

  @doc """
  Met à jour un porte-monnaie avec vérification que l'utilisateur est bien le propriétaire.
  """
  def update_wallet(%User{} = user, %Wallet{} = wallet, attrs) do
    if owner?(wallet, user) do
      update_wallet(wallet, attrs)
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Met à jour les attributs d'un porte-monnaie.
  """
  def update_wallet(%Wallet{} = wallet, attrs) do
    wallet
    |> Wallet.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Supprime un porte-monnaie avec vérification que l'utilisateur est bien le propriétaire.
  """
  def delete_wallet(%User{} = user, %Wallet{} = wallet) do
    if owner?(wallet, user) do
      delete_wallet(wallet)
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Supprime un porte-monnaie de la base de données.
  """
  def delete_wallet(%Wallet{} = wallet) do
    Repo.delete(wallet)
  end
end
