defmodule LesBonsComptesWeb.SignInLive do
  use LesBonsComptesWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email, "password" => ""}, as: "user")

    {:ok,
     socket
     |> assign(:page_title, "Connexion - Les Bons Comptes")
     |> assign(:form, form),
     temporary_assigns: [form: form]}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} show_sign_in={false}>
      <div class="max-w-xl mx-auto space-y-6">
        <%!-- En-tête de la page --%>
        <div class="text-center space-y-2">
          <div class="inline-flex items-center justify-center size-14 rounded-2xl bg-primary/10 text-primary mb-2 shadow-sm">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.75"
              stroke="currentColor"
              class="size-7"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M15.75 9V5.25A2.25 2.25 0 0 0 13.5 3h-6a2.25 2.25 0 0 0-2.25 2.25v13.5A2.25 2.25 0 0 0 7.5 21h6a2.25 2.25 0 0 0 2.25-2.25V15M12 9l-3 3m0 0 3 3m-3-3h12.75"
              />
            </svg>
          </div>
          <h1 class="text-3xl font-extrabold tracking-tight text-base-content">
            Connexion
          </h1>
          <p class="text-sm text-base-content/70">
            Connectez-vous à votre espace Les Bons Comptes.
          </p>
        </div>

        <%!-- Carte Formulaire de connexion --%>
        <div class="card bg-base-100 shadow-xl border border-base-200">
          <div class="card-body p-6 sm:p-8">
            <.form
              for={@form}
              id="user-sign-in-form"
              action={~p"/users/log_in"}
              phx-update="ignore"
              class="space-y-4"
            >
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
                placeholder="Votre mot de passe"
                required
              />

              <div class="pt-2">
                <button
                  type="submit"
                  id="submit-login-btn"
                  class="btn btn-primary w-full shadow-md text-base font-medium flex items-center justify-center gap-2"
                >
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="1.75"
                    stroke="currentColor"
                    class="size-5"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="M15.75 9V5.25A2.25 2.25 0 0 0 13.5 3h-6a2.25 2.25 0 0 0-2.25 2.25v13.5A2.25 2.25 0 0 0 7.5 21h6a2.25 2.25 0 0 0 2.25-2.25V15M12 9l-3 3m0 0 3 3m-3-3h12.75"
                    />
                  </svg>
                  Se connecter
                </button>
              </div>
            </.form>

            <div class="text-center pt-4 border-t border-base-200 mt-4 text-sm text-base-content/70">
              Pas encore de compte ?
              <.link navigate={~p"/sign-up"} class="font-semibold text-primary hover:underline ml-1">
                Créer un compte
              </.link>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
