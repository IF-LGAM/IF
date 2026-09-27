defmodule LesBonsComptesWeb.WalletLive.Show do
  use LesBonsComptesWeb, :live_view

  import LesBonsComptesWeb.WalletLive.WalletComponents
  alias LesBonsComptes.Expenses
  alias LesBonsComptes.Wallets

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(LesBonsComptes.PubSub, "wallet:#{id}")
    end

    case load_wallet_data(id) do
      {:ok, data} ->
        {:ok,
         socket
         |> assign(:page_title, "#{data.wallet.name} - Les Bons Comptes")
         |> assign(data)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Ce porte-monnaie n'existe pas ou est introuvable.")
         |> push_navigate(to: ~p"/wallets")}
    end
  end

  @impl true
  def handle_info({:wallet_updated, wallet_id}, socket) do
    case load_wallet_data(wallet_id) do
      {:ok, data} ->
        {:noreply, assign(socket, data)}

      {:error, _} ->
        {:noreply, socket}
    end
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
        case load_wallet_data(wallet.id) do
          {:ok, data} ->
            {:noreply,
             socket
             |> assign(data)
             |> put_flash(
               :info,
               "La dépense « #{deleted_expense.title} » a été supprimée avec succès."
             )}

          {:error, :not_found} ->
            {:noreply,
             socket
             |> put_flash(:error, "Ce porte-monnaie n'existe pas ou est introuvable.")
             |> push_navigate(to: ~p"/wallets")}
        end

      {:error, :unauthorized} ->
        {:noreply,
         socket
         |> put_flash(:error, "Vous n'êtes pas autorisé à supprimer cette dépense.")}

      {:error, :wallet_closed} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Impossible de supprimer une dépense lorsque le porte-monnaie n'est plus en phase de déclaration."
         )}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Impossible de supprimer cette dépense.")}
    end
  end

  @impl true
  def handle_event("validate_wallet", _params, socket) do
    current_user = socket.assigns.current_user
    wallet = socket.assigns.wallet

    case Wallets.validate_wallet(current_user, wallet) do
      {:ok, updated_wallet} ->
        case load_wallet_data(wallet.id) do
          {:ok, data} ->
            if data.settlements == [] do
              case Wallets.close_wallet(current_user, updated_wallet) do
                {:ok, _closed_wallet} ->
                  {:ok, closed_data} = load_wallet_data(wallet.id)

                  {:noreply,
                   socket
                   |> assign(closed_data)
                   |> put_flash(
                     :info,
                     "Le porte-monnaie « #{wallet.name} » a été validé. Tous les comptes étant déjà équilibrés, il a été clôturé automatiquement."
                   )}

                _ ->
                  {:noreply,
                   socket
                   |> assign(data)
                   |> put_flash(
                     :info,
                     "Le porte-monnaie « #{wallet.name} » a été validé."
                   )}
              end
            else
              {:noreply,
               socket
               |> assign(data)
               |> put_flash(
                 :info,
                 "Le porte-monnaie « #{wallet.name} » a été validé. Les dépenses sont figées et les virements peuvent être réglés."
               )}
            end

          {:error, :not_found} ->
            {:noreply, push_navigate(socket, to: ~p"/wallets")}
        end

      {:error, :unauthorized} ->
        {:noreply,
         socket
         |> put_flash(:error, "Seul le propriétaire peut valider ce porte-monnaie.")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Impossible de valider ce porte-monnaie.")}
    end
  end

  @impl true
  def handle_event("reopen_wallet", _params, socket) do
    current_user = socket.assigns.current_user
    wallet = socket.assigns.wallet

    cond do
      wallet.status == "closed" ->
        {:noreply,
         socket
         |> put_flash(:error, "La clôture de ce porte-monnaie est définitive.")}

      MapSet.size(socket.assigns.mock_settled_ids) > 0 ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Impossible d'annuler la validation : des virements ont déjà été effectués et sont définitifs."
         )}

      true ->
        case Wallets.reopen_wallet(current_user, wallet) do
          {:ok, _updated_wallet} ->
            case load_wallet_data(wallet.id) do
              {:ok, data} ->
                {:noreply,
                 socket
                 |> assign(data)
                 |> put_flash(
                   :info,
                   "Le porte-monnaie « #{wallet.name} » a été rouvert. Vous pouvez à nouveau y ajouter des dépenses."
                 )}

              {:error, :not_found} ->
                {:noreply, push_navigate(socket, to: ~p"/wallets")}
            end

          {:error, :unauthorized} ->
            {:noreply,
             socket
             |> put_flash(:error, "Seul le propriétaire peut rouvrir ce porte-monnaie.")}

          {:error, :closure_is_final} ->
            {:noreply,
             socket
             |> put_flash(:error, "La clôture de ce porte-monnaie est définitive.")}

          {:error, _reason} ->
            {:noreply,
             socket
             |> put_flash(:error, "Impossible de rouvrir ce porte-monnaie.")}
        end
    end
  end

  @impl true
  def handle_event(
        "mock_settle",
        %{
          "from_id" => from_id,
          "to_id" => to_id,
          "from_name" => from_name,
          "to_name" => to_name,
          "amount" => amount
        },
        socket
      ) do
    wallet = socket.assigns.wallet
    current_user = socket.assigns.current_user

    case Expenses.settle_transfer(current_user, wallet, from_id, to_id, amount) do
      {:ok, _settlement} ->
        {:ok, new_data} = load_wallet_data(wallet.id)
        currency = new_data.wallet.currency

        if new_data.wallet.status == "closed" do
          {:noreply,
           socket
           |> assign(new_data)
           |> put_flash(
             :info,
             "Dernier virement de #{amount} #{currency} de #{from_name} vers #{to_name} réglé ! Tous les virements sont effectués, le porte-monnaie est désormais clôturé définitivement."
           )}
        else
          {:noreply,
           socket
           |> assign(new_data)
           |> put_flash(
             :info,
             "Virement de #{amount} #{currency} de #{from_name} vers #{to_name} marqué comme réglé."
           )}
        end

      {:error, :unauthorized} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Seul le membre devant réaliser ce virement peut le marquer comme réglé."
         )}

      {:error, :wallet_not_in_settlement} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Impossible d'effectuer le virement : le porte-monnaie doit d'abord être validé par son propriétaire."
         )}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Impossible d'enregistrer ce virement.")}
    end
  end

  defp load_wallet_data(wallet_id) do
    try do
      wallet = Wallets.get_wallet!(wallet_id)
      total_expenses = Expenses.total_expenses_for_wallet(wallet.id)
      expenses_by_member = Expenses.total_expenses_by_member(wallet.id)
      creditors = Expenses.calculate_creditors(wallet)
      debtors = Expenses.calculate_debtors(wallet)
      settlements = Expenses.calculate_settlements(wallet)
      settled_records = Expenses.list_settled_transfers(wallet.id)
      mock_settled_ids = MapSet.new(settled_records, &"#{&1.from_id}->#{&1.to_id}")

      {:ok,
       %{
         wallet: wallet,
         total_expenses: total_expenses,
         expenses_by_member: expenses_by_member,
         creditors: creditors,
         debtors: debtors,
         settlements: settlements,
         mock_settled_ids: mock_settled_ids
       }}
    rescue
      _ in [Ecto.NoResultsError, ArgumentError] ->
        {:error, :not_found}
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
                  <.wallet_status_badge status={@wallet.status} />
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
                <%= if @wallet.status == "open" and @current_user && Enum.any?(@wallet.members, &(&1.user_id == @current_user.id)) do %>
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
                  <%= case @wallet.status do %>
                    <% "open" -> %>
                      <button
                        type="button"
                        id="validate-wallet-btn"
                        phx-click="validate_wallet"
                        data-confirm="Êtes-vous sûr de vouloir valider les comptes ? Les dépenses seront figées et vous passerez à l'étape des virements."
                        class="btn btn-primary btn-sm gap-1 shadow-sm"
                      >
                        <.icon name="hero-check" class="size-4" />
                        <span>Valider les comptes</span>
                      </button>

                    <% "pending_settlement" -> %>
                      <%= if MapSet.size(@mock_settled_ids) == 0 do %>
                        <button
                          type="button"
                          id="reopen-wallet-btn"
                          phx-click="reopen_wallet"
                          class="btn btn-ghost btn-sm gap-1 text-base-content/70"
                          title="Rouvrir pour modifier des dépenses"
                        >
                          <.icon name="hero-arrow-uturn-left" class="size-4" />
                          <span>Rouvrir</span>
                        </button>
                      <% end %>

                    <% "closed" -> %>
                      <%!-- Clôture définitive : aucun bouton de réouverture ni de clôture --%>
                  <% end %>

                  <%= if @wallet.status == "open" do %>
                    <.link
                      navigate={~p"/wallets/#{@wallet.id}/edit"}
                      id="edit-wallet-btn"
                      class="btn btn-outline btn-sm gap-1"
                    >
                      <.icon name="hero-pencil-square" class="size-4" />
                      <span>Modifier</span>
                    </.link>
                  <% end %>

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

            <%!-- Stepper des 3 étapes du porte-monnaie (IF-85) --%>
            <.wallet_lifecycle_stepper status={@wallet.status} />

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

              <%= if @wallet.status == "open" and @current_user && Enum.any?(@wallet.members, &(&1.user_id == @current_user.id)) do %>
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
                <%= if @wallet.status == "open" and @current_user && Enum.any?(@wallet.members, &(&1.user_id == @current_user.id)) do %>
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
                    can_edit={Expenses.can_edit_expense?(@current_user, expense)}
                    edit_link={~p"/wallets/#{@wallet.id}/expenses/#{expense.id}/edit"}
                  />
                <% end %>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Comptes à rembourser (US : Lister les comptes qui doivent recevoir de l’argent et combien) --%>
        <div id="wallet-creditors-section" class="card bg-base-100 shadow-xl border border-base-200">
          <div class="card-body p-6 sm:p-8 space-y-4">
            <div class="flex items-center justify-between">
              <div class="space-y-0.5">
                <h2 class="text-lg font-bold text-base-content flex items-center gap-2">
                  <.icon name="hero-arrow-path" class="size-5 text-success" />
                  <span>Comptes à rembourser ({length(@creditors)})</span>
                </h2>
                <p class="text-xs text-base-content/60">
                  Participants ayant avancé des frais et devant recevoir un remboursement
                </p>
              </div>

              <%= if @creditors != [] do %>
                <span id="creditors-count-badge" class="badge badge-success badge-sm font-semibold">
                  {length(@creditors)} bénéficiaire(s)
                </span>
              <% end %>
            </div>

            <%= if @creditors == [] do %>
              <div
                id="no-creditors-message"
                class="text-center py-8 text-base-content/60 bg-base-200/30 rounded-xl border border-dashed border-base-300 space-y-2"
              >
                <.icon name="hero-check-badge" class="size-8 mx-auto text-success/60" />
                <%= if @wallet.expenses == [] do %>
                  <p class="font-medium text-sm">Aucun remboursement en attente</p>
                  <p class="text-xs">
                    Ajoutez des dépenses au groupe pour calculer automatiquement les soldes et les montants à recevoir.
                  </p>
                <% else %>
                  <p class="font-medium text-sm">Les comptes sont équilibrés !</p>
                  <p class="text-xs">
                    Chaque participant a payé exactement sa part équitable. Aucun remboursement n'est nécessaire.
                  </p>
                <% end %>
              </div>
            <% else %>
              <div id="wallet-creditors-list" class="divide-y divide-base-200">
                <%= for creditor <- @creditors do %>
                  <.creditor_item creditor={creditor} currency={@wallet.currency} />
                <% end %>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Comptes qui doivent donner de l'argent (US : Liste des comptes qui doivent donner de l’argent et combien) --%>
        <div id="wallet-debtors-section" class="card bg-base-100 shadow-xl border border-base-200">
          <div class="card-body p-6 sm:p-8 space-y-4">
            <div class="flex items-center justify-between">
              <div class="space-y-0.5">
                <h2 class="text-lg font-bold text-base-content flex items-center gap-2">
                  <.icon name="hero-arrow-up-right" class="size-5 text-warning" />
                  <span>Comptes qui doivent donner de l'argent ({length(@debtors)})</span>
                </h2>
                <p class="text-xs text-base-content/60">
                  Participants devant régler leur part des dépenses communes
                </p>
              </div>

              <%= if @debtors != [] do %>
                <span id="debtors-count-badge" class="badge badge-warning badge-sm font-semibold">
                  {length(@debtors)} débiteur(s)
                </span>
              <% end %>
            </div>

            <%= if @debtors == [] do %>
              <div
                id="no-debtors-message"
                class="text-center py-8 text-base-content/60 bg-base-200/30 rounded-xl border border-dashed border-base-300 space-y-2"
              >
                <.icon name="hero-check-badge" class="size-8 mx-auto text-success/60" />
                <%= if @wallet.expenses == [] do %>
                  <p class="font-medium text-sm">Aucun montant à régler</p>
                  <p class="text-xs">
                    Ajoutez des dépenses au groupe pour calculer automatiquement les soldes et les montants à payer.
                  </p>
                <% else %>
                  <p class="font-medium text-sm">Les comptes sont équilibrés !</p>
                  <p class="text-xs">
                    Chaque participant a payé sa part exacte. Aucun remboursement n'est dû.
                  </p>
                <% end %>
              </div>
            <% else %>
              <div id="wallet-debtors-list" class="divide-y divide-base-200">
                <%= for debtor <- @debtors do %>
                  <.debtor_item debtor={debtor} currency={@wallet.currency} />
                <% end %>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Virements proposés (US : Calculer qui donne combien à qui en minimisant les virements) --%>
        <div id="wallet-settlements-section" class="card bg-base-100 shadow-xl border border-base-200">
          <div class="card-body p-6 sm:p-8 space-y-4">
            <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
              <div class="space-y-0.5">
                <h2 class="text-lg font-bold text-base-content flex items-center gap-2">
                  <.icon name="hero-arrows-right-left" class="size-5 text-primary" />
                  <span>Virements proposés ({length(@settlements)})</span>
                </h2>
                <p class="text-xs text-base-content/60">
                  Transactions optimisées pour solder toutes les dettes avec le minimum de virements
                </p>
              </div>

              <div class="flex items-center gap-2">
                <%= if @settlements != [] do %>
                  <span id="settlements-count-badge" class="badge badge-primary badge-sm font-semibold">
                    {length(@settlements)} virement(s)
                  </span>
                <% end %>
              </div>
            </div>

            <%= if @wallet.status == "open" do %>
              <div
                id="wallet-open-notice"
                class="p-3 bg-warning/10 border border-warning/30 rounded-xl text-xs flex flex-col sm:flex-row sm:items-center justify-between gap-3"
              >
                <div class="flex items-center gap-2 text-base-content/80">
                  <.icon name="hero-information-circle" class="size-5 text-warning shrink-0" />
                  <span>Le porte-monnaie est actuellement en cours de déclarations. Validez-le pour enregistrer les virements.</span>
                </div>

                <%= if @current_user && @current_user.id == @wallet.creator_id do %>
                  <button
                    type="button"
                    id="notice-validate-wallet-btn"
                    phx-click="validate_wallet"
                    class="btn btn-warning btn-xs shrink-0 gap-1 font-semibold"
                  >
                    <.icon name="hero-check" class="size-3" />
                    <span>Valider les comptes</span>
                  </button>
                <% end %>
              </div>
            <% end %>

            <%= if @settlements != [] do %>
              <.simulated_settlements_summary
                settlements={@settlements}
                mock_settled_ids={@mock_settled_ids}
                currency={@wallet.currency}
                is_closed={@wallet.status in ["pending_settlement", "closed"]}
              />
            <% end %>

            <%= if @settlements == [] do %>
              <div
                id="no-settlements-message"
                class="text-center py-8 text-base-content/60 bg-base-200/30 rounded-xl border border-dashed border-base-300 space-y-2"
              >
                <%= if @wallet.expenses == [] do %>
                  <.icon name="hero-arrows-right-left" class="size-8 mx-auto text-base-content/30" />
                  <p class="font-medium text-sm">Aucun virement nécessaire</p>
                  <p class="text-xs">
                    Ajoutez des dépenses au groupe pour calculer automatiquement les virements optimisés entre participants.
                  </p>
                <% else %>
                  <.icon name="hero-check-badge" class="size-8 mx-auto text-success/60" />
                  <p class="font-medium text-sm">Les comptes sont parfaitement équilibrés !</p>
                  <p class="text-xs">
                    Chaque participant a payé sa part exacte. Aucun virement n'est nécessaire.
                  </p>
                <% end %>
              </div>
            <% else %>
              <div id="wallet-settlements-list" class="space-y-3">
                <%= for settlement <- @settlements do %>
                  <.settlement_item
                    settlement={settlement}
                    currency={@wallet.currency}
                    is_mock_settled={MapSet.member?(@mock_settled_ids, "#{settlement.from_id}->#{settlement.to_id}")}
                    status={@wallet.status}
                    is_closed={@wallet.status in ["pending_settlement", "closed"]}
                    current_user={@current_user}
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

              <%= if @wallet.status == "open" and @current_user && @current_user.id == @wallet.creator_id do %>
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
