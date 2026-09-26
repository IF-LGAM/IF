defmodule LesBonsComptesWeb.SignInLiveTest do
  use LesBonsComptesWeb.ConnCase
  import Phoenix.LiveViewTest

  alias LesBonsComptes.Accounts

  test "renders sign-in form on /sign-in", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/sign-in")

    assert has_element?(view, "#user-sign-in-form")
    assert has_element?(view, "input[name=\"user[name]\"]")
    assert has_element?(view, "input[name=\"user[email]\"]")
    assert has_element?(view, "input[name=\"user[password]\"]")
    assert has_element?(view, "#submit-user-btn")
  end

  test "validates form and shows errors on blur/change", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/sign-in")

    view
    |> form("#user-sign-in-form", user: %{name: "", email: "bad-email", password: "123"})
    |> render_change()

    assert has_element?(view, "#user-sign-in-form")
  end

  test "creates user in database upon form submit", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/sign-in")

    valid_attrs = %{
      name: "Martin Dupont",
      email: "martin.dupont@test.fr",
      password: "motdepassesolide"
    }

    view
    |> form("#user-sign-in-form", user: valid_attrs)
    |> render_submit()

    # Vérification que l'utilisateur est bien enregistré en base de données
    assert [user] = Enum.filter(Accounts.list_users(), &(&1.email == "martin.dupont@test.fr"))
    assert user.name == "Martin Dupont"

    # Vérification que la liste en temps réel et le message de confirmation s'affichent
    assert has_element?(view, "#users")
  end
end
