defmodule LesBonsComptesWeb.WalletLive.Index do
  use LesBonsComptesWeb, :live_view

  import LesBonsComptesWeb.WalletLive.WalletComponents
  alias LesBonsComptes.Wallets

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    pending_invitations = Wallets.list_pending_invitations_for_user(user.id)

    {:ok,
     socket
     |> assign(:page_title, "Mes porte-monnaies - Les Bons Comptes")
     |> assign(:pending_invitations, pending_invitations)
     |> assign(:active_tab, "my_wallets")
     |> assign(:wallet_status_filter, "all")
     |> assign(:wallet_page, 1)
     |> assign(:invited_page, 1)
     |> assign(:all_wallets, [])
     |> assign(:wallets, [])
     |> assign(:wallets_pagination, nil)
     |> assign(:wallet_counts, %{})
     |> assign(:wallets_error, nil)
     |> assign(:invitation_filter, "all")
     |> assign(:invited_wallets, [])
     |> assign(:all_invited_wallets, [])
     |> assign(:invited_pagination, nil)
     |> assign(:invited_counts, %{})
     |> assign(:loading_error, nil)
     |> load_wallets_data(user.id, "all", 1)
     |> load_invited_wallets_data(user.id, "all", 1)}
  end

  @impl true
  def handle_params(params, uri, socket) do
    user = socket.assigns.current_user
    path = URI.parse(uri).path
    page = params["page"] || 1

    {tab, status_filter} =
      cond do
        path == "/wallets/invited" or socket.assigns.live_action == :invited ->
          {"invited", params["status"] || socket.assigns[:invitation_filter] || "all"}

        path == "/wallets/open" ->
          {"my_wallets", "open"}

        path == "/wallets/closed" ->
          {"my_wallets", "closed"}

        params["tab"] == "invited" ->
          {"invited", params["status"] || socket.assigns[:invitation_filter] || "all"}

        true ->
          tab = params["tab"] || "my_wallets"
          filter = params["status"] || "all"
          {tab, filter}
      end

    socket =
      if tab == "invited" do
        socket
        |> assign(:active_tab, tab)
        |> assign(:page_title, "Portes-monnaies invités - Les Bons Comptes")
        |> assign(:invitation_filter, status_filter)
        |> assign(:invited_page, page)
        |> load_invited_wallets_data(user.id, status_filter, page)
      else
        page_title =
          case status_filter do
            "open" -> "Portes-monnaies ouverts - Les Bons Comptes"
            "closed" -> "Portes-monnaies clos - Les Bons Comptes"
            _ -> "Mes porte-monnaies - Les Bons Comptes"
          end

        socket
        |> assign(:active_tab, tab)
        |> assign(:page_title, page_title)
        |> assign(:wallet_status_filter, status_filter)
        |> assign(:wallet_page, page)
        |> load_wallets_data(user.id, status_filter, page)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_tab", %{"tab" => tab}, socket) do
    {:noreply, push_patch(socket, to: ~p"/wallets?tab=#{tab}")}
  end

  @impl true
  def handle_event("filter_wallets", %{"status" => status}, socket) do
    target_path =
      case status do
        "open" -> ~p"/wallets/open"
        "closed" -> ~p"/wallets/closed"
        "all" -> ~p"/wallets"
        other -> ~p"/wallets?status=#{other}"
      end

    {:noreply, push_patch(socket, to: target_path)}
  end

  @impl true
  def handle_event("retry_load_wallets", _params, socket) do
    user = socket.assigns.current_user
    filter = socket.assigns.wallet_status_filter || "all"
    page = socket.assigns[:wallet_page] || 1

    {:noreply,
     socket
     |> assign(:wallets_error, nil)
     |> load_wallets_data(user.id, filter, page)}
  end

  @impl true
  def handle_event("simulate_wallets_error", _params, socket) do
    {:noreply,
     socket
     |> assign(:wallets, [])
     |> assign(:wallets_error, "Erreur de connexion au serveur de base de données (simulation).")}
  end

  @impl true
  def handle_event("filter_invitations", %{"status" => status}, socket) do
    {:noreply, push_patch(socket, to: ~p"/wallets?tab=invited&status=#{status}")}
  end

  @impl true
  def handle_event("change_wallet_page", %{"page" => page}, socket) do
    status = socket.assigns.wallet_status_filter || "all"
    {:noreply, push_patch(socket, to: wallet_path(status, page))}
  end

  @impl true
  def handle_event("change_invited_page", %{"page" => page}, socket) do
    status = socket.assigns.invitation_filter || "all"
    {:noreply, push_patch(socket, to: invited_path(status, page))}
  end

  @impl true
  def handle_event("retry_load_invited", _params, socket) do
    user = socket.assigns.current_user
    filter = socket.assigns.invitation_filter || "all"
    page = socket.assigns.invited_page || 1

    {:noreply,
     socket
     |> assign(:loading_error, nil)
     |> load_invited_wallets_data(user.id, filter, page)}
  end

  @impl true
  def handle_event("simulate_loading_error", _params, socket) do
    {:noreply,
     socket
     |> assign(:invited_wallets, [])
     |> assign(:loading_error, "Erreur de connexion au serveur de base de données (simulation).")}
  end

  @impl true
  def handle_event("accept_invitation", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    case Wallets.accept_invitation(user, id) do
      {:ok, _member} ->
        pending_invitations = Wallets.list_pending_invitations_for_user(user.id)

        {:noreply,
         socket
         |> put_flash(:info, "Félicitations ! Vous avez rejoint le porte-monnaie avec succès.")
         |> assign(:pending_invitations, pending_invitations)
         |> load_wallets_data(user.id, socket.assigns.wallet_status_filter, socket.assigns.wallet_page)
         |> load_invited_wallets_data(user.id, socket.assigns.invitation_filter, socket.assigns.invited_page)}

      {:error, :invitations_disabled} ->
        pending_invitations = Wallets.list_pending_invitations_for_user(user.id)

        {:noreply,
         socket
         |> put_flash(
           :error,
           "Impossible d'accepter cette invitation : le porte-monnaie n'est plus en phase de déclaration."
         )
         |> assign(:pending_invitations, pending_invitations)
         |> load_invited_wallets_data(user.id, socket.assigns.invitation_filter, socket.assigns.invited_page)}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Impossible d'accepter l'invitation : #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("decline_invitation", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    case Wallets.decline_invitation(user, id) do
      {:ok, _invitation} ->
        pending_invitations = Wallets.list_pending_invitations_for_user(user.id)

        {:noreply,
         socket
         |> put_flash(:info, "Vous avez refusé l'invitation.")
         |> assign(:pending_invitations, pending_invitations)
         |> load_invited_wallets_data(user.id, socket.assigns.invitation_filter, socket.assigns.invited_page)}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Impossible de refuser l'invitation : #{inspect(reason)}")}
    end
  end

  def wallet_path(filter, page) do
    page = if is_binary(page), do: String.to_integer(page), else: page

    base =
      case filter do
        "open" -> "/wallets/open"
        "closed" -> "/wallets/closed"
        "all" -> "/wallets"
        other -> "/wallets?status=#{other}"
      end

    if page > 1 do
      if String.contains?(base, "?"), do: "#{base}&page=#{page}", else: "#{base}?page=#{page}"
    else
      base
    end
  end

  def invited_path(status, page) do
    page = if is_binary(page), do: String.to_integer(page), else: page
    status = status || "all"

    if page > 1 do
      "/wallets?tab=invited&status=#{status}&page=#{page}"
    else
      "/wallets?tab=invited&status=#{status}"
    end
  end

  defp load_wallets_data(socket, user_id, filter, page) do
    case Wallets.fetch_wallets_for_user(user_id, "all") do
      {:ok, all_wallets} ->
        counts = %{
          "all" => length(all_wallets),
          "open" => Enum.count(all_wallets, &(&1.status == "open")),
          "closed" => Enum.count(all_wallets, &(&1.status == "closed")),
          "pending_settlement" => Enum.count(all_wallets, &(&1.status == "pending_settlement"))
        }

        filtered = Wallets.filter_wallets_by_status(all_wallets, filter)
        pagination = LesBonsComptes.Pagination.paginate(filtered, page, 8)

        socket
        |> assign(:all_wallets, all_wallets)
        |> assign(:wallets, pagination.entries)
        |> assign(:wallets_pagination, pagination)
        |> assign(:wallet_counts, counts)
        |> assign(:wallets_error, nil)

      {:error, reason} ->
        socket
        |> assign(:all_wallets, [])
        |> assign(:wallets, [])
        |> assign(:wallets_pagination, %LesBonsComptes.Pagination{
          entries: [],
          page_number: 1,
          page_size: 8,
          total_entries: 0,
          total_pages: 1,
          has_prev: false,
          has_next: false,
          start_index: 0,
          end_index: 0
        })
        |> assign(:wallet_counts, %{})
        |> assign(
          :wallets_error,
          "Une erreur est survenue lors de la récupération des porte-monnaies : #{inspect(reason)}"
        )
    end
  end

  defp load_invited_wallets_data(socket, user_id, filter, page) do
    case Wallets.fetch_invited_wallets(user_id, "all") do
      {:ok, all_invited} ->
        counts = %{
          "all" => length(all_invited),
          "pending" =>
            Enum.count(all_invited, fn w -> w.invitation && w.invitation.status == "pending" end),
          "accepted" =>
            Enum.count(all_invited, fn w -> w.invitation && w.invitation.status == "accepted" end),
          "declined" =>
            Enum.count(all_invited, fn w -> w.invitation && w.invitation.status == "declined" end),
          "cancelled" =>
            Enum.count(all_invited, fn w -> w.invitation && w.invitation.status == "cancelled" end)
        }

        filtered = Wallets.filter_invited_wallets_by_status(all_invited, filter)
        pagination = LesBonsComptes.Pagination.paginate(filtered, page, 6)

        socket
        |> assign(:all_invited_wallets, all_invited)
        |> assign(:invited_wallets, pagination.entries)
        |> assign(:invited_pagination, pagination)
        |> assign(:invited_counts, counts)
        |> assign(:loading_error, nil)

      {:error, reason} ->
        socket
        |> assign(:all_invited_wallets, [])
        |> assign(:invited_wallets, [])
        |> assign(:invited_pagination, %LesBonsComptes.Pagination{
          entries: [],
          page_number: 1,
          page_size: 6,
          total_entries: 0,
          total_pages: 1,
          has_prev: false,
          has_next: false,
          start_index: 0,
          end_index: 0
        })
        |> assign(:invited_counts, %{})
        |> assign(
          :loading_error,
          "Une erreur est survenue lors de la récupération des portes-monnaies invités : #{inspect(reason)}"
        )
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      pending_invitations={@pending_invitations}
    >
      <div class="max-w-4xl mx-auto space-y-6">
        <%!-- En-tête avec titre dynamique et bouton Créer --%>
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div>
            <h1
              id="page-main-heading"
              class="text-3xl font-extrabold tracking-tight text-base-content"
            >
              <%= cond do %>
                <% @active_tab == "invited" -> %>
                  Portes-monnaies invités
                <% @wallet_status_filter == "open" -> %>
                  Portes-monnaies ouverts
                <% @wallet_status_filter == "closed" -> %>
                  Portes-monnaies clos
                <% true -> %>
                  Mes porte-monnaies
              <% end %>
            </h1>

            <p class="text-sm text-base-content/70">
              <%= cond do %>
                <% @active_tab == "invited" -> %>
                  Retrouvez tous les comptes partagés auxquels vous avez été invité(e).
                <% @wallet_status_filter == "open" -> %>
                  Comptes en cours de déclaration des dépenses et invitations.
                <% @wallet_status_filter == "closed" -> %>
                  Comptes clôturés et définitivement soldés.
                <% true -> %>
                  Retrouvez tous vos comptes de dépenses partagées (Tricounts).
              <% end %>
            </p>
          </div>

          <.link
            navigate={~p"/wallets/new"}
            id="new-wallet-btn"
            class="btn btn-primary gap-2 shadow-sm"
          >
            <.icon name="hero-plus" class="size-5" /> <span>Nouveau porte-monnaie</span>
          </.link>
        </div>

        <%!-- Onglets de navigation principale --%>
        <div class="flex items-center justify-between border-b border-base-200 pb-2">
          <div class="tabs tabs-boxed bg-base-200/60 p-1 rounded-xl">
            <button
              type="button"
              id="tab-my-wallets"
              phx-click="change_tab"
              phx-value-tab="my_wallets"
              class={[
                "tab tab-sm sm:tab-md font-semibold gap-2 transition-all rounded-lg",
                @active_tab == "my_wallets" &&
                  "tab-active bg-primary text-primary-content shadow-sm"
              ]}
            >
              <.icon name="hero-wallet" class="size-4" /> <span>Mes porte-monnaies</span>
              <span class="badge badge-sm opacity-80">{length(@all_wallets)}</span>
            </button>

            <button
              type="button"
              id="tab-invited-wallets"
              phx-click="change_tab"
              phx-value-tab="invited"
              class={[
                "tab tab-sm sm:tab-md font-semibold gap-2 transition-all rounded-lg",
                @active_tab == "invited" &&
                  "tab-active bg-primary text-primary-content shadow-sm"
              ]}
            >
              <.icon name="hero-envelope" class="size-4" /> <span>Portes-monnaies invités</span>
              <span
                id="invited-wallets-badge"
                class={[
                  "badge badge-sm",
                  if(@pending_invitations != [],
                    do: "badge-warning font-bold",
                    else: "badge-ghost opacity-80"
                  )
                ]}
              >
                {length(@all_invited_wallets)}
              </span>
            </button>
          </div>
        </div>

        <%= if @active_tab == "invited" do %>
          <%!-- ======================================================== --%>
          <%!-- VUE: Portes-monnaies invités (Epic)                      --%>
          <%!-- ======================================================== --%>
          <div id="invited-wallets-section" class="space-y-6">
            <%!-- Filtres par statut d'invitation (US: Filtrage par statut) --%>
            <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
              <.invitation_status_filter_bar
                current_filter={@invitation_filter}
                counts={@invited_counts}
              />
              <div class="text-xs text-base-content/60 font-medium sm:text-right">
                <span id="filtered-invited-count">
                  {if @invited_pagination,
                    do: @invited_pagination.total_entries,
                    else: length(@invited_wallets)}
                </span>
                porte-monnaie(s) invité(s)
              </div>
            </div>

            <%!-- État d'erreur de chargement (US: Gestion des erreurs de chargement) --%>
            <.invited_wallets_error_state
              :if={@loading_error}
              error_message={@loading_error}
            />
            <%= if is_nil(@loading_error) do %>
              <%!-- État vide (US: Gestion des états vides) --%>
              <.empty_invited_wallets_state
                :if={@invited_wallets == []}
                status_filter={@invitation_filter}
              />
              <%!-- Affichage de la liste des cartes de portes-monnaies invités (US: Affichage de la liste) --%>
              <div
                :if={@invited_wallets != []}
                id="invited-wallets-grid"
                class="grid grid-cols-1 md:grid-cols-2 gap-4"
              >
                <%= for wallet <- @invited_wallets do %>
                  <.invited_wallet_card wallet={wallet} current_user={@current_user} />
                <% end %>
              </div>

              <.pagination
                :if={@invited_pagination}
                pagination={@invited_pagination}
                id="invited-wallets-pagination"
                item_name="portes-monnaies"
                path_fn={&invited_path(@invitation_filter, &1)}
              />
            <% end %>
          </div>
        <% else %>
          <%!-- ======================================================== --%>
          <%!-- VUE: Mes porte-monnaies (Épics: Ouverts, Clos, Tous)      --%>
          <%!-- ======================================================== --%>
          <div id="my-wallets-section" class="space-y-6">
            <%!-- Section Invitations en attente (IF-44) --%>
            <div
              :if={@pending_invitations != []}
              id="pending-invitations-section"
              class="card bg-base-100 shadow-lg border-2 border-primary/20 bg-gradient-to-br from-primary/5 to-base-100"
            >
              <div class="card-body p-6 space-y-4">
                <div class="flex items-center justify-between">
                  <div class="flex items-center gap-2.5">
                    <div class="size-9 rounded-xl bg-primary text-primary-content flex items-center justify-center shadow-sm">
                      <.icon name="hero-envelope-open" class="size-5" />
                    </div>

                    <div>
                      <h2 class="text-lg font-bold text-base-content">
                        Invitations reçues
                      </h2>

                      <p class="text-xs text-base-content/60">
                        Vous avez été invité(e) à participer à des comptes partagés.
                      </p>
                    </div>
                  </div>

                  <span class="badge badge-primary font-semibold">
                    {length(@pending_invitations)} en attente
                  </span>
                </div>

                <div class="grid grid-cols-1 md:grid-cols-2 gap-3 pt-1">
                  <%= for invitation <- @pending_invitations do %>
                    <div
                      id={"invitation-card-#{invitation.id}"}
                      class="bg-base-100 rounded-xl p-4 border border-base-200 shadow-sm flex flex-col justify-between gap-3 hover:border-primary/40 transition-colors"
                    >
                      <div class="space-y-1">
                        <div class="flex items-start justify-between gap-2">
                          <h3 class="font-bold text-base text-base-content">
                            {invitation.wallet.name}
                          </h3>

                          <span class="badge badge-primary badge-sm font-semibold">
                            {invitation.wallet.currency}
                          </span>
                        </div>

                        <p class="text-xs text-base-content/70">
                          Invité(e) par
                          <span class="font-semibold text-base-content">
                            {invitation.inviter.name}
                          </span>
                        </p>

                        <p
                          :if={invitation.wallet.description}
                          class="text-xs text-base-content/60 italic line-clamp-2"
                        >
                          « {invitation.wallet.description} »
                        </p>
                      </div>

                      <div class="flex items-center justify-end gap-2 pt-2 border-t border-base-200">
                        <button
                          type="button"
                          id={"decline-invitation-btn-#{invitation.id}"}
                          phx-click="decline_invitation"
                          phx-value-id={invitation.id}
                          class="btn btn-ghost btn-sm text-error hover:bg-error/10"
                        >
                          <.icon name="hero-x-mark" class="size-4" /> <span>Refuser</span>
                        </button>

                        <button
                          type="button"
                          id={"accept-invitation-btn-#{invitation.id}"}
                          phx-click="accept_invitation"
                          phx-value-id={invitation.id}
                          class="btn btn-primary btn-sm gap-1.5 shadow-sm"
                        >
                          <.icon name="hero-check" class="size-4" /> <span>Accepter</span>
                        </button>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>

            <%!-- Filtres par statut (US: Filtrage par statut - Ouvert, Clos, etc.) --%>
            <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
              <.wallet_status_filter_bar
                current_filter={@wallet_status_filter}
                counts={@wallet_counts}
              />
              <div class="text-xs text-base-content/60 font-medium sm:text-right">
                <span id="filtered-wallets-count">{length(@wallets)}</span> porte-monnaie(s)
              </div>
            </div>

            <%!-- État d'erreur de chargement (US: Gestion des erreurs de chargement) --%>
            <.wallets_error_state
              :if={@wallets_error}
              error_message={@wallets_error}
            />

            <%= if is_nil(@wallets_error) do %>
              <%!-- Gestion des états vides (US: Gestion des états vides) --%>
              <%= if @all_wallets == [] do %>
                <div
                  id="empty-wallets-state"
                  class="card bg-base-100 shadow-xl border border-base-200"
                >
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
                <%= if @wallets == [] do %>
                  <%= case @wallet_status_filter do %>
                    <% "open" -> %>
                      <.empty_open_wallets_state />
                    <% "closed" -> %>
                      <.empty_closed_wallets_state />
                    <% _ -> %>
                      <.empty_filtered_wallets_state filter={@wallet_status_filter} />
                  <% end %>
                <% else %>
                  <%!-- Affichage de la liste des cartes (US: Affichage de la liste des portes-monnaies ouverts / clos) --%>
                  <div id="wallets-grid" class="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <%= for wallet <- @wallets do %>
                      <.link
                        navigate={~p"/wallets/#{wallet.id}"}
                        id={"wallet-card-#{wallet.id}"}
                        class="card bg-base-100 shadow hover:shadow-lg border border-base-200 transition-all cursor-pointer group"
                      >
                        <div class="card-body p-6 space-y-3">
                          <div class="flex items-start justify-between gap-2">
                            <div class="space-y-1">
                              <h2 class="text-xl font-bold text-base-content group-hover:text-primary transition-colors">
                                {wallet.name}
                              </h2>
                              <.wallet_status_badge
                                status={wallet.status}
                                id={"wallet-status-badge-#{wallet.id}"}
                              />
                            </div>

                            <span class="badge badge-primary badge-sm font-semibold">
                              {wallet.currency}
                            </span>
                          </div>

                          <p
                            :if={wallet.description}
                            class="text-xs text-base-content/70 line-clamp-2"
                          >
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

                  <.pagination
                    :if={@wallets_pagination}
                    pagination={@wallets_pagination}
                    id="wallets-pagination"
                    item_name="portes-monnaies"
                    path_fn={&wallet_path(@wallet_status_filter, &1)}
                  />
                <% end %>
              <% end %>
            <% end %>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
