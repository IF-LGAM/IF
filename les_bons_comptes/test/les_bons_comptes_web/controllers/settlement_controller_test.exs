defmodule LesBonsComptesWeb.SettlementControllerTest do
  use LesBonsComptesWeb.ConnCase

  alias LesBonsComptes.Accounts
  alias LesBonsComptes.Expenses
  alias LesBonsComptes.Wallets

  defp create_user(attrs \\ %{}) do
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

  describe "POST /api/wallets/:id/settlements/mock (Action de remboursement mock pour un porte-monnaie clos - IF-85)" do
    test "retourne 422 si le porte-monnaie n'est pas clos", %{conn: conn} do
      owner = create_user(%{name: "Alice", email: "alice_mock_open@test.com"})
      bob = create_user(%{name: "Bob", email: "bob_mock_open@test.com"})

      {:ok, wallet} =
        Wallets.create_wallet(owner, %{name: "Ouvert", currency: "EUR"}, [
          %{name: "Bob", email: bob.email, user_id: bob.id}
        ])

      {:ok, _} = Expenses.create_expense(owner, wallet, %{title: "Courses", amount: "50.00"})

      bob_member = Enum.find(wallet.members, &(&1.name == "Bob"))
      alice_member = Enum.find(wallet.members, &(&1.name == "Alice"))

      params = %{
        "from_id" => bob_member.id,
        "to_id" => alice_member.id,
        "amount" => "25.00"
      }

      conn = post(conn, ~p"/api/wallets/#{wallet.id}/settlements/mock", params)
      assert response = json_response(conn, 422)
      assert response["error"] == "Le porte-monnaie doit être validé ou clos pour effectuer les remboursements"
    end

    test "retourne 200 si le porte-monnaie est validé (Étape 2) ou clos (Étape 3)", %{
      conn: conn
    } do
      owner = create_user(%{name: "Alice", email: "alice_mock_closed@test.com"})
      bob = create_user(%{name: "Bob", email: "bob_mock_closed@test.com"})

      {:ok, wallet} =
        Wallets.create_wallet(owner, %{name: "Clos", currency: "EUR"}, [
          %{name: "Bob", email: bob.email, user_id: bob.id}
        ])

      {:ok, _} = Expenses.create_expense(owner, wallet, %{title: "Courses", amount: "60.00"})

      # Validation du porte-monnaie (Étape 2)
      {:ok, _} = Wallets.validate_wallet(owner, wallet)

      bob_member = Enum.find(wallet.members, &(&1.name == "Bob"))
      alice_member = Enum.find(wallet.members, &(&1.name == "Alice"))

      params = %{
        "from_id" => bob_member.id,
        "to_id" => alice_member.id,
        "amount" => "30.00"
      }

      conn = post(conn, ~p"/api/wallets/#{wallet.id}/settlements/mock", params)
      assert response = json_response(conn, 200)

      assert response["status"] == "success"
      assert response["message"] == "Virement enregistré avec succès"
      assert s = response["settlement"]
      assert s["from_id"] == bob_member.id
      assert s["from_name"] == "Bob"
      assert s["to_id"] == alice_member.id
      assert s["to_name"] == "Alice"
      assert s["amount"] == "30.00"
      assert s["currency"] == "EUR"
      assert s["status"] == "settled"
      assert s["settled"] == true
      assert s["settled_at"] != nil
    end

    test "simule tous les remboursements lorsque aucun paramètre de virement spécifique n'est passé et clôture le porte-monnaie",
         %{conn: conn} do
      owner = create_user(%{name: "Alice", email: "alice_mock_all@test.com"})
      bob = create_user(%{name: "Bob", email: "bob_mock_all@test.com"})

      {:ok, wallet} =
        Wallets.create_wallet(owner, %{name: "Tous Remboursements", currency: "EUR"}, [
          %{name: "Bob", email: bob.email, user_id: bob.id}
        ])

      {:ok, _} = Expenses.create_expense(owner, wallet, %{title: "Repas", amount: "80.00"})
      {:ok, pending_wallet} = Wallets.validate_wallet(owner, wallet)

      conn = post(conn, ~p"/api/wallets/#{pending_wallet.id}/settlements/mock", %{})
      assert response = json_response(conn, 200)

      assert response["status"] == "success"
      assert response["settlements_count"] == 1
      assert [settlement] = response["settlements"]
      assert settlement["from_name"] == "Bob"
      assert settlement["to_name"] == "Alice"
      assert settlement["amount"] == "40.00"

      # Vérification de la clôture automatique
      assert Wallets.get_wallet!(wallet.id).status == "closed"
    end

    test "retourne 404 si le porte-monnaie n'existe pas", %{conn: conn} do
      conn = post(conn, ~p"/api/wallets/999999/settlements/mock", %{})
      assert response = json_response(conn, 404)
      assert response["error"] =~ "introuvable"
    end

    test "retourne 422 si les membres ou montants sont invalides sur un porte-monnaie clos", %{
      conn: conn
    } do
      owner = create_user()
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "Invalide"})
      {:ok, _} = Wallets.close_wallet(owner, wallet)

      [member] = wallet.members

      # Même membre
      conn1 =
        post(conn, ~p"/api/wallets/#{wallet.id}/settlements/mock", %{
          "from_id" => member.id,
          "to_id" => member.id,
          "amount" => "10.00"
        })

      assert json_response(conn1, 422)["error"] ==
               "L'émetteur et le récepteur doivent être distincts"

      # Montant négatif ou nul
      conn2 =
        post(conn, ~p"/api/wallets/#{wallet.id}/settlements/mock", %{
          "from_id" => member.id,
          "to_id" => 999_999,
          "amount" => "-5.00"
        })

      assert json_response(conn2, 422)["error"] ==
               "Membre introuvable dans ce porte-monnaie"
    end
  end
end
