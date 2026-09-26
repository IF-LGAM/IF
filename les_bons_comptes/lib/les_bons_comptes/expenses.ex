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

    cond do
      is_nil(user_member) ->
        {:error, :unauthorized}

      true ->
        raw_payer_id = attrs[:payer_id] || attrs["payer_id"]

        payer_id =
          case raw_payer_id do
            nil ->
              user_member.id

            "" ->
              user_member.id

            id when is_binary(id) ->
              String.to_integer(id)

            id when is_integer(id) ->
              id
          end

        # Vérifier que le payer_id appartient bien aux membres du wallet
        payer = Enum.find(wallet.members, &(&1.id == payer_id))

        if is_nil(payer) do
          changeset =
            %Expense{}
            |> Expense.changeset(attrs)
            |> Ecto.Changeset.add_error(
              :payer_id,
              "Le membre sélectionné ne fait pas partie de ce porte-monnaie"
            )

          {:error, changeset}
        else
          date =
            case attrs[:date] || attrs["date"] do
              nil -> Date.utc_today()
              "" -> Date.utc_today()
              val -> val
            end

          attrs_with_defaults =
            attrs
            |> Map.new(fn {k, v} -> {to_string(k), v} end)
            |> Map.put("wallet_id", wallet.id)
            |> Map.put("created_by_id", user.id)
            |> Map.put("payer_id", payer_id)
            |> Map.put("currency", wallet.currency)
            |> Map.put("date", date)

          %Expense{}
          |> Expense.changeset(attrs_with_defaults)
          |> Repo.insert()
          |> case do
            {:ok, expense} ->
              {:ok, Repo.preload(expense, [:payer, :created_by, :wallet])}

            {:error, changeset} ->
              {:error, changeset}
          end
        end
    end
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
  Supprime une dépense si l'utilisateur est le créateur de la dépense ou le propriétaire du porte-monnaie.
  """
  def delete_expense(%User{} = user, %Expense{} = expense) do
    expense = Repo.preload(expense, [:wallet])

    if expense.created_by_id == user.id or expense.wallet.creator_id == user.id do
      Repo.delete(expense)
    else
      {:error, :unauthorized}
    end
  end
end
