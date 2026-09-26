defmodule LesBonsComptesWeb.PageControllerTest do
  use LesBonsComptesWeb.ConnCase

  alias LesBonsComptes.Accounts

  test "GET / when unauthenticated shows welcome page with auth links", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)
    assert response =~ "Les Bons Comptes"
    assert response =~ "Créer un compte"
    assert response =~ "Se connecter"
  end

  test "GET / when authenticated shows user confirmation and disconnect button", %{conn: conn} do
    {:ok, user} =
      Accounts.create_user(%{
        name: "Julien Dupont",
        email: "julien@exemple.com",
        password: "password123"
      })

    conn =
      conn
      |> init_test_session(user_id: user.id)
      |> get(~p"/")

    response = html_response(conn, 200)
    assert response =~ "Bienvenue, Julien Dupont !"
    assert response =~ "julien@exemple.com"
    assert response =~ "Se déconnecter"
    assert response =~ "disconnect-user-btn"
  end
end
