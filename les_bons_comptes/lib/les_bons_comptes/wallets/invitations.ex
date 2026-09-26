defmodule LesBonsComptes.Wallets.Invitations do
  @moduledoc """
  Gestion du cycle de vie des invitations aux porte-monnaies.
  Comprend la création, l'envoi, la notification, l'acceptation, le refus et l'annulation.
  """

  import Ecto.Query, warn: false
  alias LesBonsComptes.Accounts.User
  alias LesBonsComptes.Repo
  alias LesBonsComptes.Wallets.{InvitationNotifier, Members, Wallet, WalletInvitation}

  @doc """
  Crée et envoie une invitation pour rejoindre un porte-monnaie (IF-40, IF-41, IF-42).
  Vérifie que l'émetteur est propriétaire, valide que l'utilisateur invité existe,
  n'est pas déjà membre, et n'a pas déjà d'invitation en attente.
  """
  def create(%User{} = inviter, %Wallet{} = wallet, attrs) do
    email = attrs[:email] || attrs["email"]
    wallet = Repo.preload(wallet, [:members])

    with :ok <- validate_permissions(inviter, wallet),
         {:ok, invitee} <- Members.validate_new_participant(wallet.members, inviter, email),
         :ok <- validate_not_already_invited(wallet.id, invitee.id) do
      %WalletInvitation{
        wallet_id: wallet.id,
        inviter_id: inviter.id,
        invitee_id: invitee.id
      }
      |> WalletInvitation.changeset(%{
        email: invitee.email,
        status: "pending"
      })
      |> Repo.insert()
      |> case do
        {:ok, invitation} ->
          invitation = Repo.preload(invitation, [:wallet, :inviter, :invitee])
          _ = InvitationNotifier.deliver_invitation(invitation, wallet, inviter)
          {:ok, invitation}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  defp validate_permissions(user, wallet) do
    if Members.owner?(wallet, user) do
      :ok
    else
      {:error, :unauthorized}
    end
  end

  defp validate_not_already_invited(wallet_id, invitee_id) do
    query =
      from(i in WalletInvitation,
        where: i.wallet_id == ^wallet_id and i.invitee_id == ^invitee_id and i.status == "pending"
      )

    if Repo.exists?(query) do
      {:error, "Une invitation est déjà en attente pour cet utilisateur."}
    else
      :ok
    end
  end

  @doc """
  Liste toutes les invitations en attente pour un utilisateur donné (IF-44).
  """
  def list_pending_for_user(user_id) when is_integer(user_id) do
    from(i in WalletInvitation,
      where: i.invitee_id == ^user_id and i.status == "pending",
      order_by: [desc: i.inserted_at],
      preload: [:wallet, :inviter]
    )
    |> Repo.all()
  end

  @doc """
  Liste toutes les invitations en attente pour un porte-monnaie donné (IF-43).
  """
  def list_pending_for_wallet(wallet_id) when is_integer(wallet_id) do
    from(i in WalletInvitation,
      where: i.wallet_id == ^wallet_id and i.status == "pending",
      order_by: [desc: i.inserted_at],
      preload: [:invitee, :inviter]
    )
    |> Repo.all()
  end

  @doc """
  Récupère une invitation par son identifiant. Lève si introuvable.
  """
  def get!(id) do
    WalletInvitation
    |> Repo.get!(id)
    |> Repo.preload([:wallet, :inviter, :invitee])
  end

  @doc """
  Accepte une invitation au porte-monnaie (IF-44, IF-45).
  Associe le compte de l'utilisateur invité comme membre effectif du groupe dans une transaction.
  """
  def accept(%User{} = user, invitation_id)
      when is_integer(invitation_id) or is_binary(invitation_id) do
    invitation = get!(invitation_id)
    accept(user, invitation)
  end

  def accept(%User{} = user, %WalletInvitation{} = invitation) do
    cond do
      invitation.invitee_id != user.id ->
        {:error, :unauthorized}

      invitation.status != "pending" ->
        {:error, :already_processed}

      true ->
        Repo.transaction(fn ->
          {:ok, updated_invitation} =
            invitation
            |> WalletInvitation.changeset(%{status: "accepted"})
            |> Repo.update()

          member_attrs = %{
            user_id: user.id,
            name: user.name,
            email: user.email,
            role: "member"
          }

          case Members.add(%Wallet{id: invitation.wallet_id}, member_attrs) do
            {:ok, member} ->
              {updated_invitation, member}

            {:error, changeset} ->
              Repo.rollback({:member, changeset})
          end
        end)
        |> case do
          {:ok, {_invitation, member}} -> {:ok, member}
          {:error, {:member, changeset}} -> {:error, changeset}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc """
  Refuse une invitation au porte-monnaie (IF-44).
  """
  def decline(%User{} = user, invitation_id)
      when is_integer(invitation_id) or is_binary(invitation_id) do
    invitation = get!(invitation_id)
    decline(user, invitation)
  end

  def decline(%User{} = user, %WalletInvitation{} = invitation) do
    cond do
      invitation.invitee_id != user.id ->
        {:error, :unauthorized}

      invitation.status != "pending" ->
        {:error, :already_processed}

      true ->
        invitation
        |> WalletInvitation.changeset(%{status: "declined"})
        |> Repo.update()
    end
  end

  @doc """
  Permet au propriétaire du porte-monnaie d'annuler ou retirer une invitation envoyée (pending ou declined).
  """
  def cancel(%User{} = user, invitation_id) do
    invitation = get!(invitation_id)
    wallet = Repo.get!(Wallet, invitation.wallet_id)

    if Members.owner?(wallet, user) and invitation.status in ["pending", "declined"] do
      invitation
      |> WalletInvitation.changeset(%{status: "cancelled"})
      |> Repo.update()
    else
      {:error, :unauthorized}
    end
  end
end
