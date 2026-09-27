defmodule LesBonsComptes.Expenses do
  @moduledoc """
  Contexte métier pour la gestion des dépenses communes (IF-62).
  Gère la déclaration de dépenses, l'association au compte dépenseur (membre payeur),
  la validation des montants et la consultation des dépenses par porte-monnaie.
  """

  import Ecto.Query, warn: false
  alias LesBonsComptes.Repo
  alias LesBonsComptes.Accounts.User
  alias LesBonsComptes.Expenses.Expense
  alias LesBonsComptes.Wallets.Wallet

  @doc """
  Retourne la liste des dépenses d'un porte-monnaie, triées par date décroissante.
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
  Récupère une dépense par son identifiant avec ses associations préchargées.
  Lève si non trouvée.
  """
  def get_expense!(id) do
    Expense
    |> Repo.get!(id)
    |> Repo.preload([:wallet, :payer, :created_by])
  end

  @doc """
  Retourne un changeset pour une dépense.
  """
  def change_expense(%Expense{} = expense, attrs \\ %{}) do
    Expense.changeset(expense, attrs)
  end

  @doc """
  Déclare une nouvelle dépense associée à un porte-monnaie (IF-66, IF-70).
  Vérifie que l'utilisateur est bien membre du groupe (ou propriétaire).
  Affecte par défaut la dépense au compte dépenseur de l'utilisateur connecté (IF-68),
  ou au membre sélectionné si valide pour ce porte-monnaie.
  """
  def create_expense(%User{} = user, %Wallet{} = wallet, attrs) do
    wallet = Repo.preload(wallet, [:members])
    user_member = Enum.find(wallet.members, &(&1.user_id == user.id))

    if is_nil(user_member) do
      {:error, :unauthorized}
    else
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
  Calcule le montant total des dépenses enregistrées pour un porte-monnaie.
  Retourne un %Decimal{}.
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
  Calcule le total dépensé par membre dans un porte-monnaie.
  Retourne une map `%{member_id => Decimal.t}`.
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
  Compte le nombre total de dépenses enregistrées pour un porte-monnaie.
  """
  def count_expenses_for_wallet(wallet_id) when is_integer(wallet_id) or is_binary(wallet_id) do
    from(e in Expense,
      where: e.wallet_id == ^wallet_id,
      select: count(e.id)
    )
    |> Repo.one() || 0
  end

  @doc """
  Vérifie si un utilisateur a le droit de supprimer une dépense (IF-77, IF-79).
  Autorisé si l'utilisateur est :
  - le créateur de la dépense (`created_by_id == user.id`),
  - le compte dépenseur associé (`payer.user_id == user.id`),
  - ou le propriétaire du porte-monnaie (`wallet.creator_id == user.id`).
  """
  def can_delete_expense?(%User{} = user, %Expense{} = expense) do
    expense = Repo.preload(expense, [:wallet, :payer])

    is_creator_of_expense = expense.created_by_id == user.id
    is_payer_of_expense = expense.payer && expense.payer.user_id == user.id
    is_wallet_owner = expense.wallet && expense.wallet.creator_id == user.id

    is_creator_of_expense or is_payer_of_expense or is_wallet_owner
  end

  def can_delete_expense?(_, _), do: false

  @doc """
  Supprime une dépense après vérification des droits (IF-78, IF-79).
  """
  def delete_expense(%User{} = user, %Expense{} = expense) do
    if can_delete_expense?(user, expense) do
      Repo.delete(expense)
    else
      {:error, :unauthorized}
    end
  end

  def delete_expense(%User{} = user, expense_id)
      when is_integer(expense_id) or is_binary(expense_id) do
    expense = get_expense!(expense_id)
    delete_expense(user, expense)
  end

  # ---------------------------------------------------------------------------
  # Récupération des données nécessaires au calcul des soldes
  # ---------------------------------------------------------------------------

  @doc """
  Récupère et agrège toutes les données nécessaires au calcul des soldes d'un porte-monnaie.
  Accepte un struct `%Wallet{}`, un identifiant entier ou une chaîne de caractères (`"1"`).

  Retourne une map contenant :
  - `:wallet` : struct `%Wallet{}` avec ses membres préchargés
  - `:wallet_id` : identifiant entier du porte-monnaie
  - `:currency` : devise du porte-monnaie (ex: "EUR")
  - `:members` : liste des participants (`[%WalletMember{}]`)
  - `:members_count` : nombre total de participants
  - `:total_expenses` : montant total cumulé des dépenses (`%Decimal{}`)
  - `:expenses_by_member` : map `%{member_id => total_payé}` (%Decimal{})
  - `:expenses_count` : nombre total de dépenses enregistrées

  Retourne `nil` si le porte-monnaie n'est pas trouvé ou si l'ID est invalide/`nil`.
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
  Variante de `get_balance_data/1` retournant `{:ok, balance_data}` ou `{:error, :not_found}`.
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
  # Calcul des soldes et des comptes créditeurs
  # ---------------------------------------------------------------------------

  @doc """
  Calcule la balance nette de chaque participant d'un porte-monnaie.
  Pour chaque membre, la part équitable théorique (total des dépenses / nombre de membres)
  est déduite du total qu'il a payé :
  `balance = total_payé - part_équitable`.

  Accepte soit :
  - une structure de données pré-récupérée issue de `get_balance_data/1`
  - un struct `%Wallet{}`
  - un identifiant de porte-monnaie (entier ou chaîne)

  Retourne une liste de maps avec pour chaque membre :
  - `:member` : Struct `%WalletMember{}`
  - `:member_id` : ID du membre
  - `:name` : Nom du membre
  - `:email` : Email du membre
  - `:total_paid` : Montant total payé (%Decimal{})
  - `:fair_share` : Part théorique due par membre (%Decimal{})
  - `:balance` : Solde net (%Decimal{}), positif si créditeur, négatif si débiteur
  - `:amount` : Montant positif à recevoir si créditeur (%Decimal{}), sinon 0.00
  - `:amount_to_receive` : Alias de :amount
  - `:amount_to_pay` : Montant positif à régler si débiteur (%Decimal{}), sinon 0.00
  - `:type` : `:creditor` (> 0), `:debtor` (< 0) ou `:balanced` (== 0)
  - `:currency` : Devise du porte-monnaie
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
  Calcule les comptes créditeurs d'un porte-monnaie et les montants qu'ils doivent recevoir.
  Filtre les participants qui ont payé plus que leur part équitable (`balance > 0.00`).
  Trie les comptes créditeurs par montant à recevoir décroissant.

  Retourne une liste de maps contenant :
  - `:member` : Struct `%WalletMember{}`
  - `:member_id` : ID du membre
  - `:name` : Nom du membre
  - `:email` : Email du membre
  - `:amount_to_receive` : Montant à recevoir (%Decimal{})
  - `:amount` : Alias de `:amount_to_receive`
  - `:total_paid` : Total payé par ce membre
  - `:fair_share` : Part équitable due par chaque participant
  - `:balance` : Solde net créditeur (%Decimal{})
  - `:currency` : Devise du porte-monnaie
  """
  def calculate_creditors(wallet_or_id) do
    wallet_or_id
    |> calculate_balances()
    |> Enum.filter(&(&1.type == :creditor))
    |> Enum.sort_by(& &1.amount_to_receive, {:desc, Decimal})
  end

  @doc """
  Alias pour `calculate_creditors/1`.
  """
  defdelegate list_creditors(wallet_or_id), to: __MODULE__, as: :calculate_creditors

  @doc """
  Alias pour `calculate_creditors/1` pour la sous-tâche de calcul des comptes créditeurs.
  """
  defdelegate calculate_creditor_accounts(wallet_or_id), to: __MODULE__, as: :calculate_creditors

  @doc """
  Calcule les comptes débiteurs d'un porte-monnaie et les montants qu'ils doivent régler.
  Filtre les participants qui doivent de l'argent (`balance < 0.00`).
  Trie les comptes débiteurs par montant à régler décroissant.

  Retourne une liste de maps contenant :
  - `:member` : Struct `%WalletMember{}`
  - `:member_id` : ID du membre
  - `:name` : Nom du membre
  - `:email` : Email du membre
  - `:amount_to_pay` : Montant positif à régler (%Decimal{})
  - `:amount` : Alias de `:amount_to_pay`
  - `:total_paid` : Total payé par ce membre
  - `:fair_share` : Part équitable due par chaque participant
  - `:balance` : Solde net débiteur (%Decimal{})
  - `:currency` : Devise du porte-monnaie
  - `:type` : `:debtor`
  """
  def calculate_debtors(wallet_or_id) do
    wallet_or_id
    |> calculate_balances()
    |> Enum.filter(&(&1.type == :debtor))
    |> Enum.map(fn d -> %{d | amount: d.amount_to_pay} end)
    |> Enum.sort_by(& &1.amount_to_pay, {:desc, Decimal})
  end

  @doc """
  Alias pour `calculate_debtors/1`.
  """
  defdelegate list_debtors(wallet_or_id), to: __MODULE__, as: :calculate_debtors

  @doc """
  Alias pour `calculate_debtors/1` pour la sous-tâche de calcul des comptes débiteurs.
  """
  defdelegate calculate_debtor_accounts(wallet_or_id), to: __MODULE__, as: :calculate_debtors

  @doc """
  Calcule les virements optimisés entre participants pour solder l'ensemble des dettes
  en minimisant le nombre total de transactions.

  Algorithme :
  1. Récupère les soldes calculés.
  2. Isole les débiteurs (dette restante) et les créditeurs (créance restante).
  3. Apparie en priorité les montants identiques (correspondance exacte 1 pour 1).
  4. Apparie gloutonnement (greedy) le plus gros débiteur avec le plus gros créancier.
  5. Ajuste si nécessaire les éventuels centimes résiduels dus aux arrondis de division.

  Retourne une liste de virements :
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
          name: d.name,
          email: d.email,
          amount: d.amount_to_pay
        }
      end)

    creditors =
      balances
      |> Enum.filter(&(&1.type == :creditor and Decimal.gt?(&1.amount_to_receive, Decimal.new("0.00"))))
      |> Enum.map(fn c ->
        %{
          id: c.member_id,
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
  Alias pour `calculate_settlements/1`.
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
          from_name: debtor.name,
          from_email: debtor.email,
          to_id: matched_creditor.id,
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
          from_name: d.name,
          from_email: d.email,
          to_id: c.id,
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
end
