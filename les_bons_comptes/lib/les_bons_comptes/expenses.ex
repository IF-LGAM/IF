defmodule LesBonsComptes.Expenses do
  @moduledoc """
  Business context for shared expense management (IF-62).
  Handles expense creation, payer member assignment,
  amount validations, and expense retrieval by wallet.
  """

  import Ecto.Query, warn: false
  alias LesBonsComptes.Repo
  alias LesBonsComptes.Accounts.User
  alias LesBonsComptes.Expenses.Expense
  alias LesBonsComptes.Expenses.Settlement
  alias LesBonsComptes.Wallets.Wallet

  @doc """
  Returns the list of expenses for a wallet, ordered by descending date.
  """
  def list_expenses_for_wallet(wallet_id) when is_integer(wallet_id) or is_binary(wallet_id) do
    from(e in Expense,
      where: e.wallet_id == ^wallet_id,
      order_by: [desc: e.date, desc: e.inserted_at],
      preload: [:payer, :created_by]
    )
    |> Repo.all()
  end

  @doc """
  Retrieves an expense by its ID with its associations preloaded.
  Raises if not found.
  """
  def get_expense!(id) do
    Expense
    |> Repo.get!(id)
    |> Repo.preload([:wallet, :payer, :created_by])
  end

  @doc """
  Returns a changeset for tracking expense changes.
  """
  def change_expense(%Expense{} = expense, attrs \\ %{}) do
    Expense.changeset(expense, attrs)
  end

  @doc """
  Creates a new expense associated with a wallet (IF-66, IF-70).
  Verifies that the user is a member of the group (or the owner).
  Defaults the expense payer to the logged-in user (IF-68),
  or to the selected member if valid for this wallet.
  """
  def create_expense(%User{} = user, %Wallet{} = wallet, attrs) do
    wallet = Repo.preload(wallet, [:members])
    user_member = Enum.find(wallet.members, &(&1.user_id == user.id))

    cond do
      wallet.status in ["pending_settlement", "closed"] ->
        {:error, :wallet_closed}

      is_nil(user_member) ->
        {:error, :unauthorized}

      true ->
        payer_id = resolve_payer_id(attrs[:payer_id] || attrs["payer_id"], user_member.id)

        case validate_payer_in_wallet(wallet, payer_id, attrs) do
          :ok ->
            date = resolve_date(attrs[:date] || attrs["date"])
            params = build_expense_params(attrs, wallet, user, payer_id, date)

            %Expense{}
            |> Expense.changeset(params)
            |> Repo.insert()
            |> case do
              {:ok, expense} ->
                {:ok, Repo.preload(expense, [:payer, :created_by, :wallet])}

              {:error, changeset} ->
                {:error, changeset}
            end

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  defp resolve_payer_id(nil, default_id), do: default_id
  defp resolve_payer_id("", default_id), do: default_id
  defp resolve_payer_id(id, _default_id) when is_integer(id), do: id
  defp resolve_payer_id(id, _default_id) when is_binary(id), do: String.to_integer(id)

  defp resolve_date(nil), do: Date.utc_today()
  defp resolve_date(""), do: Date.utc_today()
  defp resolve_date(val), do: val

  defp validate_payer_in_wallet(wallet, payer_id, attrs) do
    if Enum.any?(wallet.members, &(&1.id == payer_id)) do
      :ok
    else
      changeset =
        %Expense{}
        |> Expense.changeset(attrs)
        |> Ecto.Changeset.add_error(
          :payer_id,
          "Le membre sélectionné ne fait pas partie de ce porte-monnaie"
        )

      {:error, changeset}
    end
  end

  defp build_expense_params(attrs, wallet, user, payer_id, date) do
    attrs
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Map.put("wallet_id", wallet.id)
    |> Map.put("created_by_id", user.id)
    |> Map.put("payer_id", payer_id)
    |> Map.put("currency", wallet.currency)
    |> Map.put("date", date)
  end

  @doc """
  Calculates the total amount of recorded expenses for a wallet.
  Returns a %Decimal{}.
  """
  def total_expenses_for_wallet(wallet_id) do
    query =
      from(e in Expense,
        where: e.wallet_id == ^wallet_id,
        select: sum(e.amount)
      )

    Repo.one(query) || Decimal.new("0.00")
  end

  @doc """
  Calculates the total amount spent by each member in a wallet.
  Returns a map `%{member_id => Decimal.t}`.
  """
  def total_expenses_by_member(wallet_id) do
    from(e in Expense,
      where: e.wallet_id == ^wallet_id,
      group_by: e.payer_id,
      select: {e.payer_id, sum(e.amount)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Counts the total number of recorded expenses for a wallet.
  """
  def count_expenses_for_wallet(wallet_id) when is_integer(wallet_id) or is_binary(wallet_id) do
    from(e in Expense,
      where: e.wallet_id == ^wallet_id,
      select: count(e.id)
    )
    |> Repo.one() || 0
  end

  @doc """
  Checks if a user has permission to delete an expense (IF-77, IF-79).
  Allowed ONLY if the wallet is open (in declaration stage) AND the user is:
  - the expense creator (`created_by_id == user.id`),
  - the associated payer (`payer.user_id == user.id`),
  - or the wallet owner (`wallet.creator_id == user.id`).
  """
  def can_delete_expense?(%User{} = user, %Expense{} = expense) do
    expense = Repo.preload(expense, [:wallet, :payer])

    wallet_is_open = expense.wallet && expense.wallet.status == "open"
    is_creator_of_expense = expense.created_by_id == user.id
    is_payer_of_expense = expense.payer && expense.payer.user_id == user.id
    is_wallet_owner = expense.wallet && expense.wallet.creator_id == user.id

    wallet_is_open and (is_creator_of_expense or is_payer_of_expense or is_wallet_owner)
  end

  def can_delete_expense?(_, _), do: false

  @doc """
  Deletes an expense after checking permissions (IF-78, IF-79).
  Rejects with `{:error, :wallet_closed}` if the wallet is no longer in the declaration stage.
  """
  def delete_expense(%User{} = user, %Expense{} = expense) do
    expense = Repo.preload(expense, [:wallet, :payer])

    cond do
      expense.wallet && expense.wallet.status != "open" ->
        {:error, :wallet_closed}

      can_delete_expense?(user, expense) ->
        Repo.delete(expense)

      true ->
        {:error, :unauthorized}
    end
  end

  def delete_expense(%User{} = user, expense_id)
      when is_integer(expense_id) or is_binary(expense_id) do
    expense = get_expense!(expense_id)
    delete_expense(user, expense)
  end

  @doc """
  Checks if a user has permission to edit an expense.
  Allowed ONLY if the wallet is open (in declaration stage) AND the user is:
  - the person who added the expense (`created_by_id == user.id`),
  - or the person who paid the expense (`payer.user_id == user.id`).
  """
  def can_edit_expense?(%User{} = user, %Expense{} = expense) do
    expense = Repo.preload(expense, [:wallet, :payer])

    wallet_is_open = expense.wallet && expense.wallet.status == "open"
    is_creator_of_expense = expense.created_by_id == user.id
    is_payer_of_expense = expense.payer && expense.payer.user_id == user.id

    wallet_is_open and (is_creator_of_expense or is_payer_of_expense)
  end

  def can_edit_expense?(_, _), do: false

  @doc """
  Updates an expense after checking permissions.
  Only the person who added the expense or the associated payer can edit it,
  and only if the wallet is in the declaration stage (open).
  """
  def update_expense(%User{} = user, %Expense{} = expense, attrs) do
    expense = Repo.preload(expense, [:wallet, :payer])
    wallet = Repo.preload(expense.wallet, [:members])

    cond do
      is_nil(wallet) or wallet.status != "open" ->
        {:error, :wallet_closed}

      not can_edit_expense?(user, expense) ->
        {:error, :unauthorized}

      true ->
        payer_id =
          case attrs[:payer_id] || attrs["payer_id"] do
            nil -> expense.payer_id
            "" -> expense.payer_id
            id when is_integer(id) -> id
            id when is_binary(id) -> String.to_integer(id)
          end

        case validate_payer_in_wallet(wallet, payer_id, attrs) do
          :ok ->
            params =
              attrs
              |> Map.new(fn {k, v} -> {to_string(k), v} end)
              |> Map.put("payer_id", payer_id)

            expense
            |> Expense.changeset(params)
            |> Repo.update()
            |> case do
              {:ok, updated} ->
                {:ok, Repo.preload(updated, [:payer, :created_by, :wallet], force: true)}

              {:error, changeset} ->
                {:error, changeset}
            end

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Balance computation data retrieval
  # ---------------------------------------------------------------------------

  @doc """
  Retrieves and aggregates all data needed to calculate balances for a wallet.
  Accepts a `%Wallet{}` struct, an integer ID, or a string ID (`"1"`).

  Returns a map containing:
  - `:wallet`: `%Wallet{}` struct with its members preloaded
  - `:wallet_id`: integer wallet ID
  - `:currency`: wallet currency (e.g., "EUR")
  - `:members`: list of participants (`[%WalletMember{}]`)
  - `:members_count`: total count of participants
  - `:total_expenses`: cumulative total expense amount (`%Decimal{}`)
  - `:expenses_by_member`: map `%{member_id => total_paid}` (%Decimal{})
  - `:expenses_count`: total number of recorded expenses

  Returns `nil` if the wallet is not found or if the ID is invalid/`nil`.
  """
  def get_balance_data(%Wallet{} = wallet) do
    wallet = Repo.preload(wallet, [:members])
    build_balance_data(wallet)
  end

  def get_balance_data(wallet_id) when is_binary(wallet_id) do
    case Integer.parse(wallet_id) do
      {id, ""} -> get_balance_data(id)
      _ -> nil
    end
  end

  def get_balance_data(wallet_id) when is_integer(wallet_id) do
    case Repo.get(Wallet, wallet_id) do
      nil -> nil
      wallet -> get_balance_data(wallet)
    end
  end

  def get_balance_data(_), do: nil

  @doc """
  Variant of `get_balance_data/1` returning `{:ok, balance_data}` or `{:error, :not_found}`.
  """
  def fetch_balance_data(wallet_or_id) do
    case get_balance_data(wallet_or_id) do
      nil -> {:error, :not_found}
      data -> {:ok, data}
    end
  end

  defp build_balance_data(%Wallet{} = wallet) do
    members = wallet.members || []
    total_expenses = total_expenses_for_wallet(wallet.id)
    expenses_by_member = total_expenses_by_member(wallet.id)
    expenses_count = count_expenses_for_wallet(wallet.id)

    %{
      wallet: wallet,
      wallet_id: wallet.id,
      currency: wallet.currency,
      members: members,
      members_count: length(members),
      total_expenses: total_expenses,
      expenses_by_member: expenses_by_member,
      expenses_count: expenses_count
    }
  end

  # ---------------------------------------------------------------------------
  # Balance and creditor account calculations
  # ---------------------------------------------------------------------------

  @doc """
  Calculates the net balance of each participant in a wallet.
  For each member, the theoretical fair share (total expenses / number of members)
  is deducted from the total amount they paid:
  `balance = total_paid - fair_share`.

  Accepts either:
  - a pre-retrieved data structure from `get_balance_data/1`
  - a `%Wallet{}` struct
  - a wallet ID (integer or string)

  Returns a list of maps for each member with:
  - `:member`: Struct `%WalletMember{}`
  - `:member_id`: Member ID
  - `:name`: Member name
  - `:email`: Member email
  - `:total_paid`: Total amount paid (%Decimal{})
  - `:fair_share`: Theoretical share due per member (%Decimal{})
  - `:balance`: Net balance (%Decimal{}), positive if creditor, negative if debtor
  - `:amount`: Positive amount to receive if creditor (%Decimal{}), otherwise 0.00
  - `:amount_to_receive`: Alias for :amount
  - `:amount_to_pay`: Positive amount to pay if debtor (%Decimal{}), otherwise 0.00
  - `:type`: `:creditor` (> 0), `:debtor` (< 0), or `:balanced` (== 0)
  - `:currency`: Wallet currency
  """
  def calculate_balances(
        %{members: _, members_count: _, total_expenses: _, expenses_by_member: _} = data
      ) do
    do_calculate_balances(data)
  end

  def calculate_balances(wallet_or_id) do
    case get_balance_data(wallet_or_id) do
      nil -> []
      balance_data -> do_calculate_balances(balance_data)
    end
  end

  @doc """
  Calculates creditor accounts for a wallet and the amounts they should receive.
  Filters participants who paid more than their fair share (`balance > 0.00`).
  Sorts creditor accounts in descending order of amount to receive.

  Returns a list of maps containing:
  - `:member`: Struct `%WalletMember{}`
  - `:member_id`: Member ID
  - `:name`: Member name
  - `:email`: Member email
  - `:amount_to_receive`: Amount to receive (%Decimal{})
  - `:amount`: Alias for `:amount_to_receive`
  - `:total_paid`: Total paid by this member
  - `:fair_share`: Fair share due by each participant
  - `:balance`: Net creditor balance (%Decimal{})
  - `:currency`: Wallet currency
  """
  def calculate_creditors(wallet_or_id) do
    wallet_or_id
    |> calculate_balances()
    |> Enum.filter(&(&1.type == :creditor))
    |> Enum.sort_by(& &1.amount_to_receive, {:desc, Decimal})
  end

  @doc """
  Alias for `calculate_creditors/1`.
  """
  defdelegate list_creditors(wallet_or_id), to: __MODULE__, as: :calculate_creditors

  @doc """
  Alias for `calculate_creditors/1` for the creditor accounts calculation subtask.
  """
  defdelegate calculate_creditor_accounts(wallet_or_id), to: __MODULE__, as: :calculate_creditors

  @doc """
  Calculates debtor accounts for a wallet and the amounts they must pay.
  Filters participants who owe money (`balance < 0.00`).
  Sorts debtor accounts in descending order of amount to pay.

  Returns a list of maps containing:
  - `:member`: Struct `%WalletMember{}`
  - `:member_id`: Member ID
  - `:name`: Member name
  - `:email`: Member email
  - `:amount_to_pay`: Positive amount to pay (%Decimal{})
  - `:amount`: Alias for `:amount_to_pay`
  - `:total_paid`: Total paid by this member
  - `:fair_share`: Fair share due by each participant
  - `:balance`: Net debtor balance (%Decimal{})
  - `:currency`: Wallet currency
  - `:type`: `:debtor`
  """
  def calculate_debtors(wallet_or_id) do
    wallet_or_id
    |> calculate_balances()
    |> Enum.filter(&(&1.type == :debtor))
    |> Enum.map(fn d -> %{d | amount: d.amount_to_pay} end)
    |> Enum.sort_by(& &1.amount_to_pay, {:desc, Decimal})
  end

  @doc """
  Alias for `calculate_debtors/1`.
  """
  defdelegate list_debtors(wallet_or_id), to: __MODULE__, as: :calculate_debtors

  @doc """
  Alias for `calculate_debtors/1` for the debtor accounts calculation subtask.
  """
  defdelegate calculate_debtor_accounts(wallet_or_id), to: __MODULE__, as: :calculate_debtors

  @doc """
  Calculates optimized transfers between participants to settle all debts
  while minimizing the total number of transactions.

  Algorithm:
  1. Retrieves calculated balances.
  2. Isolates debtors (remaining debt) and creditors (remaining credit).
  3. Matches identical amounts first (exact 1-to-1 match).
  4. Greedily matches the largest debtor with the largest creditor.
  5. Adjusts any residual rounding cents if necessary.

  Returns a list of transfers:
  [
    %{
      from_id: integer,
      from_name: string,
      from_email: string | nil,
      to_id: integer,
      to_name: string,
      to_email: string | nil,
      amount: %Decimal{},
      currency: string
    }
  ]
  """
  def calculate_settlements(wallet_or_id) do
    balances = calculate_balances(wallet_or_id)

    debtors =
      balances
      |> Enum.filter(&(&1.type == :debtor and Decimal.gt?(&1.amount_to_pay, Decimal.new("0.00"))))
      |> Enum.map(fn d ->
        %{
          id: d.member_id,
          user_id: d.member && d.member.user_id,
          name: d.name,
          email: d.email,
          amount: d.amount_to_pay
        }
      end)

    creditors =
      balances
      |> Enum.filter(
        &(&1.type == :creditor and Decimal.gt?(&1.amount_to_receive, Decimal.new("0.00")))
      )
      |> Enum.map(fn c ->
        %{
          id: c.member_id,
          user_id: c.member && c.member.user_id,
          name: c.name,
          email: c.email,
          amount: c.amount_to_receive
        }
      end)

    currency =
      case balances do
        [%{currency: c} | _] -> c
        _ -> "EUR"
      end

    do_optimize_settlements(debtors, creditors, currency)
  end

  @doc """
  Alias for `calculate_settlements/1`.
  """
  defdelegate optimize_settlements(wallet_or_id), to: __MODULE__, as: :calculate_settlements

  defp do_optimize_settlements([], _creditors, _currency), do: []
  defp do_optimize_settlements(_debtors, [], _currency), do: []

  defp do_optimize_settlements(debtors, creditors, currency) do
    {exact_transfers, remaining_debtors, remaining_creditors} =
      extract_exact_matches(debtors, creditors, currency, [])

    greedy_transfers =
      greedy_settlement(remaining_debtors, remaining_creditors, currency, [])

    exact_transfers ++ greedy_transfers
  end

  defp extract_exact_matches([], creditors, _currency, acc),
    do: {Enum.reverse(acc), [], creditors}

  defp extract_exact_matches(debtors, [], _currency, acc),
    do: {Enum.reverse(acc), debtors, []}

  defp extract_exact_matches([debtor | rest_debtors], creditors, currency, acc) do
    case Enum.split_with(creditors, &Decimal.equal?(&1.amount, debtor.amount)) do
      {[], _} ->
        {transfers, rem_d, rem_c} = extract_exact_matches(rest_debtors, creditors, currency, acc)
        {transfers, [debtor | rem_d], rem_c}

      {[matched_creditor | other_matched], unmatched} ->
        transfer = %{
          from_id: debtor.id,
          from_user_id: debtor.user_id,
          from_name: debtor.name,
          from_email: debtor.email,
          to_id: matched_creditor.id,
          to_user_id: matched_creditor.user_id,
          to_name: matched_creditor.name,
          to_email: matched_creditor.email,
          amount: Decimal.round(debtor.amount, 2),
          currency: currency
        }

        new_creditors = other_matched ++ unmatched
        extract_exact_matches(rest_debtors, new_creditors, currency, [transfer | acc])
    end
  end

  defp greedy_settlement([], _creditors, _currency, acc), do: Enum.reverse(acc)
  defp greedy_settlement(_debtors, [], _currency, acc), do: Enum.reverse(acc)

  defp greedy_settlement(debtors, creditors, currency, acc) do
    debtors =
      debtors
      |> Enum.filter(&Decimal.gt?(&1.amount, Decimal.new("0.00")))
      |> Enum.sort_by(& &1.amount, {:desc, Decimal})

    creditors =
      creditors
      |> Enum.filter(&Decimal.gt?(&1.amount, Decimal.new("0.00")))
      |> Enum.sort_by(& &1.amount, {:desc, Decimal})

    case {debtors, creditors} do
      {[], _} ->
        Enum.reverse(acc)

      {_, []} ->
        Enum.reverse(acc)

      {[d | rest_d], [c | rest_c]} ->
        transfer_amount =
          if rest_d == [] and rest_c == [] do
            c.amount
          else
            Decimal.min(d.amount, c.amount)
          end

        transfer = %{
          from_id: d.id,
          from_user_id: d.user_id,
          from_name: d.name,
          from_email: d.email,
          to_id: c.id,
          to_user_id: c.user_id,
          to_name: c.name,
          to_email: c.email,
          amount: Decimal.round(transfer_amount, 2),
          currency: currency
        }

        new_d_amount = Decimal.sub(d.amount, transfer_amount)
        new_c_amount = Decimal.sub(c.amount, transfer_amount)

        new_debtors =
          if Decimal.gt?(new_d_amount, Decimal.new("0.00")),
            do: [%{d | amount: new_d_amount} | rest_d],
            else: rest_d

        new_creditors =
          if Decimal.gt?(new_c_amount, Decimal.new("0.00")),
            do: [%{c | amount: new_c_amount} | rest_c],
            else: rest_c

        greedy_settlement(new_debtors, new_creditors, currency, [transfer | acc])
    end
  end

  defp do_calculate_balances(%{members_count: 0}), do: []

  defp do_calculate_balances(%{
         members: members,
         members_count: members_count,
         total_expenses: total_expenses,
         expenses_by_member: expenses_by_member,
         currency: currency
       }) do
    members_count_dec = Decimal.new(members_count)
    fair_share = Decimal.round(Decimal.div(total_expenses, members_count_dec), 2)

    Enum.map(members, fn member ->
      total_paid = Map.get(expenses_by_member, member.id, Decimal.new("0.00"))
      balance = Decimal.round(Decimal.sub(total_paid, fair_share), 2)

      type =
        cond do
          Decimal.gt?(balance, Decimal.new("0.00")) -> :creditor
          Decimal.lt?(balance, Decimal.new("0.00")) -> :debtor
          true -> :balanced
        end

      amount_to_receive =
        if type == :creditor do
          balance
        else
          Decimal.new("0.00")
        end

      amount_to_pay =
        if type == :debtor do
          Decimal.abs(balance)
        else
          Decimal.new("0.00")
        end

      %{
        member: member,
        member_id: member.id,
        name: member.name,
        email: member.email,
        total_paid: total_paid,
        fair_share: fair_share,
        balance: balance,
        amount: amount_to_receive,
        amount_to_receive: amount_to_receive,
        amount_to_pay: amount_to_pay,
        type: type,
        currency: currency
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Transfer settlements and database persistence (IF-85)
  # ---------------------------------------------------------------------------

  @doc """
  Lists all settled transfers recorded in the database for a given wallet.
  """
  def list_settled_transfers(wallet_id) when is_integer(wallet_id) or is_binary(wallet_id) do
    from(s in Settlement,
      where: s.wallet_id == ^wallet_id,
      preload: [:from_member, :to_member],
      order_by: [asc: s.settled_at]
    )
    |> Repo.all()
  end

  @doc """
  Validates and records a transfer in the database by its debtor.
  Business rules:
  - The wallet must be in the settlement phase ("pending_settlement").
  - Only the debtor member (`from_member.user_id == user.id`) can make the transfer.
  - The transfer is persisted in the `settlements` table.
  - If all transfers are completed, the wallet is automatically closed.
  - Broadcasts a PubSub notification to other connected users.
  """
  def settle_transfer(%User{} = user, wallet_or_id, from_id, to_id, amount) do
    case resolve_wallet_for_mock(wallet_or_id) do
      nil ->
        {:error, :not_found}

      %Wallet{status: status} when status != "pending_settlement" ->
        {:error, :wallet_not_in_settlement}

      %Wallet{} = wallet ->
        do_settle_transfer(user, wallet, from_id, to_id, amount)
    end
  end

  defp do_settle_transfer(%User{} = user, %Wallet{} = wallet, from_id, to_id, amount) do
    with {:ok, parsed_from_id} <- parse_member_id(from_id),
         {:ok, parsed_to_id} <- parse_member_id(to_id),
         :ok <- validate_distinct_members(parsed_from_id, parsed_to_id),
         {:ok, from_member} <- find_wallet_member(wallet, parsed_from_id),
         {:ok, to_member} <- find_wallet_member(wallet, parsed_to_id),
         :ok <- validate_debtor_user(user, from_member),
         {:ok, dec_amount} <- parse_settle_amount(amount) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      settlement_params = %{
        wallet_id: wallet.id,
        from_id: from_member.id,
        to_id: to_member.id,
        amount: dec_amount,
        currency: wallet.currency,
        settled_at: now
      }

      case %Settlement{}
           |> Settlement.changeset(settlement_params)
           |> Repo.insert(
             on_conflict: [set: [amount: dec_amount, settled_at: now]],
             conflict_target: [:wallet_id, :from_id, :to_id]
           ) do
        {:ok, settlement} ->
          settlements = calculate_settlements(wallet)
          all_settled = list_settled_transfers(wallet.id)

          all_completed? =
            length(settlements) > 0 and
              Enum.all?(settlements, fn s ->
                Enum.any?(all_settled, &(&1.from_id == s.from_id and &1.to_id == s.to_id))
              end)

          if all_completed? do
            {:ok, _closed_wallet} = LesBonsComptes.Wallets.close_wallet(wallet)
          end

          Phoenix.PubSub.broadcast(
            LesBonsComptes.PubSub,
            "wallet:#{wallet.id}",
            {:wallet_updated, wallet.id}
          )

          {:ok,
           %{
             id: settlement.id,
             wallet_id: wallet.id,
             from_id: from_member.id,
             from_name: from_member.name,
             from_email: from_member.email,
             to_id: to_member.id,
             to_name: to_member.name,
             to_email: to_member.email,
             amount: dec_amount,
             currency: wallet.currency,
             status: "settled",
             settled: true,
             simulated: true,
             settled_at: settlement.settled_at
           }}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  defp validate_debtor_user(%User{id: user_id}, %{user_id: member_user_id}) do
    if member_user_id == user_id do
      :ok
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Executes a simulated (mock) settlement action for a closed wallet (IF-85).
  Takes a wallet (%Wallet{} or id) and an attributes map (%{from_id: ..., to_id: ..., amount: ...}).
  """
  def mock_settle_transfer(wallet_or_id, params) when is_map(params) do
    from_id = params[:from_id] || params["from_id"]
    to_id = params[:to_id] || params["to_id"]
    amount = params[:amount] || params["amount"]

    mock_settle_transfer(wallet_or_id, from_id, to_id, amount)
  end

  @doc """
  Executes a transfer settlement action between two members for a given amount (IF-85).
  Business rules:
  - The wallet must exist.
  - The wallet must be validated or closed (status in ["pending_settlement", "closed"]). If open, returns `{:error, :wallet_not_closed}`.
  - Sender and receiver members must belong to the wallet and be distinct.
  - Amount must be greater than zero.
  """
  def mock_settle_transfer(wallet_or_id, from_id, to_id, amount) do
    case resolve_wallet_for_mock(wallet_or_id) do
      nil ->
        {:error, :not_found}

      %Wallet{status: "open"} ->
        {:error, :wallet_not_closed}

      %Wallet{} = wallet ->
        do_mock_settle_transfer(wallet, from_id, to_id, amount)
    end
  end

  @doc """
  Records the settlement of all proposed transfers for a validated or closed wallet.
  Returns `{:ok, settlements}` or `{:error, reason}`.
  """
  def mock_settle_all(wallet_or_id) do
    case resolve_wallet_for_mock(wallet_or_id) do
      nil ->
        {:error, :not_found}

      %Wallet{status: "open"} ->
        {:error, :wallet_not_closed}

      %Wallet{} = wallet ->
        settlements = calculate_settlements(wallet)
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        # Persist in database
        Enum.each(settlements, fn s ->
          %Settlement{}
          |> Settlement.changeset(%{
            wallet_id: wallet.id,
            from_id: s.from_id,
            to_id: s.to_id,
            amount: s.amount,
            currency: s.currency,
            settled_at: now
          })
          |> Repo.insert(
            on_conflict: [set: [amount: s.amount, settled_at: now]],
            conflict_target: [:wallet_id, :from_id, :to_id]
          )
        end)

        # Automatically close wallet once all transfers are completed
        {:ok, _closed_wallet} = LesBonsComptes.Wallets.close_wallet(wallet)

        Phoenix.PubSub.broadcast(
          LesBonsComptes.PubSub,
          "wallet:#{wallet.id}",
          {:wallet_updated, wallet.id}
        )

        simulated =
          Enum.map(settlements, fn s ->
            %{
              id: "mock_#{s.from_id}_#{s.to_id}",
              wallet_id: wallet.id,
              from_id: s.from_id,
              from_name: s.from_name,
              from_email: s.from_email,
              to_id: s.to_id,
              to_name: s.to_name,
              to_email: s.to_email,
              amount: s.amount,
              currency: s.currency,
              status: "settled",
              settled: true,
              simulated: true,
              settled_at: now
            }
          end)

        {:ok, simulated}
    end
  end

  defp resolve_wallet_for_mock(%Wallet{id: id}) when not is_nil(id) do
    case Repo.get(Wallet, id) do
      nil -> nil
      wallet -> Repo.preload(wallet, [:members])
    end
  end

  defp resolve_wallet_for_mock(id) when is_integer(id) do
    case Repo.get(Wallet, id) do
      nil -> nil
      wallet -> Repo.preload(wallet, [:members])
    end
  end

  defp resolve_wallet_for_mock(id) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, ""} -> resolve_wallet_for_mock(int_id)
      _ -> nil
    end
  end

  defp resolve_wallet_for_mock(_), do: nil

  defp do_mock_settle_transfer(%Wallet{} = wallet, from_id, to_id, amount) do
    with {:ok, parsed_from_id} <- parse_member_id(from_id),
         {:ok, parsed_to_id} <- parse_member_id(to_id),
         :ok <- validate_distinct_members(parsed_from_id, parsed_to_id),
         {:ok, from_member} <- find_wallet_member(wallet, parsed_from_id),
         {:ok, to_member} <- find_wallet_member(wallet, parsed_to_id),
         {:ok, dec_amount} <- parse_settle_amount(amount) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      settlement_params = %{
        wallet_id: wallet.id,
        from_id: from_member.id,
        to_id: to_member.id,
        amount: dec_amount,
        currency: wallet.currency,
        settled_at: now
      }

      {:ok, settlement} =
        %Settlement{}
        |> Settlement.changeset(settlement_params)
        |> Repo.insert(
          on_conflict: [set: [amount: dec_amount, settled_at: now]],
          conflict_target: [:wallet_id, :from_id, :to_id]
        )

      result = %{
        id: settlement.id,
        wallet_id: wallet.id,
        from_id: from_member.id,
        from_name: from_member.name,
        from_email: from_member.email,
        to_id: to_member.id,
        to_name: to_member.name,
        to_email: to_member.email,
        amount: dec_amount,
        currency: wallet.currency,
        status: "settled",
        settled: true,
        simulated: true,
        settled_at: settlement.settled_at
      }

      {:ok, result}
    end
  end

  defp parse_member_id(id) when is_integer(id), do: {:ok, id}

  defp parse_member_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, ""} -> {:ok, int_id}
      _ -> {:error, :invalid_member_id}
    end
  end

  defp parse_member_id(_), do: {:error, :invalid_member_id}

  defp validate_distinct_members(id, id), do: {:error, :identical_members}
  defp validate_distinct_members(_, _), do: :ok

  defp find_wallet_member(%Wallet{members: members}, member_id) do
    case Enum.find(members || [], &(&1.id == member_id)) do
      nil -> {:error, :member_not_found}
      member -> {:ok, member}
    end
  end

  defp parse_settle_amount(%Decimal{} = dec) do
    if Decimal.gt?(dec, Decimal.new("0.00")) do
      {:ok, Decimal.round(dec, 2)}
    else
      {:error, :invalid_amount}
    end
  end

  defp parse_settle_amount(num) when is_number(num) do
    parse_settle_amount(Decimal.from_float(num * 1.0))
  end

  defp parse_settle_amount(str) when is_binary(str) do
    case Decimal.parse(str) do
      {dec, ""} -> parse_settle_amount(dec)
      _ -> {:error, :invalid_amount}
    end
  end

  defp parse_settle_amount(_), do: {:error, :invalid_amount}
end
