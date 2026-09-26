defmodule LesBonsComptesWeb.UserSessionController do
  use LesBonsComptesWeb, :controller

  alias LesBonsComptes.Accounts
  alias LesBonsComptesWeb.UserAuth

  @doc """
  Connecte un utilisateur via un token signé (utilisé immédiatement après l'inscription LiveView)
  ou via email / mot de passe.
  """
  def create(conn, %{"token" => token}) do
    case UserAuth.verify_user_token(token) do
      {:ok, user_id} ->
        case Accounts.get_user(user_id) do
          nil ->
            conn
            |> put_flash(:error, "Utilisateur introuvable.")
            |> redirect(to: ~p"/sign-in")

          user ->
            conn
            |> put_flash(:info, "Bienvenue #{user.name} ! Votre session est active.")
            |> UserAuth.log_in_user(user)
        end

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Lien d'authentification invalide ou expiré.")
        |> redirect(to: ~p"/sign-in")
    end
  end

  def create(conn, %{"user" => %{"email" => email, "password" => password}}) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Connexion réussie !")
        |> UserAuth.log_in_user(user)

      {:error, :unauthorized} ->
        conn
        |> put_flash(:error, "Adresse email ou mot de passe invalide.")
        |> redirect(to: ~p"/sign-in")
    end
  end

  @doc """
  Déconnecte l'utilisateur en détruisant sa session signée.
  """
  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Vous avez été déconnecté.")
    |> UserAuth.log_out_user()
  end
end
