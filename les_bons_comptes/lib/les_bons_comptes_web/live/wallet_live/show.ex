defmodule LesBonsComptesWeb.WalletLive.Show do
  use LesBonsComptesWeb, :live_view

  alias LesBonsComptes.Wallets

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    wallet = Wallets.get_wallet!(id)

    {:ok,
     socket
     |> assign(:page_title, "#{wallet.name} - Les Bons Comptes")
     |> assign(:wallet, wallet)}
  end

  @impl true
  def handle_event("delete_wallet", _params, socket) do
    current_user = socket.assigns.current_user
    wallet = socket.assigns.wallet

    case Wallets.delete_wallet(current_user, wallet) do
      {:ok, _deleted_wallet} ->
        {:noreply,
         socket
         |> put_flash(:info, "Le porte-monnaie « #{wallet.name} » a été supprimé avec succès.")
         |> push_navigate(to: ~p"/wallets")}

      {:error, :unauthorized} ->
        {:noreply,
         socket
         |> put_flash(:error, "Seul le propriétaire peut supprimer ce porte-monnaie.")}
    end
  end

  @impl true
  def handle_event("leave_wallet", _params, socket) do
    current_user = socket.assigns.current_user
    wallet = socket.assigns.wallet

    case Wallets.leave_wallet(current_user, wallet) do
      {:ok, _member} ->
        {:noreply,
         socket
         |> put_flash(:info, "Vous avez quitté le porte-monnaie « #{wallet.name} ».")
         |> push_navigate(to: ~p"/wallets")}

      {:error, :owner_cannot_leave} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Le propriétaire ne peut pas quitter le groupe. Vous pouvez le supprimer."
         )}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Impossible de quitter ce porte-monnaie.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="max-w-4xl mx-auto space-y-6">
        <%!-- Fil d'Ariane & Actions retour --%>
        <div class="flex items-center justify-between">
          <.link navigate={~p"/wallets"} class="btn btn-ghost btn-sm gap-2 text-base-content/70">
            <.icon name="hero-arrow-left" class="size-4" />
            <span>Tous les porte-monnaies</span>
          </.link>

          <.link navigate={~p"/wallets/new"} class="btn btn-outline btn-sm gap-1">
            <.icon name="hero-plus" class="size-4" />
            <span>Nouveau porte-monnaie</span>
          </.link>
        </div>

        <%!-- Carte En-tête du Porte-Monnaie (IF-34 Confirmation) --%>
        <div class="card bg-base-100 shadow-xl border border-base-200">
          <div class="card-body p-6 sm:p-8 space-y-4">
            <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
              <div class="space-y-1">
                <div class="flex items-center gap-2">
                  <h1 id="wallet-name" class="text-2xl sm:text-3xl font-extrabold text-base-content">
                    {@wallet.name}
                  </h1>
                  <span id="wallet-currency-badge" class="badge badge-primary font-bold">
                    {@wallet.currency}
                  </span>
                </div>
                <p
                  :if={@wallet.description}
                  id="wallet-description"
                  class="text-sm text-base-content/70"
                >
                  {@wallet.description}
                </p>
              </div>

              <div class="flex flex-wrap items-center gap-2">
                <span class="badge badge-success badge-sm gap-1 py-3 px-3">
                  <.icon name="hero-check-circle" class="size-4" />
                  <span>Porte-monnaie actif</span>
                </span>

                <%= if @current_user && @current_user.id == @wallet.creator_id do %>
                  <.link
                    navigate={~p"/wallets/#{@wallet.id}/edit"}
                    id="edit-wallet-btn"
                    class="btn btn-outline btn-sm gap-1"
                  >
                    <.icon name="hero-pencil-square" class="size-4" />
                    <span>Modifier</span>
                  </.link>

                  <button
                    type="button"
                    id="delete-wallet-btn"
                    phx-click="delete_wallet"
                    data-confirm="Êtes-vous sûr de vouloir supprimer définitivement ce porte-monnaie ? Cette action est irréversible."
                    class="btn btn-outline btn-error btn-sm gap-1"
                  >
                    <.icon name="hero-trash" class="size-4" />
                    <span>Supprimer</span>
                  </button>
                <% else %>
                  <%= if @current_user && Enum.any?(@wallet.members, &(&1.user_id == @current_user.id)) do %>
                    <button
                      type="button"
                      id="leave-wallet-btn"
                      phx-click="leave_wallet"
                      data-confirm="Êtes-vous sûr de vouloir quitter ce porte-monnaie ? Vous ne ferez plus partie de ce groupe."
                      class="btn btn-outline btn-warning btn-sm gap-1"
                    >
                      <.icon name="hero-arrow-right-start-on-rectangle" class="size-4" />
                      <span>Quitter le porte-monnaie</span>
                    </button>
                  <% end %>
                <% end %>
              </div>
            </div>

            <div class="divider my-1"></div>

            <%!-- Métriques rapides style Tricount --%>
            <div class="grid grid-cols-1 sm:grid-cols-3 gap-4 text-center">
              <div class="bg-base-200/50 p-4 rounded-xl border border-base-200">
                <div class="text-xs font-semibold text-base-content/60 uppercase">Total Dépenses</div>
                <div class="text-2xl font-bold text-base-content mt-1">0,00 {@wallet.currency}</div>
                <div class="text-xs text-base-content/50 mt-0.5">Aucune dépense pour le moment</div>
              </div>

              <div class="bg-base-200/50 p-4 rounded-xl border border-base-200">
                <div class="text-xs font-semibold text-base-content/60 uppercase">Participants</div>
                <div id="members-count" class="text-2xl font-bold text-primary mt-1">
                  {length(@wallet.members)}
                </div>
                <div class="text-xs text-base-content/50 mt-0.5">Membres associés au groupe</div>
              </div>

              <div class="bg-base-200/50 p-4 rounded-xl border border-base-200">
                <div class="text-xs font-semibold text-base-content/60 uppercase">Propriétaire</div>
                <div
                  id="owner-name"
                  class="text-base font-bold text-base-content mt-2 flex items-center justify-center gap-1"
                >
                  <.icon name="hero-shield-check" class="size-4 text-primary" />
                  <span>{@wallet.creator.name}</span>
                </div>
                <div class="text-xs text-base-content/50 mt-0.5">{@wallet.creator.email}</div>
              </div>
            </div>
          </div>
        </div>

        <%!-- Participants au porte-monnaie (IF-30, IF-36) --%>
        <div class="card bg-base-100 shadow-xl border border-base-200">
          <div class="card-body p-6 sm:p-8 space-y-4">
            <div class="flex items-center justify-between">
              <h2 class="text-lg font-bold text-base-content flex items-center gap-2">
                <.icon name="hero-user-group" class="size-5 text-primary" />
                <span>Participants ({length(@wallet.members)})</span>
              </h2>

              <%= if @current_user && @current_user.id == @wallet.creator_id do %>
                <.link
                  navigate={~p"/wallets/#{@wallet.id}/edit"}
                  id="manage-members-btn"
                  class="btn btn-outline btn-xs gap-1 hover:btn-primary"
                >
                  <.icon name="hero-user-plus" class="size-3.5" />
                  <span>Gérer les participants</span>
                </.link>
              <% end %>
            </div>

            <div id="wallet-members-list" class="divide-y divide-base-200">
              <%= for member <- @wallet.members do %>
                <div id={"member-item-#{member.id}"} class="py-3 flex items-center justify-between">
                  <div class="flex items-center gap-3">
                    <div class={[
                      "size-10 rounded-full flex items-center justify-center font-bold text-sm shadow-sm",
                      if(member.role == "owner",
                        do: "bg-primary text-primary-content",
                        else: "bg-base-300 text-base-content"
                      )
                    ]}>
                      {String.first(member.name || "?")}
                    </div>
                    <div>
                      <div class="font-semibold text-sm text-base-content flex items-center gap-2">
                        <span>{member.name}</span>
                        <%= if member.role == "owner" do %>
                          <span class="badge badge-primary badge-xs gap-1">
                            <.icon name="hero-star" class="size-2.5" /> Propriétaire
                          </span>
                        <% else %>
                          <span class="badge badge-info badge-xs gap-0.5">
                            <.icon name="hero-check" class="size-2.5" /> Inscrit
                          </span>
                        <% end %>
                      </div>
                      <div :if={member.email} class="text-xs text-base-content/60">
                        {member.email}
                      </div>
                    </div>
                  </div>

                  <div class="text-right">
                    <span class="text-sm font-semibold text-base-content/80">0,00 {@wallet.currency}</span>
                    <div class="text-xs text-base-content/50">Équilibré</div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
