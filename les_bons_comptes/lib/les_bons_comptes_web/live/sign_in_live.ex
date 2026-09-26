defmodule LesBonsComptesWeb.SignInLive do
  use LesBonsComptesWeb, :live_view

  alias LesBonsComptes.Accounts
  alias LesBonsComptes.Accounts.User
  alias LesBonsComptesWeb.UserAuth

  @impl true
  def mount(_params, _session, socket) do
    changeset = Accounts.change_user(%User{})
    users = Accounts.list_users()

    {:ok,
     socket
     |> assign(:page_title, "Création d'utilisateur - Les Bons Comptes")
     |> assign(:form, to_form(changeset))
     |> stream(:users, users)}
  end

  @impl true
  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset =
      %User{}
      |> Accounts.change_user(user_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.create_user(user_params) do
      {:ok, user} ->
        # Génération du token sécurisé et initialisation immédiate de la session (IF-27)
        token = UserAuth.sign_user_token(user.id)

        {:noreply,
         socket
         |> put_flash(:info, "Compte créé avec succès ! Initialisation de votre session...")
         |> redirect(to: ~p"/users/log_in?token=#{token}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="max-w-xl mx-auto space-y-8">
        <%!-- En-tête de la page --%>
        <div class="text-center space-y-2">
          <div class="inline-flex items-center justify-center size-14 rounded-2xl bg-primary/10 text-primary mb-2 shadow-sm">
            <.icon name="hero-user-plus" class="size-7" />
          </div>
          <h1 class="text-3xl font-extrabold tracking-tight text-base-content">
            Créer un utilisateur
          </h1>
          <p class="text-sm text-base-content/70">
            Page accessible sur
            <span class="font-mono bg-base-200 px-2 py-0.5 rounded text-primary font-semibold">/sign-in</span>
            — L'utilisateur sera directement persisté dans la base PostgreSQL avec mot de passe haché.
          </p>
        </div>

        <%!-- Carte Formulaire d'inscription --%>
        <div class="card bg-base-100 shadow-xl border border-base-200">
          <div class="card-body p-6 sm:p-8">
            <.form
              for={@form}
              id="user-sign-in-form"
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
                  phx-disable-with="Création en base..."
                  class="btn btn-primary w-full shadow-md text-base font-medium flex items-center justify-center gap-2"
                >
                  <.icon name="hero-check" class="size-5" /> Enregistrer l'utilisateur et se connecter
                </button>
              </div>
            </.form>
          </div>
        </div>

        <%!-- Section visualisant les utilisateurs en base de données --%>
        <div class="space-y-4">
          <div class="flex items-center justify-between">
            <h2 class="text-lg font-bold text-base-content flex items-center gap-2">
              <.icon name="hero-circle-stack" class="size-5 text-secondary" />
              Utilisateurs enregistrés en base
            </h2>
            <span class="text-xs font-mono text-base-content/60 bg-base-200 px-2.5 py-1 rounded-full">
              PostgreSQL : table `users`
            </span>
          </div>

          <div class="card bg-base-100 shadow border border-base-200 overflow-hidden">
            <div id="users" phx-update="stream" class="divide-y divide-base-200">
              <div
                :for={{dom_id, user} <- @streams.users}
                id={dom_id}
                class="p-4 flex items-center justify-between hover:bg-base-200/40 transition-colors"
              >
                <div class="flex items-center gap-3">
                  <div class="size-10 rounded-full bg-secondary/15 text-secondary font-bold flex items-center justify-center uppercase text-sm">
                    {String.slice(user.name, 0, 2)}
                  </div>
                  <div>
                    <p class="font-semibold text-base-content text-sm">{user.name}</p>
                    <p class="text-xs text-base-content/60 font-mono">{user.email}</p>
                  </div>
                </div>
                <div class="text-right">
                  <span class="badge badge-sm badge-ghost text-xs">
                    ID #{user.id}
                  </span>
                  <p class="text-[10px] text-base-content/50 mt-1">
                    {Calendar.strftime(user.inserted_at, "%d/%m/%Y à %H:%M")}
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
