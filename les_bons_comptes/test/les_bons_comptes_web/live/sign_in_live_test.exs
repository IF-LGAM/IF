defmodule LesBonsComptesWeb.SignInLiveTest do
  use LesBonsComptesWeb.ConnCase
  import Phoenix.LiveViewTest

  alias LesBonsComptes.Accounts

  @user_attrs %{
    name: "Claire Martin",
    email: "claire@exemple.com",
    password: "password123"
  }

  test "renders sign-in login form on /sign-in", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/sign-in")

    assert has_element?(view, "#user-sign-in-form")
    assert has_element?(view, "input[name=\"user[email]\"]")
    assert has_element?(view, "input[name=\"user[password]\"]")
    assert has_element?(view, "#submit-login-btn")
    refute has_element?(view, "input[name=\"user[name]\"]")
    assert has_element?(view, "a[href=\"/sign-up\"]")
  end

  test "logs in user upon posting form with valid credentials", %{conn: conn} do
    {:ok, user} = Accounts.create_user(@user_attrs)

    conn =
      post(conn, ~p"/users/log_in", %{
        "user" => %{"email" => user.email, "password" => "password123"}
      })

    assert get_session(conn, :user_id) == user.id
    assert redirected_to(conn) == ~p"/"
  end

  test "redirects with error on invalid credentials", %{conn: conn} do
    conn =
      post(conn, ~p"/users/log_in", %{
        "user" => %{"email" => "inconnu@exemple.com", "password" => "mauvais_mdp"}
      })

    assert is_nil(get_session(conn, :user_id))
    assert redirected_to(conn) == ~p"/sign-in"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalide"
  end
end
