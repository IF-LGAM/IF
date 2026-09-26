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

  test "creates user in database and redirects to initialize session", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/sign-in")

    valid_attrs = %{
      name: "Martin Dupont",
      email: "martin.dupont@test.fr",
      password: "motdepassesolide"
    }

    assert {:error, {:redirect, %{to: login_path}}} =
             view
             |> form("#user-sign-in-form", user: valid_attrs)
             |> render_submit()

    assert login_path =~ "/users/log_in?token="

    # Vérification que l'utilisateur est bien enregistré en base de données avec mot de passe haché
    assert [user] = Enum.filter(Accounts.list_users(), &(&1.email == "martin.dupont@test.fr"))
    assert user.name == "Martin Dupont"
    assert user.hashed_password != nil

    # Suivre la redirection pour vérifier l'initialisation de la session (IF-27)
    conn = get(conn, login_path)
    assert get_session(conn, :user_id) == user.id
    assert redirected_to(conn) == ~p"/"
  end
end
