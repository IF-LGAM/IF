defmodule LesBonsComptesWeb.WalletLive.New do
  use LesBonsComptesWeb, :live_view

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
     |> assign(:custom_name, "")
     |> assign(:custom_email, "")
     |> assign(:participant_error, nil)}
  end

  @impl true
  def handle_event("validate", %{"wallet" => wallet_params} = params, socket) do
    changeset =
      %Wallet{creator_id: socket.assigns.current_user.id}
      |> Wallets.change_wallet(wallet_params)
      |> Map.put(:action, :validate)

    custom_name = Map.get(params, "custom_name", socket.assigns.custom_name)
    custom_email = Map.get(params, "custom_email", socket.assigns.custom_email)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset))
     |> assign(:custom_name, custom_name)
     |> assign(:custom_email, custom_email)}
  end

  def handle_event("validate", params, socket) do
    custom_name = Map.get(params, "custom_name", socket.assigns.custom_name)
    custom_email = Map.get(params, "custom_email", socket.assigns.custom_email)

    {:noreply,
     socket
     |> assign(:custom_name, custom_name)
     |> assign(:custom_email, custom_email)}
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

      updated_participants = socket.assigns.participants ++ [new_participant]
      updated_available = Enum.reject(socket.assigns.available_users, &(&1.id == user.id))

      {:noreply,
       socket
       |> assign(:participants, updated_participants)
       |> assign(:available_users, updated_available)
       |> assign(:participant_error, nil)}
    end
  end

  @impl true
  def handle_event("update_custom_name", %{"value" => name}, socket) do
    {:noreply, assign(socket, :custom_name, name)}
  end

  @impl true
  def handle_event("update_custom_email", %{"value" => email}, socket) do
    {:noreply, assign(socket, :custom_email, email)}
  end

  @impl true
  def handle_event("update_custom_inputs", params, socket) do
    name =
      params["custom_name"] || params["name"] || params["value"] || socket.assigns.custom_name

    email = params["custom_email"] || params["email"] || socket.assigns.custom_email
    {:noreply, socket |> assign(:custom_name, name) |> assign(:custom_email, email)}
  end

  @impl true
  def handle_event("add_custom_participant", params, socket) do
    email =
      String.trim(params["email"] || params["custom_email"] || socket.assigns.custom_email || "")

    current_user = socket.assigns.current_user

    cond do
      email == "" ->
        {:noreply, assign(socket, :participant_error, "L'adresse email est obligatoire.")}

      not (email =~ ~r/^[^\s]+@[^\s]+\.[^\s]+$/) ->
        {:noreply,
         assign(socket, :participant_error, "Veuillez saisir une adresse email valide.")}

      email == current_user.email ->
        {:noreply,
         assign(socket, :participant_error, "Vous êtes déjà le propriétaire de ce porte-monnaie.")}

      Enum.any?(socket.assigns.participants, fn p ->
        String.downcase(p.email || "") == String.downcase(email)
      end) ->
        {:noreply,
         assign(socket, :participant_error, "Cet utilisateur fait déjà partie des participants.")}

      user = Accounts.get_user_by_email(email) ->
        new_participant = %{
          id: System.unique_integer([:positive]),
          user_id: user.id,
          name: user.name,
          email: user.email,
          type: :registered
        }

        updated_participants = socket.assigns.participants ++ [new_participant]
        updated_available = Enum.reject(socket.assigns.available_users, &(&1.id == user.id))

        {:noreply,
         socket
         |> assign(:participants, updated_participants)
         |> assign(:available_users, updated_available)
         |> assign(:custom_email, "")
         |> assign(:participant_error, nil)}

      true ->
        {:noreply,
         assign(
           socket,
           :participant_error,
           "Aucun utilisateur inscrit avec l'email #{email}. La personne doit posséder un compte sur la plateforme."
         )}
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

    participants_payload =
      Enum.map(socket.assigns.participants, fn p ->
        %{
          name: p.name,
          email: p.email,
          user_id: p[:user_id],
          role: "member"
        }
      end)

    case Wallets.create_wallet(current_user, wallet_params, participants_payload) do
      {:ok, wallet} ->
        {:noreply,
         socket
         |> put_flash(:info, "Le porte-monnaie « #{wallet.name} » a été créé avec succès !")
         |> push_navigate(to: ~p"/wallets/#{wallet.id}")}

      {:error, :wallet, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(%{changeset | action: :validate}))}

      {:error, :member, %Ecto.Changeset{} = changeset} ->
        error_msg =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
          |> Enum.map_join(", ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)

        {:noreply,
         assign(socket, :participant_error, "Erreur dans les participants : #{error_msg}")}

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
            Configurez votre groupe, choisissez la devise et ajoutez vos amis pour commencer à partager les frais.
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
                    options={[
                      {"Euro (€)", "EUR"},
                      {"Dollar américain ($)", "USD"},
                      {"Livre sterling (£)", "GBP"},
                      {"Franc suisse (CHF)", "CHF"},
                      {"Dollar canadien ($)", "CAD"}
                    ]}
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
            </div>
          </div>

          <%!-- Carte Sélection des participants (IF-29, IF-30, IF-36) --%>
          <div class="card bg-base-100 shadow-xl border border-base-200">
            <div class="card-body p-6 sm:p-8 space-y-5">
              <div class="flex items-center justify-between">
                <div>
                  <h2 class="text-lg font-bold text-base-content flex items-center gap-2">
                    <.icon name="hero-user-group" class="size-5 text-primary" />
                    <span>2. Participants au porte-monnaie</span>
                  </h2>
                  <p class="text-xs text-base-content/60 mt-0.5">
                    Sélectionnez des utilisateurs de la plateforme ou ajoutez des amis manuellement.
                  </p>
                </div>
                <span class="badge badge-primary badge-outline font-semibold">
                  {1 + length(@participants)} participant(s)
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
                  Membres du groupe
                </label>

                <%!-- Propriétaire (Créateur) verrouillé (IF-36) --%>
                <div
                  id={"member-owner-#{@current_user.id}"}
                  class="flex items-center justify-between p-3 rounded-xl bg-primary/10 border border-primary/20"
                >
                  <div class="flex items-center gap-3">
                    <div class="size-9 rounded-full bg-primary text-primary-content flex items-center justify-center font-bold text-sm shadow-sm">
                      {String.first(@current_user.name || "U")}
                    </div>
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

                <%!-- Autres participants ajoutés (IF-29) --%>
                <div id="participants-list" class="space-y-2">
                  <%= for participant <- @participants do %>
                    <div
                      id={"participant-row-#{participant.id}"}
                      class="flex items-center justify-between p-3 rounded-xl bg-base-200/50 border border-base-200 hover:bg-base-200 transition-colors"
                    >
                      <div class="flex items-center gap-3">
                        <div class="size-9 rounded-full bg-base-300 text-base-content flex items-center justify-center font-semibold text-sm">
                          {String.first(participant.name || "?")}
                        </div>
                        <div>
                          <div class="font-semibold text-sm text-base-content flex items-center gap-2">
                            <span>{participant.name}</span>
                            <span class="badge badge-xs badge-info gap-0.5">
                              <.icon name="hero-check" class="size-2.5" /> Inscrit
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

              <div class="divider my-2 text-xs text-base-content/50">Ajouter des personnes</div>

              <%!-- Option A : Suggestions parmi les utilisateurs inscrits (IF-29) --%>
              <div :if={@available_users != []} class="space-y-2">
                <label class="text-xs font-semibold text-base-content/70">
                  Ajouter un utilisateur inscrit sur Les Bons Comptes :
                </label>
                <div class="flex flex-wrap gap-2">
                  <%= for user <- @available_users do %>
                    <button
                      type="button"
                      id={"add-user-btn-#{user.id}"}
                      phx-click="add_registered_user"
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

              <%!-- Option B : Ajouter un participant inscrit par email (IF-29) --%>
              <div class="bg-base-200/40 rounded-xl p-4 border border-base-200 space-y-3">
                <label class="text-xs font-semibold text-base-content/80 flex items-center gap-1.5">
                  <.icon name="hero-envelope" class="size-4 text-base-content/60" />
                  <span>Ou ajouter un participant inscrit par son adresse email :</span>
                </label>

                <div class="flex flex-col sm:flex-row gap-2">
                  <input
                    type="email"
                    id="custom-participant-email"
                    name="custom_email"
                    value={@custom_email}
                    placeholder="Email de l'utilisateur (ex: ami@exemple.com)"
                    phx-keyup="update_custom_email"
                    class="input input-bordered input-sm flex-1"
                  />
                  <button
                    type="button"
                    id="add-custom-participant-btn"
                    phx-click="add_custom_participant"
                    phx-value-email={@custom_email}
                    class="btn btn-secondary btn-sm gap-1"
                  >
                    <.icon name="hero-plus" class="size-4" />
                    <span>Ajouter ce participant</span>
                  </button>
                </div>
              </div>
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
