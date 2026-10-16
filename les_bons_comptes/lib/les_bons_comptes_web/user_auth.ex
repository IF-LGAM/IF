defmodule LesBonsComptesWeb.UserAuth do
  @moduledoc """
  Authentication and session management module for Les Bons Comptes.
  Handles session persistence via signed cookies, auto-login tokens post-registration,
  and mount hooks for Phoenix LiveView.
  """

  use LesBonsComptesWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias LesBonsComptes.Accounts

  # Auto-login token validity duration post-registration (in seconds)
  @token_max_age 60

  @doc """
  Logs in a user by storing their ID in the signed session.
  Renews session ID to prevent session fixation attacks.
  """
  def log_in_user(conn, user, return_to \\ ~p"/") do
    conn
    |> configure_session(renew: true)
    |> put_session(:user_id, user.id)
    |> put_session(:live_socket_id, "users_sessions:#{user.id}")
    |> redirect(to: return_to)
  end

  @doc """
  Logs out the user by clearing their current session.
  """
  def log_out_user(conn) do
    if live_socket_id = get_session(conn, :live_socket_id) do
      LesBonsComptesWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> configure_session(drop: true)
    |> clear_session()
    |> redirect(to: ~p"/sign-in")
  end

  @doc """
  Plug that extracts the current user from the signed session
  and assigns it to `conn.assigns[:current_user]`.
  """
  def fetch_current_user(conn, _opts) do
    user_id = get_session(conn, :user_id)
    user = user_id && Accounts.get_user(user_id)
    assign(conn, :current_user, user)
  end

  @doc """
  Generates an ephemeral signed token to log in the user immediately
  after account creation from a LiveView.
  """
  def sign_user_token(user_id) do
    Phoenix.Token.sign(LesBonsComptesWeb.Endpoint, "user_session", user_id)
  end

  @doc """
  Verifies the ephemeral auto-login token.
  """
  def verify_user_token(token) do
    Phoenix.Token.verify(LesBonsComptesWeb.Endpoint, "user_session", token,
      max_age: @token_max_age
    )
  end

  @doc """
  `on_mount` hook for Phoenix LiveView to assign the current user
  from the WebSocket session.
  """
  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont, mount_current_user(socket, session)}
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(
          :error,
          "Vous devez être connecté pour accéder à cette page."
        )
        |> Phoenix.LiveView.redirect(to: ~p"/sign-in")

      {:halt, socket}
    end
  end

  defp mount_current_user(socket, session) do
    socket =
      Phoenix.Component.assign_new(socket, :current_user, fn ->
        if user_id = session["user_id"] do
          Accounts.get_user(user_id)
        end
      end)

    Phoenix.Component.assign_new(socket, :pending_invitations, fn ->
      if user = socket.assigns[:current_user] do
        LesBonsComptes.Wallets.list_pending_invitations_for_user(user.id)
      else
        []
      end
    end)
  end

  @doc """
  HTTP plug to block unauthenticated requests on controller routes.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "Vous devez être connecté pour accéder à cette page.")
      |> redirect(to: ~p"/sign-in")
      |> halt()
    end
  end
end
