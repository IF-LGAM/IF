defmodule LesBonsComptesWeb.WalletLive.ExpenseEdit do
  @moduledoc """
  LiveView pour modifier une dépense existante dans un porte-monnaie.
  Autorisé uniquement en phase de déclaration ("open") pour la personne ayant ajouté
  la dépense ou pour le participant ayant réalisé la dépense.
  """
  use LesBonsComptesWeb, :live_view

  alias LesBonsComptes.Expenses
  alias LesBonsComptes.Wallets
  alias LesBonsComptesWeb.WalletLive.WalletComponents

  @impl true
  def mount(%{"id" => wallet_id, "expense_id" => expense_id}, _session, socket) do
    current_user = socket.assigns.current_user
    wallet = Wallets.get_wallet!(wallet_id)
    expense = Expenses.get_expense!(expense_id)

    cond do
      wallet.status != "open" ->
        {:ok,
         socket
         |> put_flash(
           :error,
           "Impossible de modifier une dépense lorsque le porte-monnaie n'est plus en phase de déclaration."
         )
         |> push_navigate(to: ~p"/wallets/#{wallet.id}")}

      not Expenses.can_edit_expense?(current_user, expense) ->
        {:ok,
         socket
         |> put_flash(
           :error,
           "Vous n'êtes pas autorisé à modifier cette dépense."
         )
         |> push_navigate(to: ~p"/wallets/#{wallet.id}")}

      true ->
        changeset = Expenses.change_expense(expense)

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
         |> assign(:page_title, "Modifier la dépense - #{wallet.name}")
         |> assign(:wallet, wallet)
         |> assign(:expense, expense)
         |> assign(:payer_options, payer_options)
         |> assign(:today, today)
         |> assign(:form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("validate", %{"expense" => expense_params}, socket) do
    wallet = socket.assigns.wallet
    expense = socket.assigns.expense

    params =
      expense_params
      |> Map.put("wallet_id", wallet.id)
      |> Map.put("currency", wallet.currency)

    changeset =
      expense
      |> Expenses.change_expense(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"expense" => expense_params}, socket) do
    current_user = socket.assigns.current_user
    wallet = socket.assigns.wallet
    expense = socket.assigns.expense

    case Expenses.update_expense(current_user, expense, expense_params) do
      {:ok, updated_expense} ->
        amount_formatted = WalletComponents.format_amount(updated_expense.amount)

        {:noreply,
         socket
         |> put_flash(
           :info,
           "La dépense « #{updated_expense.title} » de #{amount_formatted} #{wallet.currency} a été modifiée avec succès !"
         )
         |> push_navigate(to: ~p"/wallets/#{wallet.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(changeset))
         |> put_flash(:error, "Veuillez corriger les erreurs dans le formulaire.")}

      {:error, :wallet_closed} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Impossible de modifier une dépense lorsque le porte-monnaie n'est plus en phase de déclaration."
         )
         |> push_navigate(to: ~p"/wallets/#{wallet.id}")}

      {:error, :unauthorized} ->
        {:noreply,
         socket
         |> put_flash(:error, "Action non autorisée sur cette dépense.")
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

        <%!-- En-tête de la page --%>
        <div class="space-y-1">
          <h1 class="text-3xl font-extrabold tracking-tight text-base-content flex items-center gap-2">
            <.icon name="hero-pencil-square" class="size-8 text-primary" />
            <span>Modifier la dépense</span>
          </h1>
          <p class="text-sm text-base-content/70">
            Modifiez les informations de la dépense pour le groupe « {@wallet.name} ».
          </p>
        </div>

        <%!-- Formulaire de modification --%>
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

              <%!-- Sélection du compte dépenseur --%>
              <div class="bg-base-200/40 rounded-xl p-4 border border-base-200 space-y-3">
                <div class="flex items-center justify-between">
                  <label
                    for="expense-payer-select"
                    class="text-xs font-semibold text-base-content/80 flex items-center gap-1.5"
                  >
                    <.icon name="hero-user-circle" class="size-4 text-primary" />
                    <span>Compte dépenseur (Payé par)</span>
                  </label>
                </div>

                <.input
                  field={@form[:payer_id]}
                  id="expense-payer-select"
                  type="select"
                  options={@payer_options}
                />

                <p class="text-xs text-base-content/60">
                  La dépense est affectée à ce participant dans le calcul des soldes du groupe.
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
                  <span>Enregistrer les modifications</span>
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
