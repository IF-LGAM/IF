defmodule LesBonsComptesWeb.SettlementControllerTest do
  use LesBonsComptesWeb.ConnCase

  alias LesBonsComptes.Accounts
  alias LesBonsComptes.Expenses
  alias LesBonsComptes.Wallets

  defp create_user(attrs) do
    unique_suffix = System.unique_integer([:positive])

    default_attrs = %{
      name: "Utilisateur #{unique_suffix}",
      email: "user_#{unique_suffix}@example.com",
      password: "password123"
    }

    {:ok, user} = Accounts.create_user(Map.merge(default_attrs, attrs))
    user
  end

  describe "GET /api/wallets/:id/settlements (Exposition de l'algorithme de remboursement via une API)" do
    test "retourne 200 et les virements optimisés pour un porte-monnaie existant", %{conn: conn} do
      owner = create_user(%{name: "Alice", email: "alice_api@example.com"})
      bob = create_user(%{name: "Bob", email: "bob_api@example.com"})
      charlie = create_user(%{name: "Charlie", email: "charlie_api@example.com"})

      {:ok, wallet} =
        Wallets.create_wallet(owner, %{name: "Week-end Rome", currency: "EUR"}, [
          %{name: "Bob", email: bob.email, user_id: bob.id},
          %{name: "Charlie", email: charlie.email, user_id: charlie.id}
        ])

      # Alice paie 90€ -> part 30€ chacun
      {:ok, _expense} =
        Expenses.create_expense(owner, wallet, %{
          title: "Appartement",
          amount: "90.00"
        })

      conn = get(conn, ~p"/api/wallets/#{wallet.id}/settlements")
      assert response = json_response(conn, 200)

      assert response["wallet_id"] == wallet.id
      assert response["wallet_name"] == "Week-end Rome"
      assert response["currency"] == "EUR"
      assert response["total_expenses"] == "90.00"
      assert response["fair_share"] == "30.00"
      assert response["settlements_count"] == 2

      # Les virements proposés
      settlements = response["settlements"]
      assert length(settlements) == 2

      settlement_payers = Enum.map(settlements, & &1["from_name"]) |> Enum.sort()
      assert settlement_payers == ["Bob", "Charlie"]

      Enum.each(settlements, fn s ->
        assert s["to_name"] == "Alice"
        assert s["amount"] == "30.00"
        assert s["currency"] == "EUR"
      end)

      # Créanciers et débiteurs détaillés
      assert length(response["creditors"]) == 1
      assert hd(response["creditors"])["name"] == "Alice"
      assert hd(response["creditors"])["amount_to_receive"] == "60.00"

      assert length(response["debtors"]) == 2
    end

    test "retourne une liste vide de virements si le porte-monnaie n'a aucune dépense", %{
      conn: conn
    } do
      owner = create_user(%{name: "Alice"})
      bob = create_user(%{name: "Bob"})

      {:ok, wallet} =
        Wallets.create_wallet(owner, %{name: "Voyage Vide", currency: "EUR"}, [
          %{name: "Bob", email: bob.email, user_id: bob.id}
        ])

      conn = get(conn, ~p"/api/wallets/#{wallet.id}/settlements")
      assert response = json_response(conn, 200)

      assert response["wallet_id"] == wallet.id
      assert response["total_expenses"] == "0.00"
      assert response["settlements_count"] == 0
      assert response["settlements"] == []
      assert response["creditors"] == []
      assert response["debtors"] == []
    end

    test "retourne une liste vide de virements si tous les comptes sont équilibrés", %{conn: conn} do
      owner = create_user(%{name: "Alice"})
      bob = create_user(%{name: "Bob"})

      {:ok, wallet} =
        Wallets.create_wallet(owner, %{name: "Équilibré", currency: "EUR"}, [
          %{name: "Bob", email: bob.email, user_id: bob.id}
        ])

      {:ok, _} =
        Expenses.create_expense(owner, wallet, %{title: "Dépense Alice", amount: "50.00"})

      {:ok, _} = Expenses.create_expense(bob, wallet, %{title: "Dépense Bob", amount: "50.00"})

      conn = get(conn, ~p"/api/wallets/#{wallet.id}/settlements")
      assert response = json_response(conn, 200)

      assert response["total_expenses"] == "100.00"
      assert response["fair_share"] == "50.00"
      assert response["settlements_count"] == 0
      assert response["settlements"] == []
      assert response["creditors"] == []
      assert response["debtors"] == []
    end

    test "retourne 404 si le porte-monnaie n'existe pas", %{conn: conn} do
      conn = get(conn, ~p"/api/wallets/999999/settlements")
      assert response = json_response(conn, 404)
      assert response["error"] =~ "introuvable"
    end

    test "retourne 404 si l'identifiant est invalide", %{conn: conn} do
      conn = get(conn, ~p"/api/wallets/abc/settlements")
      assert response = json_response(conn, 404)
      assert response["error"] =~ "introuvable"
    end
  end
end
