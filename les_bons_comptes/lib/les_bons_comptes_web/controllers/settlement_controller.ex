defmodule LesBonsComptesWeb.SettlementController do
  use LesBonsComptesWeb, :controller

  alias LesBonsComptes.Expenses
  alias LesBonsComptes.Wallets

  @doc """
  Expose l'algorithme de remboursement optimisé pour un porte-monnaie via l'API REST (IF-84).
  """
  def index(conn, %{"id" => id}) do
    case parse_wallet_id(id) do
      {:ok, wallet_id} ->
        case Wallets.get_wallet(wallet_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Porte-monnaie introuvable"})

          wallet ->
            total_expenses = Expenses.total_expenses_for_wallet(wallet.id)
            members_count = length(wallet.members || [])

            fair_share =
              if members_count > 0 do
                Decimal.round(Decimal.div(total_expenses, Decimal.new(members_count)), 2)
              else
                Decimal.new("0.00")
              end

            settlements = Expenses.calculate_settlements(wallet)
            creditors = Expenses.calculate_creditors(wallet)
            debtors = Expenses.calculate_debtors(wallet)

            render(conn, :index,
              wallet: wallet,
              total_expenses: total_expenses,
              fair_share: fair_share,
              settlements: settlements,
              creditors: creditors,
              debtors: debtors
            )
        end

      :error ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Porte-monnaie introuvable"})
    end
  end

  @doc """
  Expose une action de remboursement mock pour un porte-monnaie clos (IF-85).
  POST /api/wallets/:id/settlements/mock
  """
  def mock(conn, %{"id" => id} = params) do
    case parse_wallet_id(id) do
      {:ok, wallet_id} ->
        case Wallets.get_wallet(wallet_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Porte-monnaie introuvable"})

          wallet ->
            execute_mock_settlement(conn, wallet, params)
        end

      :error ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Porte-monnaie introuvable"})
    end
  end

  defp execute_mock_settlement(
         conn,
         wallet,
         %{"from_id" => _from_id, "to_id" => _to_id, "amount" => _amount} = params
       ) do
    case Expenses.mock_settle_transfer(wallet, params) do
      {:ok, mock_data} ->
        conn
        |> put_status(:ok)
        |> render(:mock, settlement: mock_data)

      {:error, :wallet_not_closed} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Le porte-monnaie doit être validé ou clos pour effectuer les remboursements"})

      {:error, :member_not_found} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Membre introuvable dans ce porte-monnaie"})

      {:error, :identical_members} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "L'émetteur et le récepteur doivent être distincts"})

      {:error, :invalid_amount} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Le montant du remboursement doit être strictement supérieur à 0"})

      {:error, _reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Impossible d'effectuer le virement"})
    end
  end

  defp execute_mock_settlement(conn, wallet, _params) do
    case Expenses.mock_settle_all(wallet) do
      {:ok, settlements} ->
        wallet = LesBonsComptes.Wallets.get_wallet!(wallet.id)

        conn
        |> put_status(:ok)
        |> render(:mock_all, settlements: settlements, wallet: wallet)

      {:error, :wallet_not_closed} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Le porte-monnaie doit être validé ou clos pour effectuer les remboursements"})

      {:error, _reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Impossible d'effectuer les virements"})
    end
  end

  defp parse_wallet_id(id) when is_integer(id), do: {:ok, id}

  defp parse_wallet_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, ""} -> {:ok, int_id}
      _ -> :error
    end
  end

  defp parse_wallet_id(_), do: :error
end
