defmodule LesBonsComptesWeb.WalletLive.New do
  use LesBonsComptesWeb, :live_view

  import LesBonsComptesWeb.WalletLive.WalletComponents

  alias LesBonsComptes.Accounts
  alias LesBonsComptes.Wallets
  alias LesBonsComptes.Wallets.Wallet

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user
    wallet = %Wallet{currency: "EUR"}
    changeset = Wallets.change_wallet(wallet)

    all_users = Accounts.list_users()
    available_users = Enum.reject(all_users, &(&1.id == current_user.id))

    {:ok,
     socket
     |> assign(:page_title, "Nouveau porte-monnaie - Les Bons Comptes")
     |> assign(:form, to_form(changeset))
     |> assign(:participants, [])
     |> assign(:available_users, available_users)
     |> assign(:custom_email, "")
     |> assign(:participant_error, nil)}
  end

  @impl true
  def handle_event("validate", %{"wallet" => wallet_params} = params, socket) do
    changeset =
      %Wallet{creator_id: socket.assigns.current_user.id}
      |> Wallets.change_wallet(wallet_params)
      |> Map.put(:action, :validate)

    custom_email = Map.get(params, "custom_email", socket.assigns.custom_email)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset))
     |> assign(:custom_email, custom_email)}
  end

  def handle_event("validate", params, socket) do
    custom_email = Map.get(params, "custom_email", socket.assigns.custom_email)
    {:noreply, assign(socket, :custom_email, custom_email)}
  end

  @impl true
  def handle_event("add_registered_user", %{"user_id" => user_id_str}, socket) do
    user_id = String.to_integer(user_id_str)
    user = Accounts.get_user!(user_id)

    already_added =
      Enum.any?(socket.assigns.participants, fn p -> p[:user_id] == user.id end)

    if already_added do
      {:noreply,
       assign(socket, :participant_error, "#{user.name} est déjà dans la liste des participants.")}
    else
      new_participant = %{
        id: System.unique_integer([:positive]),
        user_id: user.id,
        name: user.name,
        email: user.email,
        type: :registered
      }

      {:noreply,
       socket
       |> assign(:participants, socket.assigns.participants ++ [new_participant])
       |> assign(
         :available_users,
         Enum.reject(socket.assigns.available_users, &(&1.id == user.id))
       )
       |> assign(:participant_error, nil)}
    end
  end

  @impl true
  def handle_event("update_custom_email", %{"value" => email}, socket) do
    {:noreply, assign(socket, :custom_email, email)}
  end

  @impl true
  def handle_event("add_custom_participant", params, socket) do
    email = params["email"] || params["custom_email"] || socket.assigns.custom_email

    case Wallets.validate_new_participant(
           socket.assigns.participants,
           socket.assigns.current_user,
           email
         ) do
      {:ok, user} ->
        new_participant = %{
          id: System.unique_integer([:positive]),
          user_id: user.id,
          name: user.name,
          email: user.email,
          type: :registered
        }

        {:noreply,
         socket
         |> assign(:participants, socket.assigns.participants ++ [new_participant])
         |> assign(
           :available_users,
           Enum.reject(socket.assigns.available_users, &(&1.id == user.id))
         )
         |> assign(:custom_email, "")
         |> assign(:participant_error, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :participant_error, reason)}
    end
  end

  @impl true
  def handle_event("remove_participant", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)
    removed = Enum.find(socket.assigns.participants, &(&1.id == id))
    updated_participants = Enum.reject(socket.assigns.participants, &(&1.id == id))

    updated_available =
      if removed && removed[:user_id] do
        if user = Accounts.get_user(removed.user_id) do
          [user | socket.assigns.available_users] |> Enum.uniq_by(& &1.id)
        else
          socket.assigns.available_users
        end
      else
        socket.assigns.available_users
      end

    {:noreply,
     socket
     |> assign(:participants, updated_participants)
     |> assign(:available_users, updated_available)
     |> assign(:participant_error, nil)}
  end

  @impl true
  def handle_event("save", %{"wallet" => wallet_params}, socket) do
    current_user = socket.assigns.current_user

    # Création du porte-monnaie avec le créateur comme propriétaire
    # Les autres participants recevront une invitation à accepter (IF-37, IF-42)
    case Wallets.create_wallet(current_user, wallet_params, []) do
      {:ok, wallet} ->
        # Envoi des invitations par email aux participants choisis (IF-40, IF-42)
        Enum.each(socket.assigns.participants, fn p ->
          _ = Wallets.create_invitation(current_user, wallet, %{email: p.email})
        end)

        flash_msg =
          if socket.assigns.participants != [] do
            "Le porte-monnaie « #{wallet.name} » a été créé avec succès ! Les invitations ont été envoyées."
          else
            "Le porte-monnaie « #{wallet.name} » a été créé avec succès !"
          end

        {:noreply,
         socket
         |> put_flash(:info, flash_msg)
         |> push_navigate(to: ~p"/wallets/#{wallet.id}")}

      {:error, :wallet, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(%{changeset | action: :validate}))}

      {:error, _step, reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Une erreur est survenue lors de la création : #{inspect(reason)}"
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="max-w-3xl mx-auto space-y-6">
        <%!-- Fil d'Ariane & Retour --%>
        <div class="flex items-center justify-between">
          <.link navigate={~p"/wallets"} class="btn btn-ghost btn-sm gap-2 text-base-content/70">
            <.icon name="hero-arrow-left" class="size-4" />
            <span>Tous les porte-monnaies</span>
          </.link>
        </div>

        <%!-- En-tête --%>
        <div class="text-center sm:text-left space-y-2">
          <div class="inline-flex items-center justify-center size-12 rounded-xl bg-primary/10 text-primary mb-1 shadow-sm">
            <.icon name="hero-wallet" class="size-6" />
          </div>
          <h1 class="text-3xl font-extrabold tracking-tight text-base-content">
            Créer un porte-monnaie commun
          </h1>
          <p class="text-sm text-base-content/70">
            Configurez votre groupe, choisissez la devise et invitez vos amis pour commencer à partager les frais.
          </p>
        </div>

        <%!-- Formulaire de création (IF-33, IF-35) --%>
        <.form
          for={@form}
          id="wallet-create-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-6"
        >
          <%!-- Carte Détails du porte-monnaie --%>
          <div class="card bg-base-100 shadow-xl border border-base-200">
            <div class="card-body p-6 sm:p-8 space-y-4">
              <h2 class="text-lg font-bold text-base-content flex items-center gap-2">
                <.icon name="hero-information-circle" class="size-5 text-primary" />
                <span>1. Informations générales</span>
              </h2>

              <.wallet_fields form={@form} />
            </div>
          </div>

          <%!-- Carte Sélection des participants à inviter (IF-29, IF-30, IF-36, IF-38, IF-39) --%>
          <div class="card bg-base-100 shadow-xl border border-base-200">
            <div class="card-body p-6 sm:p-8 space-y-5">
              <div class="flex items-center justify-between">
                <div>
                  <h2 class="text-lg font-bold text-base-content flex items-center gap-2">
                    <.icon name="hero-envelope" class="size-5 text-primary" />
                    <span>2. Inviter des participants</span>
                  </h2>
                  <p class="text-xs text-base-content/60 mt-0.5">
                    Les personnes sélectionnées recevront une invitation par email pour accepter de rejoindre le groupe.
                  </p>
                </div>
                <span
                  id="participants-count-badge"
                  class="badge badge-primary badge-outline font-semibold whitespace-nowrap shrink-0 px-3 py-1.5 h-auto text-xs"
                >
                  {1 + length(@participants)} personne(s)
                </span>
              </div>

              <%!-- Message d'erreur participant si applicable (IF-35) --%>
              <div
                :if={@participant_error}
                id="participant-error-alert"
                class="alert alert-error text-sm py-2 shadow-sm"
              >
                <.icon name="hero-exclamation-triangle" class="size-4 shrink-0" />
                <span>{@participant_error}</span>
              </div>

              <%!-- Liste actuelle des participants --%>
              <div class="space-y-2">
                <label class="text-xs font-semibold text-base-content/70 uppercase tracking-wider">
                  Membres et personnes à inviter
                </label>

                <%!-- Propriétaire (Créateur) verrouillé (IF-36) --%>
                <div
                  id={"member-owner-#{@current_user.id}"}
                  class="flex items-center justify-between p-3 rounded-xl bg-primary/10 border border-primary/20"
                >
                  <div class="flex items-center gap-3">
                    <.member_avatar name={@current_user.name} is_owner={true} />
                    <div>
                      <div class="font-semibold text-sm text-base-content flex items-center gap-2">
                        <span>{@current_user.name}</span>
                        <span class="badge badge-sm badge-primary gap-1">
                          <.icon name="hero-shield-check" class="size-3" />
                          <span>Organisateur (Toi)</span>
                        </span>
                      </div>
                      <div class="text-xs text-base-content/60">{@current_user.email}</div>
                    </div>
                  </div>
                  <span class="text-xs font-medium text-primary">Propriétaire</span>
                </div>

                <%!-- Participants en attente d'envoi d'invitation (IF-29, IF-38) --%>
                <div id="participants-list" class="space-y-2">
                  <%= for participant <- @participants do %>
                    <div
                      id={"participant-row-#{participant.id}"}
                      class="flex items-center justify-between p-3 rounded-xl bg-base-200/50 border border-base-200 hover:bg-base-200 transition-colors"
                    >
                      <div class="flex items-center gap-3">
                        <.member_avatar name={participant.name} is_owner={false} />
                        <div>
                          <div class="font-semibold text-sm text-base-content flex items-center gap-2">
                            <span>{participant.name}</span>
                            <.member_badge is_owner={false} />
                            <span class="badge badge-warning badge-xs gap-1">
                              <.icon name="hero-envelope" class="size-2.5" />
                              <span>Invitation à envoyer</span>
                            </span>
                          </div>
                          <%= if participant.email do %>
                            <div class="text-xs text-base-content/60">{participant.email}</div>
                          <% end %>
                        </div>
                      </div>

                      <button
                        type="button"
                        id={"remove-participant-btn-#{participant.id}"}
                        phx-click="remove_participant"
                        phx-value-id={participant.id}
                        class="btn btn-ghost btn-circle btn-sm text-error hover:bg-error/10"
                        title="Retirer ce participant"
                      >
                        <.icon name="hero-trash" class="size-4" />
                      </button>
                    </div>
                  <% end %>
                </div>
              </div>

              <div class="divider my-2 text-xs text-base-content/50">
                Sélectionner des personnes à inviter
              </div>

              <.participant_selector
                available_users={@available_users}
                custom_email={@custom_email}
                button_label="Ajouter aux invités"
              />
            </div>
          </div>

          <%!-- Actions de soumission (IF-33, IF-34) --%>
          <div class="flex items-center justify-end gap-3 pt-2">
            <.link navigate={~p"/wallets"} class="btn btn-ghost">
              Annuler
            </.link>

            <button
              type="submit"
              id="submit-wallet-btn"
              phx-disable-with="Création du porte-monnaie..."
              class="btn btn-primary px-8 gap-2 shadow-md hover:shadow-lg transition-all"
            >
              <.icon name="hero-check" class="size-5" />
              <span>Créer le porte-monnaie</span>
            </button>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end
