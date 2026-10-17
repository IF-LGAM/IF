defmodule LesBonsComptesWeb.PaginationLiveTest do
  use LesBonsComptesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  alias LesBonsComptes.Accounts
  alias LesBonsComptes.Expenses
  alias LesBonsComptes.Wallets

  defp create_user(name, email) do
    {:ok, user} =
      Accounts.create_user(%{
        name: name,
        email: email,
        password: "password123"
      })

    user
  end

  defp authenticate_user(conn, user) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
  end

  describe "Wallets Dashboard Pagination (/wallets)" do
    test "paginates user wallets across multiple pages and preserves status filters", %{conn: conn} do
      unique = System.unique_integer([:positive])
      user = create_user("Alice Paging #{unique}", "alice_paging_#{unique}@test.com")
      conn = authenticate_user(conn, user)

      # Create 11 wallets for Alice (some open, some closed)
      for i <- 1..11 do
        {:ok, wallet} =
          Wallets.create_wallet(user, %{
            name: "Porte-monnaie #{String.pad_leading("#{i}", 2, "0")}",
            currency: "EUR",
            description: "Description test #{i}"
          })

        if rem(i, 2) == 0 do
          {:ok, _closed} = Wallets.close_wallet(user, wallet)
        end
      end

      # 1. First page: 8 wallets out of 11
      {:ok, view, html} = live(conn, ~p"/wallets")

      assert has_element?(view, "#wallets-pagination")
      assert has_element?(view, "#wallets-pagination-summary")
      assert html =~ "Affichage de"
      assert html =~ "1"
      assert html =~ "8"
      assert html =~ "11"
      assert has_element?(view, "#wallets-pagination-next-btn")
      assert has_element?(view, "#wallets-pagination-page-2-btn")

      # 2. Page 2 via patch: 3 remaining wallets
      {:ok, view_page2, html_page2} = live(conn, ~p"/wallets?page=2")

      assert has_element?(view_page2, "#wallets-pagination")
      assert html_page2 =~ "9"
      assert html_page2 =~ "11"
      assert has_element?(view_page2, "#wallets-pagination-prev-btn")

      # 3. Pagination with status filter (/wallets/open)
      {:ok, view_open, _html_open} = live(conn, ~p"/wallets/open")
      assert has_element?(view_open, "#wallets-grid")
    end
  end

  describe "Invited Wallets Pagination (/wallets?tab=invited)" do
    test "paginates invited wallets across pages", %{conn: conn} do
      unique = System.unique_integer([:positive])
      alice = create_user("Alice Host #{unique}", "alice_host_#{unique}@test.com")
      bob = create_user("Bob Guest #{unique}", "bob_guest_#{unique}@test.com")
      conn = authenticate_user(conn, bob)

      # Alice creates 8 wallets and invites Bob
      for i <- 1..8 do
        {:ok, wallet} =
          Wallets.create_wallet(alice, %{
            name: "Projet Partagé #{String.pad_leading("#{i}", 2, "0")}",
            currency: "EUR"
          })

        {:ok, _invitation} = Wallets.create_invitation(alice, wallet, %{email: bob.email})
      end

      # Page 1: 6 invitations out of 8 (page size 6)
      {:ok, view, html} = live(conn, ~p"/wallets?tab=invited")

      assert has_element?(view, "#invited-wallets-grid")
      assert has_element?(view, "#invited-wallets-pagination")
      assert html =~ "Affichage de"
      assert html =~ "6"
      assert html =~ "8"
      assert has_element?(view, "#invited-wallets-pagination-next-btn")

      # Page 2: remaining 2 invitations
      {:ok, view_page2, html_page2} = live(conn, ~p"/wallets?tab=invited&page=2")
      assert has_element?(view_page2, "#invited-wallets-pagination")
      assert html_page2 =~ "7"
      assert html_page2 =~ "8"
    end
  end

  describe "Wallet Details Expenses Pagination (/wallets/:id)" do
    test "paginates expenses list while keeping global totals accurate", %{conn: conn} do
      unique = System.unique_integer([:positive])
      alice = create_user("Alice Exp #{unique}", "alice_exp_#{unique}@test.com")
      conn = authenticate_user(conn, alice)

      {:ok, wallet} =
        Wallets.create_wallet(alice, %{
          name: "Voyage Paging #{unique}",
          currency: "EUR"
        })

      # Add 12 expenses of 10.00 EUR each (total = 120.00 EUR)
      for i <- 1..12 do
        {:ok, _expense} =
          Expenses.create_expense(alice, wallet, %{
            title: "Dépense numéro #{String.pad_leading("#{i}", 2, "0")}",
            amount: "10.00",
            date: Date.utc_today()
          })
      end

      # Page 1: 8 expenses out of 12
      {:ok, view, html} = live(conn, ~p"/wallets/#{wallet.id}")

      assert has_element?(view, "#wallet-expenses-list")
      assert has_element?(view, "#expenses-pagination")
      assert html =~ "Affichage de"
      assert html =~ "1"
      assert html =~ "8"
      assert html =~ "12"

      # Verify global total remains 120.00 EUR and not just 80.00 EUR
      assert html =~ "120.00"
      assert has_element?(view, "#expenses-pagination-next-btn")

      # Navigate to Page 2
      {:ok, view_page2, html_page2} = live(conn, ~p"/wallets/#{wallet.id}?page=2")
      assert has_element?(view_page2, "#wallet-expenses-list")
      assert html_page2 =~ "9"
      assert html_page2 =~ "12"
      assert html_page2 =~ "120.00"
    end
  end
end
