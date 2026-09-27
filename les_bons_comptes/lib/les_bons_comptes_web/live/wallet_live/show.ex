defmodule LesBonsComptesWeb.WalletLive.Show do
  use LesBonsComptesWeb, :live_view

  import LesBonsComptesWeb.WalletLive.WalletComponents
  alias LesBonsComptes.Expenses
  alias LesBonsComptes.Wallets

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    data = load_wallet_data(id)

    {:ok,
     socket
     |> assign(:page_title, "#{data.wallet.name} - Les Bons Comptes")
     |> assign(data)}
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
  def handle_event("delete_expense", %{"id" => id_str}, socket) do
    current_user = socket.assigns.current_user
    wallet = socket.assigns.wallet
    expense_id = String.to_integer(id_str)

    case Expenses.delete_expense(current_user, expense_id) do
      {:ok, deleted_expense} ->
        {:noreply,
         socket
         |> assign(load_wallet_data(wallet.id))
         |> put_flash(
           :info,
           "La dépense « #{deleted_expense.title} » a été supprimée avec succès."
         )}

      {:error, :unauthorized} ->
        {:noreply,
         socket
         |> put_flash(:error, "Vous n'êtes pas autorisé à supprimer cette dépense.")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Impossible de supprimer cette dépense.")}
    end
  end

  defp load_wallet_data(wallet_id) do
    wallet = Wallets.get_wallet!(wallet_id)
    total_expenses = Expenses.total_expenses_for_wallet(wallet.id)
    expenses_by_member = Expenses.total_expenses_by_member(wallet.id)

    creditors = Expenses.calculate_creditors(wallet)

    %{
      wallet: wallet,
      total_expenses: total_expenses,
      expenses_by_member: expenses_by_member,
      creditors: creditors
    }
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
                <%= if @current_user && Enum.any?(@wallet.members, &(&1.user_id == @current_user.id)) do %>
                  <.link
                    navigate={~p"/wallets/#{@wallet.id}/expenses/new"}
                    id="add-expense-btn"
                    class="btn btn-primary btn-sm gap-1.5 shadow-sm"
                  >
                    <.icon name="hero-plus-circle" class="size-4" />
                    <span>Ajouter une dépense</span>
                  </.link>
                <% end %>

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
                <div id="total-expenses-amount" class="text-2xl font-bold text-base-content mt-1">
                  {format_amount(@total_expenses)} {@wallet.currency}
                </div>
                <div class="text-xs text-base-content/50 mt-0.5">
                  <%= if length(@wallet.expenses) == 0 do %>
                    Aucune dépense pour le moment
                  <% else %>
                    {length(@wallet.expenses)} dépense(s) enregistrée(s)
                  <% end %>
                </div>
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

        <%!-- Dépenses du groupe (IF-62, IF-65, IF-66) --%>
        <div class="card bg-base-100 shadow-xl border border-base-200">
          <div class="card-body p-6 sm:p-8 space-y-4">
            <div class="flex items-center justify-between">
              <h2 class="text-lg font-bold text-base-content flex items-center gap-2">
                <.icon name="hero-banknotes" class="size-5 text-primary" />
                <span>Dépenses ({length(@wallet.expenses)})</span>
              </h2>

              <%= if @current_user && Enum.any?(@wallet.members, &(&1.user_id == @current_user.id)) do %>
                <.link
                  navigate={~p"/wallets/#{@wallet.id}/expenses/new"}
                  id="section-add-expense-btn"
                  class="btn btn-primary btn-xs gap-1 shadow-sm"
                >
                  <.icon name="hero-plus" class="size-3.5" />
                  <span>Ajouter une dépense</span>
                </.link>
              <% end %>
            </div>

            <%= if @wallet.expenses == [] do %>
              <div
                id="no-expenses-message"
                class="text-center py-8 text-base-content/60 bg-base-200/30 rounded-xl border border-dashed border-base-300 space-y-2"
              >
                <.icon name="hero-banknotes" class="size-8 mx-auto text-base-content/30" />
                <p class="font-medium text-sm">Aucune dépense enregistrée</p>
                <p class="text-xs">
                  Chaque membre du groupe peut déclarer ses dépenses et elles lui sont directement affectées.
                </p>
                <%= if @current_user && Enum.any?(@wallet.members, &(&1.user_id == @current_user.id)) do %>
                  <div class="pt-2">
                    <.link
                      navigate={~p"/wallets/#{@wallet.id}/expenses/new"}
                      id="empty-state-add-expense-btn"
                      class="btn btn-primary btn-xs gap-1"
                    >
                      <.icon name="hero-plus" class="size-3.5" />
                      <span>Déclarer ma première dépense</span>
                    </.link>
                  </div>
                <% end %>
              </div>
            <% else %>
              <div id="wallet-expenses-list" class="divide-y divide-base-200">
                <%= for expense <- @wallet.expenses do %>
                  <.expense_item
                    expense={expense}
                    can_delete={Expenses.can_delete_expense?(@current_user, expense)}
                  />
                <% end %>
              </div>
            <% end %>
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
                  <span>Gérer les participants & invitations</span>
                </.link>
              <% end %>
            </div>

            <div id="wallet-members-list" class="divide-y divide-base-200">
              <%= for member <- @wallet.members do %>
                <div id={"member-item-#{member.id}"} class="py-3 flex items-center justify-between">
                  <div class="flex items-center gap-3">
                    <.member_avatar
                      name={member.name}
                      is_owner={member.role == "owner"}
                      size="size-10"
                    />
                    <div>
                      <div class="font-semibold text-sm text-base-content flex items-center gap-2">
                        <span>{member.name}</span>
                        <.member_badge role={member.role} />
                      </div>
                      <div :if={member.email} class="text-xs text-base-content/60">
                        {member.email}
                      </div>
                    </div>
                  </div>

                  <div class="text-right">
                    <span class="text-sm font-semibold text-base-content/80">
                      {format_amount(Map.get(@expenses_by_member, member.id, Decimal.new("0.00")))} {@wallet.currency}
                    </span>
                    <div class="text-xs text-base-content/50">Dépensé</div>
                  </div>
                </div>
              <% end %>
            </div>

            <%!-- Invitations envoyées (IF-43) --%>
            <div :if={@wallet.invitations != []} class="mt-4 pt-4 border-t border-base-200 space-y-3">
              <div class="flex items-center justify-between">
                <span class="text-xs font-semibold text-base-content/70 uppercase tracking-wider flex items-center gap-1.5">
                  <.icon name="hero-envelope" class="size-4 text-primary" />
                  <span>Invitations envoyées ({length(@wallet.invitations)})</span>
                </span>
              </div>
              <div id="wallet-pending-invitations-list" class="space-y-2">
                <%= for invitation <- @wallet.invitations do %>
                  <div
                    id={"show-pending-invitation-#{invitation.id}"}
                    class={[
                      "p-2.5 rounded-xl border flex items-center justify-between text-xs transition-colors",
                      if(invitation.status == "declined",
                        do: "bg-error/5 border-error/20",
                        else: "bg-warning/5 border-warning/20"
                      )
                    ]}
                  >
                    <div class="flex items-center gap-2">
                      <.member_avatar name={invitation.invitee.name} size="size-7" />
                      <div>
                        <span class="font-semibold text-base-content">{invitation.invitee.name}</span>
                        <span class="text-base-content/60">({invitation.email})</span>
                      </div>
                    </div>
                    <.invitation_badge status={invitation.status} />
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
