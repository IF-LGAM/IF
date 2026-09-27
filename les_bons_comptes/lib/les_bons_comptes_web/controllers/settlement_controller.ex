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

  defp parse_wallet_id(id) when is_integer(id), do: {:ok, id}

  defp parse_wallet_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, ""} -> {:ok, int_id}
      _ -> :error
    end
  end

  defp parse_wallet_id(_), do: :error
end
