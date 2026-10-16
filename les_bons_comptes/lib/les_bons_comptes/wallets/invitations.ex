defmodule LesBonsComptes.Wallets.Invitations do
  @moduledoc """
  Manages wallet invitation lifecycles.
  Includes creation, sending, notification, acceptance, decline, and cancellation.
  """

  import Ecto.Query, warn: false
  alias LesBonsComptes.Accounts.User
  alias LesBonsComptes.Repo
  alias LesBonsComptes.Wallets.{InvitationNotifier, Members, Wallet, WalletInvitation}

  @doc """
  Creates and sends an invitation to join a wallet (IF-40, IF-41, IF-42).
  Verifies that the sender is the owner, validates that the invited user exists,
  is not already a member, and has no pending invitation.
  """
  def create(%User{} = inviter, %Wallet{} = wallet, attrs) do
    if wallet.status != "open" do
      {:error, :invitations_disabled}
    else
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
  Lists all pending invitations for a given user (IF-44).
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
  Lists all pending invitations for a given wallet (IF-43).
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
  Retrieves an invitation by ID. Raises if not found.
  """
  def get!(id) do
    WalletInvitation
    |> Repo.get!(id)
    |> Repo.preload([:wallet, :inviter, :invitee])
  end

  @doc """
  Accepts an invitation to a wallet (IF-44, IF-45).
  Associates the invited user's account as an active group member within a transaction.
  """
  def accept(%User{} = user, invitation_id)
      when is_integer(invitation_id) or is_binary(invitation_id) do
    invitation = get!(invitation_id)
    accept(user, invitation)
  end

  def accept(%User{} = user, %WalletInvitation{} = invitation) do
    invitation = Repo.preload(invitation, [:wallet])

    cond do
      invitation.invitee_id != user.id ->
        {:error, :unauthorized}

      invitation.wallet && invitation.wallet.status != "open" ->
        {:error, :invitations_disabled}

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
  Declines an invitation to a wallet (IF-44).
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
  Allows the wallet owner to cancel or revoke a sent invitation (pending or declined).
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

  # ---------------------------------------------------------------------------
  # Invited wallets retrieval and filtering (Epic)
  # ---------------------------------------------------------------------------

  @doc """
  Retrieves the list of wallets to which a user has been invited.
  Each returned wallet has its associated invitation preloaded into the virtual `:invitation` field.
  Optionally filters by invitation status.
  """
  def list_invited_wallets_for_user(user_or_id, status \\ nil)

  def list_invited_wallets_for_user(%User{id: user_id}, status),
    do: list_invited_wallets_for_user(user_id, status)

  def list_invited_wallets_for_user(user_id, status) when is_integer(user_id) do
    invitations_query =
      from(i in WalletInvitation,
        where: i.invitee_id == ^user_id,
        order_by: [desc: i.inserted_at],
        preload: [:inviter, :invitee, wallet: [:creator, :members]]
      )

    invitations_query = filter_invited_wallets_by_status(invitations_query, status)

    invitations_query
    |> Repo.all()
    |> Enum.filter(&(&1.wallet != nil))
    |> Enum.uniq_by(& &1.wallet_id)
    |> Enum.map(fn invitation ->
      wallet = invitation.wallet
      %{wallet | invitation: invitation}
    end)
  end

  @doc """
  Retrieves invited wallets as an `{:ok, wallets}` or `{:error, reason}` result.
  Facilitates loading error handling in the UI.
  """
  def fetch_invited_wallets(user_or_id, status \\ nil) do
    try do
      {:ok, list_invited_wallets_for_user(user_or_id, status)}
    rescue
      e -> {:error, e}
    end
  end

  @doc """
  Filters an Ecto query or a list of wallets or invitations by invitation status.
  Accepts 'all', 'pending', 'accepted', 'declined', 'cancelled' (as atom or string).
  """
  def filter_invited_wallets_by_status(query_or_list, status)

  def filter_invited_wallets_by_status(%Ecto.Query{} = query, status) do
    case normalize_status(status) do
      :ignore -> query
      :all -> query
      {:unknown, _} -> from(i in query, where: false)
      target -> from(i in query, where: i.status == ^target)
    end
  end

  def filter_invited_wallets_by_status(list, status) when is_list(list) do
    case normalize_status(status) do
      :ignore ->
        list

      :all ->
        list

      {:unknown, _} ->
        []

      target ->
        Enum.filter(list, fn
          %Wallet{invitation: %WalletInvitation{status: s}} -> s == target
          %WalletInvitation{status: s} -> s == target
          %{invitation: %{status: s}} -> s == target
          _ -> false
        end)
    end
  end

  @doc """
  Lists all invitations for a given user with optional status filter.
  """
  def list_for_user(user_or_id, status \\ nil)

  def list_for_user(%User{id: user_id}, status), do: list_for_user(user_id, status)

  def list_for_user(user_id, status) when is_integer(user_id) do
    query =
      from(i in WalletInvitation,
        where: i.invitee_id == ^user_id,
        order_by: [desc: i.inserted_at],
        preload: [:wallet, :inviter, :invitee]
      )

    query
    |> filter_invited_wallets_by_status(status)
    |> Repo.all()
  end

  defp normalize_status(nil), do: :ignore
  defp normalize_status(:all), do: :all
  defp normalize_status("all"), do: :all
  defp normalize_status(""), do: :all

  defp normalize_status(status) when is_atom(status) do
    normalize_status(Atom.to_string(status))
  end

  defp normalize_status(status) when is_binary(status) do
    case String.downcase(String.trim(status)) do
      "all" -> :all
      valid when valid in ~w(pending accepted declined cancelled) -> valid
      other -> {:unknown, other}
    end
  end

  defp normalize_status(_), do: :ignore
end
