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
end
