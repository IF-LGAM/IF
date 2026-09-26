defmodule LesBonsComptesWeb.UserSessionControllerTest do
  use LesBonsComptesWeb.ConnCase

  alias LesBonsComptes.Accounts
  alias LesBonsComptesWeb.UserAuth

  @valid_user_attrs %{
    name: "Thomas Moreau",
    email: "thomas@exemple.com",
    password: "password123"
  }

  setup do
    {:ok, user} = Accounts.create_user(@valid_user_attrs)
    %{user: user}
  end

  describe "GET /users/log_in with token (auto-connexion post inscription)" do
    test "logs in user with valid token and sets session", %{conn: conn, user: user} do
      token = UserAuth.sign_user_token(user.id)
      conn = get(conn, ~p"/users/log_in?token=#{token}")

      assert get_session(conn, :user_id) == user.id
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Bienvenue #{user.name}"
    end

    test "fails with invalid or expired token", %{conn: conn} do
      conn = get(conn, ~p"/users/log_in?token=invalid_token")

      assert is_nil(get_session(conn, :user_id))
      assert redirected_to(conn) == ~p"/sign-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalide ou expiré"
    end
  end

  describe "POST /users/log_in with credentials" do
    test "logs in user with valid email and password", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => "password123"}
        })

      assert get_session(conn, :user_id) == user.id
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Connexion réussie"
    end

    test "fails with wrong credentials", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => "mauvais_mot_de_passe"}
        })

      assert is_nil(get_session(conn, :user_id))
      assert redirected_to(conn) == ~p"/sign-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalide"
    end
  end

  describe "DELETE /users/log_out" do
    test "logs out user and drops session", %{conn: conn, user: user} do
      conn =
        conn
        |> init_test_session(user_id: user.id)
        |> delete(~p"/users/log_out")

      assert is_nil(get_session(conn, :user_id))
      assert redirected_to(conn) == ~p"/sign-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "déconnecté"
    end
  end
end
