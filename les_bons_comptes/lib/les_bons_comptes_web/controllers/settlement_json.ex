defmodule LesBonsComptesWeb.SettlementJSON do
  @moduledoc """
  JSON view for the settlements and transfers API (IF-84).
  """

  @doc """
  Renders the list of optimized transfers along with creditors and debtors summary.
  """
  def index(%{
        wallet: wallet,
        total_expenses: total_expenses,
        fair_share: fair_share,
        settlements: settlements,
        creditors: creditors,
        debtors: debtors
      }) do
    %{
      wallet_id: wallet.id,
      wallet_name: wallet.name,
      currency: wallet.currency,
      total_expenses: format_decimal(total_expenses),
      fair_share: format_decimal(fair_share),
      settlements_count: length(settlements),
      settlements: Enum.map(settlements, &data_settlement/1),
      creditors: Enum.map(creditors, &data_creditor/1),
      debtors: Enum.map(debtors, &data_debtor/1)
    }
  end

  @doc """
  Renders confirmation of a completed transfer (IF-85).
  """
  def mock(%{settlement: settlement}) do
    %{
      status: "success",
      message: "Virement enregistré avec succès",
      settlement: data_mock_settlement(settlement)
    }
  end

  @doc """
  Renders the list of all completed transfers for a wallet (IF-85).
  """
  def mock_all(%{settlements: settlements, wallet: wallet}) do
    %{
      status: "success",
      message: "Tous les virements ont été effectués avec succès",
      wallet_id: wallet.id,
      wallet_name: wallet.name,
      currency: wallet.currency,
      settlements_count: length(settlements),
      settlements: Enum.map(settlements, &data_mock_settlement/1)
    }
  end

  defp data_mock_settlement(s) do
    %{
      id: s.id,
      wallet_id: s.wallet_id,
      from_id: s.from_id,
      from_name: s.from_name,
      from_email: s.from_email,
      to_id: s.to_id,
      to_name: s.to_name,
      to_email: s.to_email,
      amount: format_decimal(s.amount),
      currency: s.currency,
      status: s.status,
      settled: s[:settled] || true,
      simulated: s[:simulated] || true,
      settled_at: DateTime.to_iso8601(s.settled_at)
    }
  end

  defp data_settlement(settlement) do
    %{
      from_id: settlement.from_id,
      from_name: settlement.from_name,
      from_email: settlement.from_email,
      to_id: settlement.to_id,
      to_name: settlement.to_name,
      to_email: settlement.to_email,
      amount: format_decimal(settlement.amount),
      currency: settlement.currency
    }
  end

  defp data_creditor(creditor) do
    %{
      member_id: creditor.member_id,
      name: creditor.name,
      email: creditor.email,
      total_paid: format_decimal(creditor.total_paid),
      fair_share: format_decimal(creditor.fair_share),
      amount_to_receive: format_decimal(creditor.amount_to_receive)
    }
  end

  defp data_debtor(debtor) do
    %{
      member_id: debtor.member_id,
      name: debtor.name,
      email: debtor.email,
      total_paid: format_decimal(debtor.total_paid),
      fair_share: format_decimal(debtor.fair_share),
      amount_to_pay: format_decimal(debtor.amount_to_pay)
    }
  end

  defp format_decimal(%Decimal{} = dec) do
    :erlang.float_to_binary(Decimal.to_float(dec), decimals: 2)
  end

  defp format_decimal(num) when is_number(num) do
    :erlang.float_to_binary(num / 1.0, decimals: 2)
  end

  defp format_decimal(_), do: "0.00"
end
