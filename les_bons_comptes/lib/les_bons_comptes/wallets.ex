defmodule LesBonsComptes.Wallets do
  @moduledoc """
  Business context for shared wallet management (Wallets / Tricounts).
  Handles wallet creation, participant association,
  permissions initialization (owner), and associated business validations.
  """

  import Ecto.Query, warn: false
  alias LesBonsComptes.Repo
  alias LesBonsComptes.Accounts.User
  alias LesBonsComptes.Wallets.{Invitations, Members, Wallet, WalletInvitation, WalletMember}

  # ---------------------------------------------------------------------------
  # Delegations to Members and Invitations
  # ---------------------------------------------------------------------------

  # Members and permissions (IF-30, IF-36, IF-38, IF-39)
  defdelegate owner?(wallet, user), to: Members
  defdelegate add_member(wallet, attrs), to: Members, as: :add
  defdelegate add_member(user, wallet, attrs), to: Members, as: :add
  defdelegate remove_member(user, wallet, member_id), to: Members, as: :remove
  defdelegate leave_wallet(user, wallet), to: Members, as: :leave
  defdelegate validate_new_participant(existing_participants, current_user, email), to: Members

  # Invitations (IF-37, IF-40, IF-41, IF-42, IF-43, IF-44, IF-45)
  defdelegate create_invitation(inviter, wallet, attrs), to: Invitations, as: :create

  defdelegate list_pending_invitations_for_user(user_id),
    to: Invitations,
    as: :list_pending_for_user

  defdelegate list_pending_invitations_for_wallet(wallet_id),
    to: Invitations,
    as: :list_pending_for_wallet

  defdelegate get_invitation!(id), to: Invitations, as: :get!
  defdelegate accept_invitation(user, invitation_or_id), to: Invitations, as: :accept
  defdelegate decline_invitation(user, invitation_or_id), to: Invitations, as: :decline
  defdelegate cancel_invitation(user, invitation_id), to: Invitations, as: :cancel

  defdelegate list_invited_wallets_for_user(user_or_id, status \\ nil), to: Invitations

  defdelegate list_invited_wallets(user_or_id, status \\ nil),
    to: Invitations,
    as: :list_invited_wallets_for_user

  defdelegate fetch_invited_wallets(user_or_id, status \\ nil), to: Invitations
  defdelegate filter_invited_wallets_by_status(query_or_list, status), to: Invitations

  defdelegate paginate_invited_wallets(user_or_id, status \\ nil, page \\ 1, page_size \\ 6),
    to: Invitations

  defdelegate list_invitations_for_user(user_or_id, status \\ nil),
    to: Invitations,
    as: :list_for_user

  # Balance computation, creditor/debtor accounts, and settlement data
  defdelegate get_balance_data(wallet_or_id), to: LesBonsComptes.Expenses
  defdelegate fetch_balance_data(wallet_or_id), to: LesBonsComptes.Expenses
  defdelegate calculate_balances(wallet_or_id), to: LesBonsComptes.Expenses
  defdelegate calculate_creditors(wallet_or_id), to: LesBonsComptes.Expenses
  defdelegate calculate_creditor_accounts(wallet_or_id), to: LesBonsComptes.Expenses
  defdelegate list_creditors(wallet_or_id), to: LesBonsComptes.Expenses
  defdelegate calculate_debtors(wallet_or_id), to: LesBonsComptes.Expenses
  defdelegate calculate_debtor_accounts(wallet_or_id), to: LesBonsComptes.Expenses
  defdelegate list_debtors(wallet_or_id), to: LesBonsComptes.Expenses
  defdelegate calculate_settlements(wallet_or_id), to: LesBonsComptes.Expenses
  defdelegate optimize_settlements(wallet_or_id), to: LesBonsComptes.Expenses
  defdelegate mock_settle_transfer(wallet_or_id, params), to: LesBonsComptes.Expenses

  defdelegate mock_settle_transfer(wallet_or_id, from_id, to_id, amount),
    to: LesBonsComptes.Expenses

  defdelegate mock_settle_all(wallet_or_id), to: LesBonsComptes.Expenses

  defdelegate settle_transfer(user, wallet_or_id, from_id, to_id, amount),
    to: LesBonsComptes.Expenses

  defdelegate list_settled_transfers(wallet_id), to: LesBonsComptes.Expenses
  defdelegate paginate_expenses(wallet_or_id, page \\ 1, page_size \\ 8), to: LesBonsComptes.Expenses

  @doc """
  Returns all wallets the user participates in
  (either as creator or as an enrolled member).
  Optionally filters by status ("open", "closed", "pending_settlement", "all").
  """
  def list_wallets_for_user(user_or_id, status \\ nil)

  def list_wallets_for_user(%User{id: user_id}, status),
    do: list_wallets_for_user(user_id, status)

  def list_wallets_for_user(user_id, status) when is_integer(user_id) do
    query =
      from(w in Wallet,
        left_join: m in assoc(w, :members),
        where: w.creator_id == ^user_id or m.user_id == ^user_id,
        distinct: true,
        order_by: [desc: w.inserted_at],
        preload: [:creator, :members]
      )

    query
    |> filter_wallets_by_status(status)
    |> Repo.all()
  end

  @doc """
  Returns a `%LesBonsComptes.Pagination{}` of wallets for a user.
  """
  def paginate_wallets(user_or_id, status \\ nil, page \\ 1, page_size \\ 8) do
    list_wallets_for_user(user_or_id, status)
    |> LesBonsComptes.Pagination.paginate(page, page_size)
  end

  @doc """
  Retrieves wallets for a user as an `{:ok, wallets}` or `{:error, reason}` tuple
  for robust loading error handling.
  """
  def fetch_wallets_for_user(user_or_id, status \\ nil) do
    try do
      {:ok, list_wallets_for_user(user_or_id, status)}
    rescue
      e -> {:error, e}
    end
  end

  @doc """
  Retrieves only open wallets for a user.
  """
  def list_open_wallets_for_user(user_or_id) do
    list_wallets_for_user(user_or_id, "open")
  end

  @doc """
  Retrieves open wallets as an `{:ok, wallets}` or `{:error, reason}` result.
  """
  def fetch_open_wallets(user_or_id) do
    fetch_wallets_for_user(user_or_id, "open")
  end

  @doc """
  Retrieves only closed wallets for a user.
  """
  def list_closed_wallets_for_user(user_or_id) do
    list_wallets_for_user(user_or_id, "closed")
  end

  @doc """
  Retrieves closed wallets as an `{:ok, wallets}` or `{:error, reason}` result.
  """
  def fetch_closed_wallets(user_or_id) do
    fetch_wallets_for_user(user_or_id, "closed")
  end

  @doc """
  Filters a wallet query or list by status.
  Accepts 'all', 'open', 'closed', 'pending_settlement', 'active' (atom or string).
  """
  def filter_wallets_by_status(query_or_list, status)

  def filter_wallets_by_status(%Ecto.Query{} = query, status) do
    case normalize_wallet_status(status) do
      :ignore -> query
      :all -> query
      "active" -> from(w in query, where: w.status in ["open", "pending_settlement"])
      {:unknown, _} -> from(w in query, where: false)
      target -> from(w in query, where: w.status == ^target)
    end
  end

  def filter_wallets_by_status(list, status) when is_list(list) do
    case normalize_wallet_status(status) do
      :ignore -> list
      :all -> list
      "active" -> Enum.filter(list, &(&1.status in ["open", "pending_settlement"]))
      {:unknown, _} -> []
      target -> Enum.filter(list, &(&1.status == target))
    end
  end

  defp normalize_wallet_status(nil), do: :ignore
  defp normalize_wallet_status(:all), do: :all
  defp normalize_wallet_status("all"), do: :all
  defp normalize_wallet_status(""), do: :all

  defp normalize_wallet_status(status) when is_atom(status) do
    normalize_wallet_status(Atom.to_string(status))
  end

  defp normalize_wallet_status(status) when is_binary(status) do
    case String.downcase(String.trim(status)) do
      "all" -> :all
      "active" -> "active"
      valid when valid in ~w(open closed pending_settlement) -> valid
      other -> {:unknown, other}
    end
  end

  defp normalize_wallet_status(_), do: :ignore

  @doc """
  Retrieves a wallet by ID with its members, invitations, and creator. Raises if not found.
  """
  def get_wallet!(id) do
    Wallet
    |> Repo.get!(id)
    |> Repo.preload([
      :creator,
      members: from(m in WalletMember, order_by: [asc: m.id]),
      invitations:
        from(i in WalletInvitation,
          where: i.status in ["pending", "declined"],
          order_by: [desc: i.inserted_at],
          preload: [:invitee, :inviter]
        ),
      expenses:
        from(e in LesBonsComptes.Expenses.Expense,
          order_by: [desc: e.date, desc: e.inserted_at],
          preload: [:payer, :created_by]
        )
    ])
  end

  @doc """
  Retrieves a wallet by ID. Returns nil if not found.
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
  Initializes a changeset for a new wallet.
  """
  def change_wallet(%Wallet{} = wallet, attrs \\ %{}) do
    Wallet.changeset(wallet, attrs)
  end

  @doc """
  Creates a shared wallet (IF-31), validates its data (IF-32),
  initializes the creator with "owner" rights (IF-36),
  and associates additional members/participants (IF-30).

  The operation is transactional via `Ecto.Multi`.
  If any data is invalid, the transaction is rolled back.

  ## Parameters
  - `creator`: The authenticated `%User{}` creating the wallet.
  - `wallet_attrs`: Wallet attributes (`name`, `description`, `currency`).
  - `participants`: List of maps for other members, e.g.:
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
              case Members.insert_additional_members(wallet, creator, participants) do
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

  @doc """
  Updates a wallet after checking that the user is the owner.
  Rejects with `{:error, :wallet_closed}` if the wallet is no longer in the declaration stage ("open").
  """
  def update_wallet(%User{} = user, %Wallet{} = wallet, attrs) do
    cond do
      wallet.status != "open" ->
        {:error, :wallet_closed}

      not owner?(wallet, user) ->
        {:error, :unauthorized}

      true ->
        update_wallet(wallet, attrs)
    end
  end

  @doc """
  Updates attributes of a wallet.
  Rejects content updates if the wallet is no longer in the declaration stage ("open").
  """
  def update_wallet(%Wallet{} = wallet, attrs) do
    has_content_updates =
      Enum.any?(attrs, fn {k, _v} ->
        to_string(k) in ["name", "description", "currency"]
      end)

    if has_content_updates and wallet.status != "open" do
      {:error, :wallet_closed}
    else
      wallet
      |> Wallet.changeset(attrs)
      |> Repo.update()
    end
  end

  @doc """
  Deletes a wallet after checking that the user is the owner.
  """
  def delete_wallet(%User{} = user, %Wallet{} = wallet) do
    if owner?(wallet, user) do
      delete_wallet(wallet)
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Deletes a wallet from the database.
  """
  def delete_wallet(%Wallet{} = wallet) do
    Repo.delete(wallet)
  end

  @doc """
  Validates wallet accounts and freezes expenses to proceed to pending settlements (Step 2).
  Only the owner can validate the group.
  """
  def validate_wallet(%User{} = user, %Wallet{} = wallet) do
    if owner?(wallet, user) do
      validate_wallet(wallet)
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Validates a wallet by updating its status to "pending_settlement".
  """
  def validate_wallet(%Wallet{} = wallet) do
    update_wallet(wallet, %{status: "pending_settlement"})
  end

  @doc """
  Closes a wallet (Step 3: Closed). Only the owner can close the group.
  """
  def close_wallet(%User{} = user, %Wallet{} = wallet) do
    if owner?(wallet, user) do
      close_wallet(wallet)
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Closes a wallet by updating its status to "closed".
  Also removes all existing invitations for this wallet.
  """
  def close_wallet(%Wallet{} = wallet) do
    Repo.delete_all(from i in WalletInvitation, where: i.wallet_id == ^wallet.id)
    update_wallet(wallet, %{status: "closed"})
  end

  @doc """
  Reopens a validated wallet for edits (Step 1: Declarations).
  Only the owner can reopen the group.
  Closure being permanent, a closed wallet can never be reopened ({:error, :closure_is_final}).
  """
  def reopen_wallet(%User{} = user, %Wallet{} = wallet) do
    cond do
      not owner?(wallet, user) ->
        {:error, :unauthorized}

      wallet.status == "closed" ->
        {:error, :closure_is_final}

      true ->
        reopen_wallet(wallet)
    end
  end

  @doc """
  Reopens a wallet by setting its status back to "open".
  Fails if the wallet is already closed.
  """
  def reopen_wallet(%Wallet{} = wallet) do
    if wallet.status == "closed" do
      {:error, :closure_is_final}
    else
      update_wallet(wallet, %{status: "open"})
    end
  end

  @doc """
  Indicates whether the wallet is closed.
  """
  def closed?(%Wallet{} = wallet), do: Wallet.closed?(wallet)
  def closed?(_), do: false

  @doc """
  Indicates whether the wallet is pending settlement.
  """
  def pending_settlement?(%Wallet{} = wallet), do: Wallet.pending_settlement?(wallet)
  def pending_settlement?(_), do: false

  @doc """
  Indicates whether the wallet is open for declarations.
  """
  def open?(%Wallet{} = wallet), do: Wallet.open?(wallet)
  def open?(_), do: false

  @doc """
  Returns the current step number (1, 2, or 3).
  """
  def step_number(%Wallet{} = wallet), do: Wallet.step_number(wallet)
  def step_number(_), do: 1

  @doc """
  Returns the current step label.
  """
  def status_label(%Wallet{} = wallet), do: Wallet.status_label(wallet)
  def status_label(_), do: "Déclarations en cours"

  @doc """
  Indicates whether the wallet can be reopened.
  """
  def reopenable?(%Wallet{} = wallet), do: Wallet.reopenable?(wallet)
  def reopenable?(_), do: false
end
