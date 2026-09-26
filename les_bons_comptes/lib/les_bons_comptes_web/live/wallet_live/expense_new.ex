defmodule LesBonsComptesWeb.WalletLive.ExpenseNew do
  @moduledoc """
  LiveView pour déclarer une nouvelle dépense dans un porte-monnaie (IF-62).
  Permet à chaque membre de créer une dépense qui lui est directement affectée par défaut (IF-68, IF-70),
  avec validation en direct des champs (IF-67, IF-69) et confirmation de création (IF-71).
  """
  use LesBonsComptesWeb, :live_view

  alias LesBonsComptes.Expenses
  alias LesBonsComptes.Expenses.Expense
  alias LesBonsComptes.Wallets
  alias LesBonsComptesWeb.WalletLive.WalletComponents

  @impl true
  def mount(%{"id" => wallet_id}, _session, socket) do
    current_user = socket.assigns.current_user
    wallet = Wallets.get_wallet!(wallet_id)

    # Vérification d'autorisation : l'utilisateur doit être membre ou propriétaire
    current_member = Enum.find(wallet.members, &(&1.user_id == current_user.id))

    if is_nil(current_member) do
      {:ok,
       socket
       |> put_flash(
         :error,
         "Vous devez être membre de ce porte-monnaie pour déclarer une dépense."
       )
       |> push_navigate(to: ~p"/wallets")}
    else
      # Compte dépenseur pré-sélectionné : le membre connecté lui-même (IF-68, IF-70)
      default_attrs = %{
        "payer_id" => current_member.id,
        "date" => Date.to_iso8601(Date.utc_today()),
        "currency" => wallet.currency
      }

      changeset = Expenses.change_expense(%Expense{}, default_attrs)

      payer_options =
        Enum.map(wallet.members, fn member ->
          label =
            if member.user_id == current_user.id do
              "#{member.name} (Moi)"
            else
              member.name
            end

          {label, member.id}
        end)

      today = Date.to_iso8601(Date.utc_today())

      {:ok,
       socket
       |> assign(:wallet, wallet)
       |> assign(:current_member, current_member)
       |> assign(:payer_options, payer_options)
       |> assign(:today, today)
       |> assign(:form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("validate", %{"expense" => expense_params}, socket) do
    # Conserve le wallet_id et currency dans la validation
    wallet = socket.assigns.wallet

    params =
      expense_params
      |> Map.put("wallet_id", wallet.id)
      |> Map.put("currency", wallet.currency)

    changeset =
      %Expense{}
      |> Expenses.change_expense(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"expense" => expense_params}, socket) do
    current_user = socket.assigns.current_user
    wallet = socket.assigns.wallet

    case Expenses.create_expense(current_user, wallet, expense_params) do
      {:ok, expense} ->
        # Confirmation de déclaration de la dépense (IF-71)
        amount_formatted = WalletComponents.format_amount(expense.amount)

        {:noreply,
         socket
         |> put_flash(
           :info,
           "La dépense « #{expense.title} » de #{amount_formatted} #{wallet.currency} a été enregistrée avec succès !"
         )
         |> push_navigate(to: ~p"/wallets/#{wallet.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(changeset))
         |> put_flash(:error, "Veuillez corriger les erreurs dans le formulaire.")}

      {:error, :unauthorized} ->
        {:noreply,
         socket
         |> put_flash(:error, "Action non autorisée sur ce porte-monnaie.")
         |> push_navigate(to: ~p"/wallets/#{wallet.id}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="max-w-2xl mx-auto space-y-6">
        <%!-- Fil d'Ariane & Bouton retour --%>
        <div class="flex items-center justify-between">
          <.link
            navigate={~p"/wallets/#{@wallet.id}"}
            id="back-to-wallet-btn"
            class="btn btn-ghost btn-sm gap-2 text-base-content/70 hover:text-base-content"
          >
            <.icon name="hero-arrow-left" class="size-4" />
            <span>Retour à « {@wallet.name} »</span>
          </.link>
          <span class="badge badge-primary font-bold">
            {@wallet.currency}
          </span>
        </div>

        <%!-- En-tête de la page (IF-65) --%>
        <div class="space-y-1">
          <h1 class="text-3xl font-extrabold tracking-tight text-base-content flex items-center gap-2">
            <.icon name="hero-banknotes" class="size-8 text-primary" />
            <span>Déclarer une dépense</span>
          </h1>
          <p class="text-sm text-base-content/70">
            Enregistrez une nouvelle dépense pour le groupe « {@wallet.name} ».
          </p>
        </div>

        <%!-- Formulaire de déclaration (IF-65, IF-67, IF-68) --%>
        <div class="card bg-base-100 shadow-xl border border-base-200">
          <div class="card-body p-6 sm:p-8">
            <.form
              for={@form}
              id="expense-form"
              phx-change="validate"
              phx-submit="save"
              class="space-y-6"
            >
              <%!-- Titre de la dépense --%>
              <.input
                field={@form[:title]}
                id="expense-title-input"
                type="text"
                label="Titre de la dépense"
                placeholder="Ex : Courses du weekend, Restaurant tapas, Billets de train..."
                required
              />

              <%!-- Montant et Devise --%>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div>
                  <.input
                    field={@form[:amount]}
                    id="expense-amount-input"
                    type="number"
                    step="0.01"
                    min="0.01"
                    label={"Montant (#{@wallet.currency})"}
                    placeholder="0.00"
                    required
                  />
                </div>

                <%!-- Date de la dépense --%>
                <div>
                  <.input
                    field={@form[:date]}
                    id="expense-date-input"
                    type="date"
                    max={@today}
                    label="Date de la dépense"
                    required
                  />
                </div>
              </div>

              <%!-- Sélection du compte dépenseur (IF-68, IF-70) --%>
              <div class="bg-base-200/40 rounded-xl p-4 border border-base-200 space-y-3">
                <div class="flex items-center justify-between">
                  <label
                    for="expense-payer-select"
                    class="text-xs font-semibold text-base-content/80 flex items-center gap-1.5"
                  >
                    <.icon name="hero-user-circle" class="size-4 text-primary" />
                    <span>Compte dépenseur (Payé par)</span>
                  </label>
                  <span class="badge badge-info badge-xs gap-1">
                    <.icon name="hero-check" class="size-2.5" /> Par défaut : vous-même
                  </span>
                </div>

                <.input
                  field={@form[:payer_id]}
                  id="expense-payer-select"
                  type="select"
                  options={@payer_options}
                />

                <p class="text-xs text-base-content/60">
                  La dépense est automatiquement affectée à ce participant dans le calcul des soldes du groupe.
                </p>
              </div>

              <%!-- Description / Notes optionnelles --%>
              <.input
                field={@form[:description]}
                id="expense-description-input"
                type="text"
                label="Description ou note (optionnel)"
                placeholder="Ex : Ticket de caisse partagé avec le groupe"
              />

              <%!-- Boutons d'action --%>
              <div class="divider my-2"></div>

              <div class="flex items-center justify-end gap-3 pt-2">
                <.link
                  navigate={~p"/wallets/#{@wallet.id}"}
                  id="cancel-expense-btn"
                  class="btn btn-ghost btn-sm"
                >
                  Annuler
                </.link>

                <button
                  type="submit"
                  id="submit-expense-btn"
                  phx-disable-with="Enregistrement en cours..."
                  class="btn btn-primary btn-sm px-6 gap-2 shadow-sm"
                >
                  <.icon name="hero-check" class="size-4" />
                  <span>Confirmer la dépense</span>
                </button>
              </div>
            </.form>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
