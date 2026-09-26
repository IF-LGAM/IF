defmodule LesBonsComptes.Wallets.Members do
  @moduledoc """
  Gestion des membres et participants des porte-monnaies.
  Comprend l'ajout, le retrait, les permissions et la validation des participants.
  """

  alias LesBonsComptes.Accounts
  alias LesBonsComptes.Accounts.User
  alias LesBonsComptes.Repo
  alias LesBonsComptes.Wallets.{Wallet, WalletMember}

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
  Ajoute un nouveau participant à un porte-monnaie avec vérification que l'utilisateur est le propriétaire.
  """
  def add(%User{} = user, %Wallet{} = wallet, attrs) do
    if owner?(wallet, user) do
      add(wallet, attrs)
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Ajoute un nouveau participant à un porte-monnaie existant.
  """
  def add(%Wallet{} = wallet, attrs) do
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
  def remove(%User{} = user, %Wallet{} = wallet, member_id) do
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
  def leave(%User{} = user, %Wallet{} = wallet) do
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
  Insère les membres initiaux supplémentaires lors de la création transactionnelle du porte-monnaie.
  """
  def insert_additional_members(wallet, creator, participants) do
    filtered =
      participants
      |> Enum.reject(fn p ->
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
end
