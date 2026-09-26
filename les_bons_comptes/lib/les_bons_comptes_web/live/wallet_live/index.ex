defmodule LesBonsComptesWeb.WalletLive.Index do
  use LesBonsComptesWeb, :live_view

  alias LesBonsComptes.Wallets

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    wallets = Wallets.list_wallets_for_user(user.id)

    {:ok,
     socket
     |> assign(:page_title, "Mes porte-monnaies - Les Bons Comptes")
     |> assign(:wallets, wallets)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="max-w-4xl mx-auto space-y-6">
        <%!-- En-tête avec bouton Créer --%>
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div>
            <h1 class="text-3xl font-extrabold tracking-tight text-base-content">
              Mes porte-monnaies
            </h1>
            <p class="text-sm text-base-content/70">
              Retrouvez tous vos comptes de dépenses partagées (Tricounts).
            </p>
          </div>

          <.link
            navigate={~p"/wallets/new"}
            id="new-wallet-btn"
            class="btn btn-primary gap-2 shadow-sm"
          >
            <.icon name="hero-plus" class="size-5" />
            <span>Nouveau porte-monnaie</span>
          </.link>
        </div>

        <%!-- Liste ou État vide --%>
        <%= if @wallets == [] do %>
          <div id="empty-wallets-state" class="card bg-base-100 shadow-xl border border-base-200">
            <div class="card-body p-12 text-center space-y-4">
              <div class="size-16 rounded-2xl bg-primary/10 text-primary flex items-center justify-center mx-auto">
                <.icon name="hero-wallet" class="size-8" />
              </div>
              <div class="space-y-1">
                <h3 class="text-lg font-bold text-base-content">
                  Aucun porte-monnaie pour le moment
                </h3>
                <p class="text-sm text-base-content/60 max-w-md mx-auto">
                  Créez votre premier porte-monnaie commun pour commencer à répartir équitablement vos dépenses de vacances, colocation ou sorties.
                </p>
              </div>
              <div class="pt-2">
                <.link navigate={~p"/wallets/new"} class="btn btn-primary btn-sm gap-2">
                  <.icon name="hero-plus" class="size-4" />
                  <span>Créer mon premier porte-monnaie</span>
                </.link>
              </div>
            </div>
          </div>
        <% else %>
          <div id="wallets-grid" class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <%= for wallet <- @wallets do %>
              <.link
                navigate={~p"/wallets/#{wallet.id}"}
                id={"wallet-card-#{wallet.id}"}
                class="card bg-base-100 shadow hover:shadow-lg border border-base-200 transition-all cursor-pointer group"
              >
                <div class="card-body p-6 space-y-3">
                  <div class="flex items-start justify-between gap-2">
                    <h2 class="text-xl font-bold text-base-content group-hover:text-primary transition-colors">
                      {wallet.name}
                    </h2>
                    <span class="badge badge-primary badge-sm font-semibold">
                      {wallet.currency}
                    </span>
                  </div>

                  <p :if={wallet.description} class="text-xs text-base-content/70 line-clamp-2">
                    {wallet.description}
                  </p>

                  <div class="divider my-1"></div>

                  <div class="flex items-center justify-between text-xs text-base-content/60">
                    <span class="flex items-center gap-1">
                      <.icon name="hero-user-group" class="size-4" />
                      <span>{length(wallet.members)} participant(s)</span>
                    </span>

                    <span class="flex items-center gap-1 font-medium text-primary">
                      <span>Accéder</span>
                      <.icon
                        name="hero-arrow-right"
                        class="size-3.5 group-hover:translate-x-0.5 transition-transform"
                      />
                    </span>
                  </div>
                </div>
              </.link>
            <% end %>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
