defmodule LesBonsComptesWeb.UserAuth do
  @moduledoc """
  Module d'authentification et de gestion de session pour Les Bons Comptes.
  Gère la persistance de session par cookies signés, les tokens d'auto-connexion post-inscription,
  et les hooks de montage pour Phoenix LiveView.
  """

  use LesBonsComptesWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias LesBonsComptes.Accounts

  # Durée de validité du token d'auto-connexion post-inscription (en secondes)
  @token_max_age 60

  @doc """
  Connecte un utilisateur en initialisant son ID dans la session signée.
  Renouvelle l'ID de session pour prévenir les attaques de fixation de session.
  """
  def log_in_user(conn, user, return_to \\ ~p"/") do
    conn
    |> configure_session(renew: true)
    |> put_session(:user_id, user.id)
    |> put_session(:live_socket_id, "users_sessions:#{user.id}")
    |> redirect(to: return_to)
  end

  @doc """
  Déconnecte l'utilisateur en détruisant sa session courante.
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
  Plug qui extrait l'utilisateur courant depuis la session signée
  et l'assigne à `conn.assigns[:current_user]`.
  """
  def fetch_current_user(conn, _opts) do
    user_id = get_session(conn, :user_id)
    user = user_id && Accounts.get_user(user_id)
    assign(conn, :current_user, user)
  end

  @doc """
  Génère un token éphémère signé pour connecter l'utilisateur immédiatement
  après la création de son compte depuis une LiveView.
  """
  def sign_user_token(user_id) do
    Phoenix.Token.sign(LesBonsComptesWeb.Endpoint, "user_session", user_id)
  end

  @doc """
  Vérifie le token éphémère d'auto-connexion.
  """
  def verify_user_token(token) do
    Phoenix.Token.verify(LesBonsComptesWeb.Endpoint, "user_session", token,
      max_age: @token_max_age
    )
  end

  @doc """
  Hook `on_mount` pour Phoenix LiveView permettant d'assigner l'utilisateur courant
  à partir de la session WebSocket.
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
  Plug HTTP pour bloquer les requêtes non authentifiées sur les routes contrôleur.
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
