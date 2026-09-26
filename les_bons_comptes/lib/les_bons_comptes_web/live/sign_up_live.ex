defmodule LesBonsComptesWeb.SignUpLive do
  use LesBonsComptesWeb, :live_view

  alias LesBonsComptes.Accounts
  alias LesBonsComptes.Accounts.User
  alias LesBonsComptesWeb.UserAuth

  @impl true
  def mount(_params, _session, socket) do
    changeset = Accounts.change_user(%User{})

    {:ok,
     socket
     |> assign(:page_title, "Créer un compte - Les Bons Comptes")
     |> assign(:form, to_form(changeset))
     |> assign(:unique_error, nil)}
  end

  @impl true
  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset =
      %User{}
      |> Accounts.change_user(user_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset))
     |> assign(:unique_error, nil)}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.create_user(user_params) do
      {:ok, user} ->
        # Génération du token sécurisé et initialisation immédiate de la session (IF-27)
        token = UserAuth.sign_user_token(user.id)

        {:noreply,
         socket
         |> put_flash(:info, "Compte créé avec succès ! Bienvenue #{user.name}.")
         |> redirect(to: ~p"/users/log_in?token=#{token}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        unique_error = if has_unique_error?(changeset), do: "Un compte existe déjà", else: nil
        cleaned_changeset = remove_unique_error(changeset)

        {:noreply,
         socket
         |> assign(:form, to_form(cleaned_changeset))
         |> assign(:unique_error, unique_error)}
    end
  end

  defp has_unique_error?(%Ecto.Changeset{} = changeset) do
    Enum.any?(changeset.errors, fn
      {:email, {msg, _}} -> msg =~ "un compte existe déjà"
      _ -> false
    end)
  end

  defp remove_unique_error(%Ecto.Changeset{} = changeset) do
    new_errors =
      Enum.reject(changeset.errors, fn
        {:email, {msg, _}} -> msg =~ "un compte existe déjà"
        _ -> false
      end)

    %{changeset | errors: new_errors}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} show_sign_in={false}>
      <div class="max-w-xl mx-auto space-y-6">
        <%!-- En-tête de la page --%>
        <div class="text-center space-y-2">
          <div class="inline-flex items-center justify-center size-14 rounded-2xl bg-primary/10 text-primary mb-2 shadow-sm">
            <.icon name="hero-user-plus" class="size-7" />
          </div>
          <h1 class="text-3xl font-extrabold tracking-tight text-base-content">
            Créer un compte
          </h1>
          <p class="text-sm text-base-content/70">
            Remplissez vos informations pour créer votre profil utilisateur.
          </p>
        </div>

        <%!-- Carte Formulaire d'inscription --%>
        <div class="card bg-base-100 shadow-xl border border-base-200">
          <div class="card-body p-6 sm:p-8">
            <.form
              for={@form}
              id="user-sign-up-form"
              phx-change="validate"
              phx-submit="save"
              class="space-y-4"
            >
              <.input
                field={@form[:name]}
                type="text"
                label="Nom ou Pseudo"
                placeholder="ex: Alex Dupont"
                required
              />

              <.input
                field={@form[:email]}
                type="email"
                label="Adresse Email"
                placeholder="alex.dupont@exemple.com"
                required
              />

              <.input
                field={@form[:password]}
                type="password"
                label="Mot de passe"
                placeholder="Au moins 6 caractères"
                required
              />

              <div class="pt-2">
                <button
                  type="submit"
                  id="submit-user-btn"
                  phx-disable-with="Création en cours..."
                  class="btn btn-primary w-full shadow-md text-base font-medium flex items-center justify-center gap-2"
                >
                  <.icon name="hero-check" class="size-5" /> Créer mon compte
                </button>

                <div
                  :if={@unique_error}
                  id="email-uniqueness-error"
                  class="mt-3 p-3 rounded-xl bg-error/10 border border-error/20 flex items-center justify-center gap-2 text-sm text-error font-semibold"
                >
                  <.icon name="hero-exclamation-circle" class="size-5 shrink-0" />
                  <span>{@unique_error}</span>
                </div>
              </div>
            </.form>

            <div class="text-center pt-4 border-t border-base-200 mt-4 text-sm text-base-content/70">
              Déjà inscrit ?
              <.link navigate={~p"/sign-in"} class="font-semibold text-primary hover:underline ml-1">
                Se connecter
              </.link>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
