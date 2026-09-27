defmodule LesBonsComptesWeb.WalletLive.WalletComponents do
  @moduledoc """
  Composants UI réutilisables pour les vues Wallet (New, Edit, Show).
  """
  use LesBonsComptesWeb, :html

  alias LesBonsComptes.Wallets.Wallet

  @doc """
  Affiche le badge d'un membre (Propriétaire ou Inscrit).
  """
  attr :role, :string, default: "member"
  attr :is_owner, :boolean, default: false

  def member_badge(assigns) do
    is_owner = assigns.is_owner or assigns.role == "owner"
    assigns = assign(assigns, :is_owner, is_owner)

    ~H"""
    <%= if @is_owner do %>
      <span class="badge badge-primary badge-xs gap-1">
        <.icon name="hero-star" class="size-2.5" /> Propriétaire
      </span>
    <% else %>
      <span class="badge badge-info badge-xs gap-0.5">
        <.icon name="hero-check" class="size-2.5" /> Inscrit
      </span>
    <% end %>
    """
  end

  @doc """
  Affiche le badge du statut du porte-monnaie selon l'étape (IF-85).
  - open : Étape 1 : Ouvert (Déclarations en cours)
  - pending_settlement : Étape 2 : Attente des virements
  - closed : Étape 3 : Clos
  """
  attr :status, :string, default: "open"

  def wallet_status_badge(assigns) do
    ~H"""
    <%= case @status do %>
      <% "closed" -> %>
        <span id="wallet-status-badge" class="badge badge-neutral font-bold gap-1 shadow-sm">
          <.icon name="hero-check-badge" class="size-3" /> Clos
        </span>
      <% "pending_settlement" -> %>
        <span id="wallet-status-badge" class="badge badge-warning font-bold gap-1 shadow-sm">
          <.icon name="hero-clock" class="size-3" /> Attente des virements
        </span>
      <% _ -> %>
        <span id="wallet-status-badge" class="badge badge-success font-bold gap-1 shadow-sm">
          <.icon name="hero-lock-open" class="size-3" /> Ouvert
        </span>
    <% end %>
    """
  end

  @doc """
  Affiche le stepper horizontal visuel des 3 étapes du porte-monnaie (IF-85).
  Étape 1 : Déclarations & Invitations
  Étape 2 : Attente des virements
  Étape 3 : Clôture
  """
  attr :status, :string, default: "open"

  def wallet_lifecycle_stepper(assigns) do
    step =
      case assigns.status do
        "closed" -> 3
        "pending_settlement" -> 2
        _ -> 1
      end

    assigns = assign(assigns, :step, step)

    ~H"""
    <div id="wallet-lifecycle-stepper" class="w-full bg-base-100 rounded-2xl p-4 border border-base-200 shadow-sm">
      <ul class="steps steps-horizontal w-full text-xs">
        <li class={[
          "step",
          @step >= 1 && "step-primary font-semibold"
        ]} data-content={if(@step > 1, do: "✓", else: "1")}>
          <span class="text-xs">1. Déclarations</span>
        </li>
        <li class={[
          "step",
          @step >= 2 && "step-primary font-semibold"
        ]} data-content={if(@step > 2, do: "✓", else: "2")}>
          <span class="text-xs">2. Attente des virements</span>
        </li>
        <li class={[
          "step",
          @step >= 3 && "step-success font-semibold"
        ]} data-content={if(@step >= 3, do: "✓", else: "3")}>
          <span class="text-xs">3. Clôture</span>
        </li>
      </ul>
    </div>
    """
  end


  @doc """
  Affiche le badge du statut d'une invitation.
  """
  attr :status, :string, default: "pending"

  def invitation_badge(assigns) do
    ~H"""
    <%= case @status do %>
      <% "pending" -> %>
        <span class="badge badge-warning badge-xs gap-1">
          <.icon name="hero-paper-airplane" class="size-2.5" /> Invitation envoyée
        </span>
      <% "accepted" -> %>
        <span class="badge badge-success badge-xs gap-1">
          <.icon name="hero-check" class="size-2.5" /> Acceptée
        </span>
      <% "declined" -> %>
        <span class="badge badge-error badge-xs gap-1">
          <.icon name="hero-x-mark" class="size-2.5" /> Refusée
        </span>
      <% _ -> %>
        <span class="badge badge-ghost badge-xs">
          {@status}
        </span>
    <% end %>
    """
  end

  @doc """
  Affiche l'avatar circulaire avec la première lettre du nom.
  """
  attr :name, :string, default: "?"
  attr :is_owner, :boolean, default: false
  attr :size, :string, default: "size-9"

  def member_avatar(assigns) do
    initial =
      case assigns.name do
        nil -> "?"
        "" -> "?"
        str -> String.first(str)
      end

    assigns = assign(assigns, :initial, initial)

    ~H"""
    <div class={[
      @size,
      "rounded-full flex items-center justify-center font-bold text-sm shadow-sm",
      if(@is_owner, do: "bg-primary text-primary-content", else: "bg-base-300 text-base-content")
    ]}>
      {@initial}
    </div>
    """
  end

  @doc """
  Rendu des champs généraux du formulaire Wallet (nom, devise, description).
  """
  attr :form, Phoenix.HTML.Form, required: true

  def wallet_fields(assigns) do
    assigns = assign(assigns, :currency_options, Wallet.currency_options())

    ~H"""
    <div class="space-y-4">
      <.input
        field={@form[:name]}
        id="wallet-name-input"
        type="text"
        label="Nom du porte-monnaie"
        placeholder="Ex : Vacances à Barcelone, Coloc 2026, Weekend Ski..."
        required
      />

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input
          field={@form[:currency]}
          id="wallet-currency-select"
          type="select"
          label="Devise"
          options={@currency_options}
        />

        <.input
          field={@form[:description]}
          id="wallet-description-input"
          type="text"
          label="Description (optionnel)"
          placeholder="Ex : Dépenses de groupe pour l'été"
        />
      </div>
    </div>
    """
  end

  @doc """
  Sélecteur de participants : suggestions d'utilisateurs inscrits + ajout manuel par email.
  """
  attr :available_users, :list, default: []
  attr :custom_email, :string, default: ""
  attr :add_registered_event, :string, default: "add_registered_user"
  attr :add_custom_event, :string, default: "add_custom_participant"
  attr :input_id, :string, default: "custom-participant-email"
  attr :button_id, :string, default: "add-custom-participant-btn"
  attr :button_label, :string, default: "Ajouter ce participant"

  def participant_selector(assigns) do
    ~H"""
    <div class="space-y-4">
      <%!-- Option A : Suggestions parmi les utilisateurs inscrits --%>
      <div :if={@available_users != []} class="space-y-2">
        <label class="text-xs font-semibold text-base-content/70">
          Ajouter un utilisateur inscrit sur Les Bons Comptes :
        </label>
        <div class="flex flex-wrap gap-2">
          <%= for user <- @available_users do %>
            <button
              type="button"
              id={"add-user-btn-#{user.id}"}
              phx-click={@add_registered_event}
              phx-value-user_id={user.id}
              class="btn btn-outline btn-xs sm:btn-sm gap-1 hover:btn-primary"
            >
              <.icon name="hero-user-plus" class="size-3.5" />
              <span>{user.name}</span>
              <span class="text-xs opacity-60">({user.email})</span>
            </button>
          <% end %>
        </div>
      </div>

      <%!-- Option B : Ajouter un participant inscrit par email --%>
      <div class="bg-base-200/40 rounded-xl p-4 border border-base-200 space-y-3">
        <label class="text-xs font-semibold text-base-content/80 flex items-center gap-1.5">
          <.icon name="hero-envelope" class="size-4 text-base-content/60" />
          <span>Ou ajouter un participant inscrit par son adresse email :</span>
        </label>

        <div class="flex flex-col sm:flex-row gap-2">
          <input
            type="email"
            id={@input_id}
            name="custom_email"
            value={@custom_email}
            placeholder="Email de l'utilisateur (ex: ami@exemple.com)"
            phx-keyup="update_custom_email"
            class="input input-bordered input-sm flex-1"
          />
          <button
            type="button"
            id={@button_id}
            phx-click={@add_custom_event}
            phx-value-email={@custom_email}
            class="btn btn-secondary btn-sm gap-1"
          >
            <.icon name="hero-plus" class="size-4" />
            <span>{@button_label}</span>
          </button>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Formate un montant monétaire avec 2 décimales.
  """
  def format_amount(%Decimal{} = decimal) do
    :erlang.float_to_binary(Decimal.to_float(decimal), decimals: 2)
  end

  def format_amount(num) when is_number(num) do
    :erlang.float_to_binary(num / 1.0, decimals: 2)
  end

  def format_amount(_), do: "0.00"

  @doc """
  Composant d'affichage d'un élément de dépense dans une liste.
  Permet d'afficher l'action de suppression si autorisé (IF-81).
  """
  attr :expense, :map, required: true
  attr :can_delete, :boolean, default: false
  attr :delete_event, :string, default: "delete_expense"
  attr :can_edit, :boolean, default: false
  attr :edit_link, :string, default: nil

  def expense_item(assigns) do
    payer_name = (assigns.expense.payer && assigns.expense.payer.name) || "Inconnu"
    assigns = assign(assigns, :payer_name, payer_name)

    ~H"""
    <div id={"expense-item-#{@expense.id}"} class="py-3 flex items-center justify-between gap-4">
      <div class="flex items-center gap-3 min-w-0">
        <.member_avatar name={@payer_name} size="size-10" />
        <div class="min-w-0">
          <div class="font-semibold text-sm text-base-content flex items-center gap-2 truncate">
            <span>{@expense.title}</span>
          </div>
          <div class="text-xs text-base-content/60 flex flex-wrap items-center gap-1.5 mt-0.5">
            <span>Payé par <strong class="text-base-content/80">{@payer_name}</strong></span>
            <span>•</span>
            <span>{Calendar.strftime(@expense.date, "%d/%m/%Y")}</span>
            <span :if={@expense.description} class="italic">• {@expense.description}</span>
          </div>
        </div>
      </div>

      <div class="flex items-center gap-3 shrink-0">
        <span class="text-base font-bold text-primary">
          {format_amount(@expense.amount)} {@expense.currency}
        </span>

        <%= if @can_edit and @edit_link do %>
          <.link
            navigate={@edit_link}
            id={"edit-expense-btn-#{@expense.id}"}
            class="btn btn-ghost btn-circle btn-xs text-primary hover:bg-primary/10"
            title="Modifier cette dépense"
          >
            <.icon name="hero-pencil" class="size-4" />
          </.link>
        <% end %>

        <%= if @can_delete do %>
          <button
            type="button"
            id={"delete-expense-btn-#{@expense.id}"}
            phx-click={@delete_event}
            phx-value-id={@expense.id}
            data-confirm={"Êtes-vous sûr de vouloir supprimer définitivement la dépense « #{@expense.title} » de #{format_amount(@expense.amount)} #{@expense.currency} ?"}
            class="btn btn-ghost btn-circle btn-xs text-error hover:bg-error/10"
            title="Supprimer cette dépense"
          >
            <.icon name="hero-trash" class="size-4" />
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  @doc """
  Composant d'affichage d'un compte créditeur à rembourser.
  Affiche le nom, le badge, le montant net à recevoir mis en valeur, et le détail du calcul.
  """
  attr :creditor, :map, required: true
  attr :currency, :string, default: "EUR"

  def creditor_item(assigns) do
    member = assigns.creditor.member
    is_owner = member && member.role == "owner"
    role = (member && member.role) || "member"

    assigns =
      assigns
      |> assign(:is_owner, is_owner)
      |> assign(:role, role)

    ~H"""
    <div
      id={"creditor-item-#{@creditor.member_id}"}
      class="py-3 flex items-center justify-between gap-4"
    >
      <div class="flex items-center gap-3 min-w-0">
        <.member_avatar name={@creditor.name} is_owner={@is_owner} size="size-10" />
        <div class="min-w-0">
          <div class="font-semibold text-sm text-base-content flex items-center gap-2 truncate">
            <span>{@creditor.name}</span>
            <.member_badge role={@role} is_owner={@is_owner} />
          </div>
          <div class="text-xs text-base-content/60 flex flex-wrap items-center gap-1.5 mt-0.5">
            <span :if={@creditor.email}>{@creditor.email} •</span>
            <span>A payé {format_amount(@creditor.total_paid)} {@currency}</span>
            <span>•</span>
            <span>Part due : {format_amount(@creditor.fair_share)} {@currency}</span>
          </div>
        </div>
      </div>

      <div class="text-right shrink-0">
        <div class="inline-flex items-center gap-1 px-2.5 py-1 rounded-lg bg-success/10 text-success border border-success/20">
          <.icon name="hero-arrow-down-left" class="size-3.5" />
          <span class="text-sm font-bold">
            + {format_amount(@creditor.amount_to_receive)} {@currency}
          </span>
        </div>
        <div class="text-xs text-base-content/50 mt-0.5">À recevoir</div>
      </div>
    </div>
    """
  end

  @doc """
  Composant d'affichage d'un compte débiteur qui doit donner de l'argent.
  Affiche le nom, le badge, le montant net à payer mis en valeur, et le détail du calcul.
  """
  attr :debtor, :map, required: true
  attr :currency, :string, default: "EUR"

  def debtor_item(assigns) do
    member = assigns.debtor.member
    is_owner = member && member.role == "owner"
    role = (member && member.role) || "member"

    assigns =
      assigns
      |> assign(:is_owner, is_owner)
      |> assign(:role, role)

    ~H"""
    <div
      id={"debtor-item-#{@debtor.member_id}"}
      class="py-3 flex items-center justify-between gap-4"
    >
      <div class="flex items-center gap-3 min-w-0">
        <.member_avatar name={@debtor.name} is_owner={@is_owner} size="size-10" />
        <div class="min-w-0">
          <div class="font-semibold text-sm text-base-content flex items-center gap-2 truncate">
            <span>{@debtor.name}</span>
            <.member_badge role={@role} is_owner={@is_owner} />
          </div>
          <div class="text-xs text-base-content/60 flex flex-wrap items-center gap-1.5 mt-0.5">
            <span :if={@debtor.email}>{@debtor.email} •</span>
            <span>A payé {format_amount(@debtor.total_paid)} {@currency}</span>
            <span>•</span>
            <span>Part due : {format_amount(@debtor.fair_share)} {@currency}</span>
          </div>
        </div>
      </div>

      <div class="text-right shrink-0">
        <div class="inline-flex items-center gap-1 px-2.5 py-1 rounded-lg bg-error/10 text-error border border-error/20">
          <.icon name="hero-arrow-up-right" class="size-3.5" />
          <span class="text-sm font-bold">
            - {format_amount(@debtor.amount_to_pay)} {@currency}
          </span>
        </div>
        <div class="text-xs text-base-content/50 mt-0.5">À régler</div>
      </div>
    </div>
    """
  end

  @doc """
  Composant d'affichage d'un virement proposé entre comptes (IF-84, IF-85).
  Affiche le compte émetteur (débiteur), le flux vers le compte récepteur (créditeur),
  le montant net optimisé à transférer, et le bouton/badge de règlement.
  """
  attr :settlement, :map, required: true
  attr :currency, :string, default: "EUR"
  attr :is_mock_settled, :boolean, default: false
  attr :status, :string, default: "open"
  attr :is_closed, :boolean, default: false
  attr :current_user, :any, default: nil

  def settlement_item(assigns) do
    is_debtor =
      not is_nil(assigns[:current_user]) and
        not is_nil(assigns.settlement[:from_user_id]) and
        assigns.current_user.id == assigns.settlement.from_user_id

    can_settle =
      (assigns.status == "pending_settlement" or assigns.is_closed) and
        not assigns.is_mock_settled and
        is_debtor

    assigns = assign(assigns, :can_settle, can_settle)

    ~H"""
    <div
      id={"settlement-item-#{@settlement.from_id}-#{@settlement.to_id}"}
      class={[
        "py-3.5 px-4 rounded-xl border transition-all duration-200 flex flex-col sm:flex-row sm:items-center justify-between gap-4",
        if(@is_mock_settled,
          do: "bg-success/5 border-success/30 opacity-80",
          else: "bg-base-100 border-base-200 hover:border-primary/30 hover:shadow-sm"
        )
      ]}
    >
      <div class="flex items-center gap-3 min-w-0">
        <%!-- Débiteur --%>
        <div class="flex items-center gap-2">
          <.member_avatar name={@settlement.from_name} size="size-8" />
          <div class="text-sm font-semibold text-base-content truncate">
            <span>{@settlement.from_name}</span>
          </div>
        </div>

        <%!-- Flèche directionnelle --%>
        <div class="flex items-center gap-1 text-primary shrink-0 px-2.5 py-1 bg-primary/10 rounded-lg text-xs font-semibold">
          <span>doit donner</span>
          <.icon name="hero-arrow-right" class="size-3.5" />
        </div>

        <%!-- Créditeur --%>
        <div class="flex items-center gap-2">
          <.member_avatar name={@settlement.to_name} size="size-8" />
          <div class="text-sm font-semibold text-base-content truncate">
            <span>{@settlement.to_name}</span>
          </div>
        </div>
      </div>

      <div class="flex items-center justify-between sm:justify-end gap-3 shrink-0">
        <div class="text-right">
          <span class="text-base font-bold text-primary">
            {format_amount(@settlement.amount)} {@currency}
          </span>
          <div class="text-xs text-base-content/50">Virement conseillé</div>
        </div>

        <%= if @is_mock_settled do %>
          <div
            id={"mock-settled-badge-#{@settlement.from_id}-#{@settlement.to_id}"}
            class="badge badge-success badge-sm gap-1 py-3 px-2.5 font-semibold shadow-sm"
          >
            <.icon name="hero-check-circle" class="size-4" />
            <span>Réglé</span>
          </div>
        <% else %>
          <%= if @can_settle do %>
            <button
              type="button"
              id={"mock-settle-btn-#{@settlement.from_id}-#{@settlement.to_id}"}
              phx-click="mock_settle"
              phx-value-from_id={@settlement.from_id}
              phx-value-to_id={@settlement.to_id}
              phx-value-from_name={@settlement.from_name}
              phx-value-to_name={@settlement.to_name}
              phx-value-amount={format_amount(@settlement.amount)}
              class="btn btn-xs btn-outline btn-success gap-1 hover:shadow-sm"
              title="Marquer ce virement comme réglé"
            >
              <.icon name="hero-check" class="size-3.5" />
              <span>Marquer comme réglé</span>
            </button>
          <% else %>
            <span class="text-xs text-base-content/50 italic">En attente du virement</span>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  @doc """
  Affiche le récapitulatif des remboursements et leur répartition entre comptes (IF-85).
  """
  attr :settlements, :list, default: []
  attr :mock_settled_ids, :any, default: MapSet.new()
  attr :currency, :string, default: "EUR"
  attr :is_closed, :boolean, default: false

  def simulated_settlements_summary(assigns) do
    settlements = assigns.settlements || []
    mock_settled_ids = assigns.mock_settled_ids || MapSet.new()
    total_count = length(settlements)

    settled_settlements =
      Enum.filter(settlements, &MapSet.member?(mock_settled_ids, "#{&1.from_id}->#{&1.to_id}"))

    settled_count = length(settled_settlements)

    total_amount =
      Enum.reduce(settlements, Decimal.new("0.00"), &Decimal.add(&2, &1.amount))

    settled_amount =
      Enum.reduce(settled_settlements, Decimal.new("0.00"), &Decimal.add(&2, &1.amount))

    remaining_amount = Decimal.sub(total_amount, settled_amount)

    progress_percent =
      if Decimal.gt?(total_amount, Decimal.new("0.00")) do
        Decimal.to_float(Decimal.div(settled_amount, total_amount)) * 100.0
      else
        0.0
      end

    all_completed = total_count > 0 and settled_count == total_count

    assigns =
      assigns
      |> assign(:total_count, total_count)
      |> assign(:settled_count, settled_count)
      |> assign(:total_amount, total_amount)
      |> assign(:settled_amount, settled_amount)
      |> assign(:remaining_amount, remaining_amount)
      |> assign(:progress_percent, progress_percent)
      |> assign(:all_completed, all_completed)

    ~H"""
    <div id="settlements-summary" class="bg-base-200/50 rounded-xl p-4 border border-base-200 space-y-3">
      <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
        <div class="space-y-0.5">
          <div class="text-xs font-semibold text-base-content/70 uppercase tracking-wider flex items-center gap-1.5">
            <.icon name="hero-chart-pie" class="size-4 text-primary" />
            <span>Répartition des remboursements</span>
          </div>
          <p class="text-xs text-base-content/60">
            Progression des virements et réconciliation des montants
          </p>
        </div>

        <div class="flex items-center gap-2">
          <span id="settlement-progress-badge" class="badge badge-primary badge-sm font-semibold">
            {@settled_count} / {@total_count} virement(s) réglé(s)
          </span>
        </div>
      </div>

      <%!-- Barre de progression --%>
      <div class="w-full bg-base-300 rounded-full h-2.5 overflow-hidden">
        <div
          id="settlement-progress-bar"
          class="bg-success h-2.5 rounded-full transition-all duration-300"
          style={"width: #{@progress_percent}%"}
        >
        </div>
      </div>

      <%!-- Répartition chiffrée --%>
      <div class="grid grid-cols-2 sm:grid-cols-3 gap-2 text-center pt-1 text-xs">
        <div class="bg-base-100 p-2 rounded-lg border border-base-200">
          <span class="text-base-content/60 block">Total à virer</span>
          <strong id="summary-total-amount" class="text-base-content font-bold text-sm">
            {format_amount(@total_amount)} {@currency}
          </strong>
        </div>

        <div class="bg-base-100 p-2 rounded-lg border border-base-200">
          <span class="text-success block">Réglé</span>
          <strong id="summary-settled-amount" class="text-success font-bold text-sm">
            {format_amount(@settled_amount)} {@currency}
          </strong>
        </div>

        <div class="bg-base-100 p-2 rounded-lg border border-base-200 col-span-2 sm:col-span-1">
          <span class="text-base-content/60 block">Restant à régler</span>
          <strong id="summary-remaining-amount" class="text-warning font-bold text-sm">
            {format_amount(@remaining_amount)} {@currency}
          </strong>
        </div>
      </div>

      <%= if @all_completed do %>
        <div
          id="all-settlements-completed-message"
          class="p-3 bg-success/15 border border-success/30 rounded-lg text-success text-xs font-medium flex items-center gap-2"
        >
          <.icon name="hero-check-circle" class="size-5 shrink-0" />
          <span>Tous les remboursements ont été effectués avec succès ! Le porte-monnaie est désormais définitivement clôturé et l'ensemble des comptes est soldé.</span>
        </div>
      <% end %>
    </div>
    """
  end
end
