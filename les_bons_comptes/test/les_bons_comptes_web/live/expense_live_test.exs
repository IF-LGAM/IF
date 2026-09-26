defmodule LesBonsComptesWeb.ExpenseLiveTest do
  use LesBonsComptesWeb.ConnCase

  import Phoenix.LiveViewTest
  alias LesBonsComptes.Accounts
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
end
