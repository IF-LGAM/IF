defmodule LesBonsComptesWeb.ExpenseLiveTest do
  use LesBonsComptesWeb.ConnCase

  import Phoenix.LiveViewTest
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

  defp authenticate_user(conn, user) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
  end

  defp setup_wallet do
    creator = create_user(%{name: "Alice", email: "alice@test.com"})
    bob = create_user(%{name: "Bob", email: "bob@test.com"})

    {:ok, wallet} =
      Wallets.create_wallet(creator, %{name: "Voyage Barcelone", currency: "EUR"}, [
        %{name: "Bob", email: bob.email, user_id: bob.id}
      ])

    %{creator: creator, bob: bob, wallet: wallet}
  end

  describe "Déclaration de dépense (IF-65, IF-66, IF-67, IF-68, IF-69, IF-70, IF-71)" do
    test "affiche le bouton d'ajout de dépense sur la page du porte-monnaie (IF-65)", %{
      conn: conn
    } do
      %{creator: creator, wallet: wallet} = setup_wallet()
      conn = authenticate_user(conn, creator)

      {:ok, view, _html} = live(conn, ~p"/wallets/#{wallet.id}")

      assert has_element?(view, "#add-expense-btn")
      assert has_element?(view, "#total-expenses-amount")
      assert has_element?(view, "#no-expenses-message")
    end

    test "affiche le formulaire de déclaration avec le membre connecté pré-sélectionné (IF-65, IF-68)",
         %{conn: conn} do
      %{creator: creator, wallet: wallet} = setup_wallet()
      conn = authenticate_user(conn, creator)

      {:ok, view, _html} = live(conn, ~p"/wallets/#{wallet.id}/expenses/new")

      assert has_element?(view, "#expense-form")
      assert has_element?(view, "#expense-title-input")
      assert has_element?(view, "#expense-amount-input")
      assert has_element?(view, "#expense-date-input")
      assert has_element?(view, "#expense-payer-select")

      # Vérifie que le propriétaire Alice est pré-sélectionné par défaut
      [owner_member | _] = wallet.members

      assert has_element?(
               view,
               "#expense-payer-select option[selected][value='#{owner_member.id}']"
             )
    end

    test "valide les erreurs de saisie en temps réel (IF-67, IF-69)", %{conn: conn} do
      %{creator: creator, wallet: wallet} = setup_wallet()
      conn = authenticate_user(conn, creator)

      {:ok, view, _html} = live(conn, ~p"/wallets/#{wallet.id}/expenses/new")

      # Test validation montant <= 0
      view
      |> form("#expense-form", expense: %{title: "Courses", amount: "0"})
      |> render_change()

      assert render(view) =~ "doit être supérieur à 0"

      # Test validation montant négatif
      view
      |> form("#expense-form", expense: %{title: "Courses", amount: "-10"})
      |> render_change()

      assert render(view) =~ "doit être supérieur à 0"

      # Test validation date dans le futur
      future_date_str = Date.to_iso8601(Date.add(Date.utc_today(), 2))

      view
      |> form("#expense-form", expense: %{title: "Courses", amount: "15", date: future_date_str})
      |> render_change()

      assert render(view) =~ "la date ne peut pas être dans le futur"
    end

    test "crée avec succès une dépense et redirige avec confirmation (IF-66, IF-70, IF-71)", %{
      conn: conn
    } do
      %{creator: creator, wallet: wallet} = setup_wallet()
      conn = authenticate_user(conn, creator)

      {:ok, view, _html} = live(conn, ~p"/wallets/#{wallet.id}/expenses/new")

      {:ok, show_view, html} =
        view
        |> form("#expense-form",
          expense: %{
            title: "Restaurant Paella",
            amount: "85.50",
            description: "Dîner du samedi soir"
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/wallets/#{wallet.id}")

      # Confirmation affichée (IF-71)
      assert html =~ "Restaurant Paella"
      assert html =~ "85.50"
      assert html =~ "a été enregistrée avec succès"

      # Affichage dans la liste des dépenses du porte-monnaie
      assert has_element?(show_view, "#wallet-expenses-list")
      assert has_element?(show_view, "#total-expenses-amount")
      assert render(show_view) =~ "85.50 EUR"
      assert render(show_view) =~ "Payé par"
      assert render(show_view) =~ "Alice"
    end

    test "un membre invité (Bob) peut déclarer sa propre dépense qui lui est affectée (IF-68, IF-70)",
         %{conn: conn} do
      %{bob: bob, wallet: wallet} = setup_wallet()
      conn = authenticate_user(conn, bob)

      {:ok, view, _html} = live(conn, ~p"/wallets/#{wallet.id}/expenses/new")

      # Bob est présélectionné par défaut
      bob_member = Enum.find(wallet.members, &(&1.name == "Bob"))

      assert has_element?(
               view,
               "#expense-payer-select option[selected][value='#{bob_member.id}']"
             )

      {:ok, show_view, html} =
        view
        |> form("#expense-form",
          expense: %{
            title: "Essence station",
            amount: "40.00"
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/wallets/#{wallet.id}")

      assert html =~ "a été enregistrée avec succès"
      assert render(show_view) =~ "Essence station"
      assert render(show_view) =~ "Bob"
      assert render(show_view) =~ "40.00 EUR"
    end

    test "refuse l'accès à un utilisateur qui n'est pas membre du porte-monnaie", %{conn: conn} do
      %{wallet: wallet} = setup_wallet()
      intruder = create_user(%{name: "Intrus", email: "intrus@test.com"})
      conn = authenticate_user(conn, intruder)

      {:ok, _view, html} =
        live(conn, ~p"/wallets/#{wallet.id}/expenses/new")
        |> follow_redirect(conn, ~p"/wallets")

      assert html =~ "Vous devez être membre de ce porte-monnaie"
    end
  end

  describe "Suppression d'une dépense (IF-77, IF-78, IF-79, IF-80, IF-81)" do
    test "affiche le bouton de suppression pour le créateur de la dépense ou le propriétaire (IF-81)",
         %{conn: conn} do
      %{creator: creator, bob: bob, wallet: wallet} = setup_wallet()

      # Bob crée une dépense
      {:ok, expense} =
        Expenses.create_expense(bob, wallet, %{title: "Courses tapas", amount: "35.00"})

      # 1. Bob voit le bouton de suppression sur sa dépense
      conn_bob = authenticate_user(conn, bob)
      {:ok, view_bob, _html} = live(conn_bob, ~p"/wallets/#{wallet.id}")
      assert has_element?(view_bob, "#delete-expense-btn-#{expense.id}")

      # 2. Le propriétaire Alice voit aussi le bouton de suppression (IF-81)
      conn_alice = authenticate_user(conn, creator)
      {:ok, view_alice, _html} = live(conn_alice, ~p"/wallets/#{wallet.id}")
      assert has_element?(view_alice, "#delete-expense-btn-#{expense.id}")
    end

    test "masque le bouton de suppression pour un membre non autorisé (IF-81)", %{conn: conn} do
      %{creator: creator, bob: bob, wallet: wallet} = setup_wallet()
      charlie = create_user(%{name: "Charlie", email: "charlie@test.com"})

      {:ok, _member} =
        Wallets.add_member(creator, wallet, %{
          name: "Charlie",
          email: charlie.email,
          user_id: charlie.id
        })

      # Bob crée une dépense
      {:ok, expense} =
        Expenses.create_expense(bob, wallet, %{title: "Cinéma", amount: "22.00"})

      # Charlie (qui n'est ni le propriétaire Alice, ni le payeur/créateur Bob) ne voit pas le bouton
      conn_charlie = authenticate_user(conn, charlie)
      {:ok, view_charlie, _html} = live(conn_charlie, ~p"/wallets/#{wallet.id}")

      assert has_element?(view_charlie, "#expense-item-#{expense.id}")
      refute has_element?(view_charlie, "#delete-expense-btn-#{expense.id}")
    end

    test "supprime la dépense avec confirmation et met à jour le total (IF-78, IF-80)", %{
      conn: conn
    } do
      %{bob: bob, wallet: wallet} = setup_wallet()

      {:ok, expense} =
        Expenses.create_expense(bob, wallet, %{title: "Billets de bus", amount: "15.00"})

      conn = authenticate_user(conn, bob)
      {:ok, view, _html} = live(conn, ~p"/wallets/#{wallet.id}")

      assert has_element?(view, "#expense-item-#{expense.id}")
      assert render(view) =~ "15.00 EUR"

      # Déclenche la suppression
      render_click(element(view, "#delete-expense-btn-#{expense.id}"))

      # Notification flash affichée (IF-80)
      assert render(view) =~ "La dépense « Billets de bus » a été supprimée avec succès."

      # La dépense a disparu de la liste
      refute has_element?(view, "#expense-item-#{expense.id}")
      assert render(view) =~ "0.00 EUR"
      assert has_element?(view, "#no-expenses-message")
    end

    test "rejette la suppression d'un membre non autorisé (IF-79)", %{conn: conn} do
      %{creator: creator, bob: bob, wallet: wallet} = setup_wallet()
      charlie = create_user(%{name: "Charlie", email: "charlie@test.com"})

      {:ok, _member} =
        Wallets.add_member(creator, wallet, %{
          name: "Charlie",
          email: charlie.email,
          user_id: charlie.id
        })

      {:ok, expense} =
        Expenses.create_expense(bob, wallet, %{title: "Pizza", amount: "18.00"})

      conn_charlie = authenticate_user(conn, charlie)
      {:ok, view_charlie, _html} = live(conn_charlie, ~p"/wallets/#{wallet.id}")

      # Envoi direct de l'événement delete_expense par Charlie
      render_click(view_charlie, "delete_expense", %{"id" => to_string(expense.id)})

      assert render(view_charlie) =~ "pas autorisé à supprimer cette dépense"
      assert Expenses.get_expense!(expense.id) != nil
    end

    test "masque le bouton de suppression et rejette la suppression hors phase de déclaration", %{conn: conn} do
      %{creator: creator, wallet: wallet} = setup_wallet()
      {:ok, expense} = Expenses.create_expense(creator, wallet, %{title: "Courses", amount: "30.00"})

      # Validation -> Étape 2
      {:ok, _pending} = Wallets.validate_wallet(creator, wallet)

      conn = authenticate_user(conn, creator)
      {:ok, view, _html} = live(conn, ~p"/wallets/#{wallet.id}")

      refute has_element?(view, "#delete-expense-btn-#{expense.id}")

      # Tentative directe de suppression par événement
      render_click(view, "delete_expense", %{"id" => to_string(expense.id)})
      assert render(view) =~ "Impossible de supprimer une dépense lorsque le porte-monnaie n&#39;est plus en phase de déclaration"
      assert Expenses.get_expense!(expense.id) != nil
    end
  end

  describe "Modification de dépense (ExpenseEdit LiveView)" do
    test "affiche le bouton de modification uniquement pour l'auteur ou le payeur en phase ouverte", %{conn: conn} do
      %{creator: creator, bob: bob, wallet: wallet} = setup_wallet()
      charlie = create_user(%{name: "Charlie", email: "charlie_edit@test.com"})

      {:ok, _member} =
        Wallets.add_member(creator, wallet, %{
          name: "Charlie",
          email: charlie.email,
          user_id: charlie.id
        })

      # Bob est le créateur et le payeur
      {:ok, expense1} = Expenses.create_expense(bob, wallet, %{title: "Dépense Bob", amount: "20.00"})

      # Bob voit le bouton d'édition
      conn_bob = authenticate_user(conn, bob)
      {:ok, view_bob, _html} = live(conn_bob, ~p"/wallets/#{wallet.id}")
      assert has_element?(view_bob, "#edit-expense-btn-#{expense1.id}")

      # Charlie ne voit pas le bouton d'édition
      conn_charlie = authenticate_user(conn, charlie)
      {:ok, view_charlie, _html} = live(conn_charlie, ~p"/wallets/#{wallet.id}")
      refute has_element?(view_charlie, "#edit-expense-btn-#{expense1.id}")

      # Alice (créatrice du wallet mais pas auteur/payeur de cette dépense) ne voit pas le bouton
      conn_alice = authenticate_user(conn, creator)
      {:ok, view_alice, _html} = live(conn_alice, ~p"/wallets/#{wallet.id}")
      refute has_element?(view_alice, "#edit-expense-btn-#{expense1.id}")

      # Cas où l'auteur et le payeur sont distincts : Alice ajoute pour Bob
      bob_member = Enum.find(wallet.members, &(&1.name == "Bob"))
      {:ok, expense2} = Expenses.create_expense(creator, wallet, %{title: "Cadeau", amount: "50.00", payer_id: bob_member.id})

      # Alice (qui a ajouté) voit le bouton d'édition
      {:ok, view_alice2, _html} = live(conn_alice, ~p"/wallets/#{wallet.id}")
      assert has_element?(view_alice2, "#edit-expense-btn-#{expense2.id}")

      # Bob (qui est le compte payeur) voit aussi le bouton d'édition
      {:ok, view_bob2, _html} = live(conn_bob, ~p"/wallets/#{wallet.id}")
      assert has_element?(view_bob2, "#edit-expense-btn-#{expense2.id}")
    end

    test "masque le bouton de modification hors phase de déclaration", %{conn: conn} do
      %{creator: creator, wallet: wallet} = setup_wallet()
      {:ok, expense} = Expenses.create_expense(creator, wallet, %{title: "Courses", amount: "30.00"})

      {:ok, _pending} = Wallets.validate_wallet(creator, wallet)

      conn = authenticate_user(conn, creator)
      {:ok, view, _html} = live(conn, ~p"/wallets/#{wallet.id}")
      refute has_element?(view, "#edit-expense-btn-#{expense.id}")
    end

    test "permet de modifier avec succès une dépense via le formulaire ExpenseEdit", %{conn: conn} do
      %{creator: creator, wallet: wallet} = setup_wallet()
      {:ok, expense} = Expenses.create_expense(creator, wallet, %{title: "Ancien titre", amount: "40.00"})

      conn = authenticate_user(conn, creator)
      {:ok, edit_view, _html} = live(conn, ~p"/wallets/#{wallet.id}/expenses/#{expense.id}/edit")

      assert has_element?(edit_view, "#expense-form")
      assert has_element?(edit_view, "#expense-title-input[value='Ancien titre']")

      # Modification et soumission
      edit_view
      |> form("#expense-form", expense: %{title: "Nouveau titre", amount: "55.00"})
      |> render_submit()

      assert_redirect(edit_view, ~p"/wallets/#{wallet.id}")

      reloaded = Expenses.get_expense!(expense.id)
      assert reloaded.title == "Nouveau titre"
      assert Decimal.equal?(reloaded.amount, Decimal.new("55.00"))
    end

    test "redirige avec un message d'erreur si l'utilisateur n'est pas autorisé", %{conn: conn} do
      %{creator: creator, wallet: wallet} = setup_wallet()
      charlie = create_user(%{name: "Charlie", email: "charlie_unauth@test.com"})

      {:ok, _member} =
        Wallets.add_member(creator, wallet, %{
          name: "Charlie",
          email: charlie.email,
          user_id: charlie.id
        })

      {:ok, expense} = Expenses.create_expense(creator, wallet, %{title: "Privé", amount: "30.00"})

      conn_charlie = authenticate_user(conn, charlie)
      assert {:error, {:live_redirect, %{to: to, flash: %{"error" => msg}}}} =
               live(conn_charlie, ~p"/wallets/#{wallet.id}/expenses/#{expense.id}/edit")

      assert to == ~p"/wallets/#{wallet.id}"
      assert msg =~ "pas autorisé à modifier cette dépense"
    end

    test "redirige avec un message d'erreur si le porte-monnaie n'est plus en phase de déclaration", %{conn: conn} do
      %{creator: creator, wallet: wallet} = setup_wallet()
      {:ok, expense} = Expenses.create_expense(creator, wallet, %{title: "Courses", amount: "30.00"})

      {:ok, _pending} = Wallets.validate_wallet(creator, wallet)

      conn = authenticate_user(conn, creator)
      assert {:error, {:live_redirect, %{to: to, flash: %{"error" => msg}}}} =
               live(conn, ~p"/wallets/#{wallet.id}/expenses/#{expense.id}/edit")

      assert to == ~p"/wallets/#{wallet.id}"
      assert msg =~ "n'est plus en phase de déclaration"
    end
  end
end
