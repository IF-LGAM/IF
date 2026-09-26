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

  def expense_item(assigns) do
    ~H"""
    <div id={"expense-item-#{@expense.id}"} class="py-3 flex items-center justify-between gap-4">
      <div class="flex items-center gap-3 min-w-0">
        <.member_avatar name={@expense.payer.name} size="size-10" />
        <div class="min-w-0">
          <div class="font-semibold text-sm text-base-content flex items-center gap-2 truncate">
            <span>{@expense.title}</span>
          </div>
          <div class="text-xs text-base-content/60 flex flex-wrap items-center gap-1.5 mt-0.5">
            <span>Payé par <strong class="text-base-content/80">{@expense.payer.name}</strong></span>
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
end
