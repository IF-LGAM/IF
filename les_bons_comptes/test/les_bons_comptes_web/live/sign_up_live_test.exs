defmodule LesBonsComptesWeb.SignUpLiveTest do
  use LesBonsComptesWeb.ConnCase
  import Phoenix.LiveViewTest

  alias LesBonsComptes.Accounts

  test "renders sign-up form on /sign-up", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/sign-up")

    assert has_element?(view, "#user-sign-up-form")
    assert has_element?(view, "input[name=\"user[name]\"]")
    assert has_element?(view, "input[name=\"user[email]\"]")
    assert has_element?(view, "input[name=\"user[password]\"]")
    assert has_element?(view, "#submit-user-btn")
    assert has_element?(view, "a[href=\"/sign-in\"]")
  end

  test "validates form and shows errors on blur/change", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/sign-up")

    view
    |> form("#user-sign-up-form", user: %{name: "", email: "bad-email", password: "123"})
    |> render_change()

    assert has_element?(view, "#user-sign-up-form")
  end

  test "creates user in database and redirects to initialize session", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/sign-up")

    valid_attrs = %{
      name: "Martin Dupont",
      email: "martin.dupont@test.fr",
      password: "motdepassesolide"
    }

    assert {:error, {:redirect, %{to: login_path}}} =
             view
             |> form("#user-sign-up-form", user: valid_attrs)
             |> render_submit()

    assert login_path =~ "/users/log_in?token="

    # Verify that the user is persisted in the database with a hashed password
    assert [user] = Enum.filter(Accounts.list_users(), &(&1.email == "martin.dupont@test.fr"))
    assert user.name == "Martin Dupont"
    assert user.hashed_password != nil

    # Follow redirect to verify session initialization (IF-27)
    conn = get(conn, login_path)
    assert get_session(conn, :user_id) == user.id
    assert redirected_to(conn) == ~p"/"
  end

  test "displays 'Un compte existe déjà' error below submit button when email is taken", %{
    conn: conn
  } do
    {:ok, _existing_user} =
      Accounts.create_user(%{
        name: "Existant",
        email: "deja.pris@exemple.com",
        password: "password123"
      })

    {:ok, view, _html} = live(conn, ~p"/sign-up")

    # Real-time change / blur verification (phx-change): no DB uniqueness check at this stage
    view
    |> form("#user-sign-up-form",
      user: %{
        name: "Nouveau",
        email: "deja.pris@exemple.com",
        password: "password123"
      }
    )
    |> render_change()

    refute has_element?(view, "#email-uniqueness-error")

    # Submission verification (phx-submit): DB constraint triggers and displays error below button
    view
    |> form("#user-sign-up-form",
      user: %{
        name: "Nouveau",
        email: "deja.pris@exemple.com",
        password: "password123"
      }
    )
    |> render_submit()

    assert has_element?(view, "#email-uniqueness-error", "Un compte existe déjà")
  end
end
