defmodule LesBonsComptesWeb.WalletLive.Edit do
  use LesBonsComptesWeb, :live_view

  alias LesBonsComptes.Accounts
  alias LesBonsComptes.Wallets

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    wallet = Wallets.get_wallet!(id)
    current_user = socket.assigns.current_user

    if Wallets.owner?(wallet, current_user) do
      changeset = Wallets.change_wallet(wallet)
      available_users = compute_available_users(wallet, current_user)

      {:ok,
       socket
       |> assign(:page_title, "Modifier #{wallet.name} - Les Bons Comptes")
       |> assign(:wallet, wallet)
       |> assign(:form, to_form(changeset))
       |> assign(:available_users, available_users)
       |> assign(:custom_name, "")
       |> assign(:custom_email, "")
       |> assign(:participant_error, nil)}
    else
      {:ok,
       socket
       |> put_flash(:error, "Seul le propriétaire peut modifier ce porte-monnaie.")
       |> push_navigate(to: ~p"/wallets/#{wallet.id}")}
    end
  end

  @impl true
  def handle_event("validate", %{"wallet" => wallet_params}, socket) do
    changeset =
      socket.assigns.wallet
      |> Wallets.change_wallet(wallet_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"wallet" => wallet_params}, socket) do
    current_user = socket.assigns.current_user
    wallet = socket.assigns.wallet

    case Wallets.update_wallet(current_user, wallet, wallet_params) do
      {:ok, updated_wallet} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Le porte-monnaie « #{updated_wallet.name} » a été modifié avec succès."
         )
         |> push_navigate(to: ~p"/wallets/#{updated_wallet.id}")}

      {:error, :unauthorized} ->
        {:noreply,
         socket
         |> put_flash(:error, "Seul le propriétaire peut modifier ce porte-monnaie.")
         |> push_navigate(to: ~p"/wallets/#{wallet.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
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
  def handle_event("add_registered_user", %{"user_id" => user_id_str}, socket) do
    user_id = String.to_integer(user_id_str)
    user = Accounts.get_user!(user_id)
    current_user = socket.assigns.current_user
    wallet = socket.assigns.wallet

    case Wallets.add_member(current_user, wallet, %{
           user_id: user.id,
           name: user.name,
           email: user.email,
           role: "member"
         }) do
      {:ok, _member} ->
        updated_wallet = Wallets.get_wallet!(wallet.id)
        available_users = compute_available_users(updated_wallet, current_user)

        {:noreply,
         socket
         |> assign(:wallet, updated_wallet)
         |> assign(:available_users, available_users)
         |> assign(:participant_error, nil)
         |> put_flash(:info, "#{user.name} a été ajouté au porte-monnaie.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        error_msg =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
          |> Enum.map_join(", ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)

        {:noreply, assign(socket, :participant_error, error_msg)}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Action non autorisée.")}
    end
  end

  @impl true
  def handle_event("add_custom_participant", params, socket) do
    email =
      String.trim(params["email"] || params["custom_email"] || socket.assigns.custom_email || "")

    current_user = socket.assigns.current_user
    wallet = socket.assigns.wallet

    cond do
      email == "" ->
        {:noreply, assign(socket, :participant_error, "L'adresse email est obligatoire.")}

      not (email =~ ~r/^[^\s]+@[^\s]+\.[^\s]+$/) ->
        {:noreply,
         assign(socket, :participant_error, "Veuillez saisir une adresse email valide.")}

      email == current_user.email ->
        {:noreply,
         assign(socket, :participant_error, "Vous êtes déjà le propriétaire de ce porte-monnaie.")}

      Enum.any?(wallet.members, fn m ->
        String.downcase(m.email || "") == String.downcase(email)
      end) ->
        {:noreply,
         assign(socket, :participant_error, "Cet utilisateur fait déjà partie des participants.")}

      user = Accounts.get_user_by_email(email) ->
        case Wallets.add_member(current_user, wallet, %{
               user_id: user.id,
               name: user.name,
               email: user.email,
               role: "member"
             }) do
          {:ok, _member} ->
            updated_wallet = Wallets.get_wallet!(wallet.id)
            available_users = compute_available_users(updated_wallet, current_user)

            {:noreply,
             socket
             |> assign(:wallet, updated_wallet)
             |> assign(:available_users, available_users)
             |> assign(:custom_name, "")
             |> assign(:custom_email, "")
             |> assign(:participant_error, nil)
             |> put_flash(:info, "#{user.name} a été ajouté au porte-monnaie.")}

          {:error, %Ecto.Changeset{} = changeset} ->
            error_msg =
              Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
              |> Enum.map_join(", ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)

            {:noreply, assign(socket, :participant_error, error_msg)}

          {:error, :unauthorized} ->
            {:noreply, put_flash(socket, :error, "Action non autorisée.")}
        end

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
  def handle_event("remove_member", %{"id" => member_id_str}, socket) do
    member_id = String.to_integer(member_id_str)
    current_user = socket.assigns.current_user
    wallet = socket.assigns.wallet

    case Wallets.remove_member(current_user, wallet, member_id) do
      {:ok, removed_member} ->
        updated_wallet = Wallets.get_wallet!(wallet.id)
        available_users = compute_available_users(updated_wallet, current_user)

        {:noreply,
         socket
         |> assign(:wallet, updated_wallet)
         |> assign(:available_users, available_users)
         |> assign(:participant_error, nil)
         |> put_flash(:info, "#{removed_member.name} a été retiré du porte-monnaie.")}

      {:error, :cannot_remove_owner} ->
        {:noreply,
         assign(
           socket,
           :participant_error,
           "Le propriétaire ne peut pas être retiré du porte-monnaie."
         )}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Action non autorisée.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Impossible de retirer ce participant.")}
    end
  end

  @impl true
  def handle_event("delete", _params, socket) do
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

  defp compute_available_users(wallet, current_user) do
    existing_user_ids =
      wallet.members
      |> Enum.map(& &1.user_id)
      |> Enum.reject(&is_nil/1)

    Accounts.list_users()
    |> Enum.reject(fn u -> u.id == current_user.id or u.id in existing_user_ids end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="max-w-3xl mx-auto space-y-6">
        <%!-- Fil d'Ariane & Retour --%>
        <div class="flex items-center justify-between">
          <.link
            navigate={~p"/wallets/#{@wallet.id}"}
            class="btn btn-ghost btn-sm gap-2 text-base-content/70"
          >
            <.icon name="hero-arrow-left" class="size-4" />
            <span>Retour au porte-monnaie</span>
          </.link>
        </div>

        <%!-- En-tête --%>
        <div class="space-y-1">
          <h1 class="text-3xl font-extrabold tracking-tight text-base-content">
            Modifier le porte-monnaie
          </h1>
          <p class="text-sm text-base-content/70">
            Modifiez les informations générales et gérez les participants du groupe.
          </p>
        </div>

        <%!-- Formulaire de modification générale --%>
        <.form
          for={@form}
          id="wallet-edit-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-6"
        >
          <div class="card bg-base-100 shadow-xl border border-base-200">
            <div class="card-body p-6 sm:p-8 space-y-4">
              <h2 class="text-lg font-bold text-base-content flex items-center gap-2">
                <.icon name="hero-information-circle" class="size-5 text-primary" />
                <span>1. Informations générales</span>
              </h2>

              <.input
                field={@form[:name]}
                id="wallet-name-input"
                type="text"
                label="Nom du porte-monnaie"
                placeholder="Ex : Vacances à Barcelone"
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
                  label="Description"
                  placeholder="Détails ou informations utiles"
                />
              </div>

              <div class="flex justify-end pt-2">
                <button
                  type="submit"
                  id="submit-edit-wallet-btn"
                  phx-disable-with="Enregistrement..."
                  class="btn btn-primary btn-sm px-6 gap-1.5 shadow-sm"
                >
                  <.icon name="hero-check" class="size-4" />
                  <span>Enregistrer les modifications</span>
                </button>
              </div>
            </div>
          </div>
        </.form>

        <%!-- Gestion des Membres / Participants --%>
        <div class="card bg-base-100 shadow-xl border border-base-200">
          <div class="card-body p-6 sm:p-8 space-y-5">
            <div class="flex items-center justify-between">
              <div>
                <h2 class="text-lg font-bold text-base-content flex items-center gap-2">
                  <.icon name="hero-user-group" class="size-5 text-primary" />
                  <span>2. Gestion des participants ({length(@wallet.members)})</span>
                </h2>
                <p class="text-xs text-base-content/60 mt-0.5">
                  Ajoutez ou retirez des membres du porte-monnaie.
                </p>
              </div>
            </div>

            <%!-- Alerte erreur si applicable --%>
            <div
              :if={@participant_error}
              id="edit-participant-error-alert"
              class="alert alert-error text-sm py-2 shadow-sm"
            >
              <.icon name="hero-exclamation-triangle" class="size-4 shrink-0" />
              <span>{@participant_error}</span>
            </div>

            <%!-- Liste des membres existants --%>
            <div id="edit-members-list" class="space-y-2">
              <%= for member <- @wallet.members do %>
                <div
                  id={"edit-member-item-#{member.id}"}
                  class="flex items-center justify-between p-3 rounded-xl bg-base-200/50 border border-base-200"
                >
                  <div class="flex items-center gap-3">
                    <div class={[
                      "size-9 rounded-full flex items-center justify-center font-bold text-sm shadow-sm",
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

                  <%= if member.role != "owner" do %>
                    <button
                      type="button"
                      id={"remove-member-btn-#{member.id}"}
                      phx-click="remove_member"
                      phx-value-id={member.id}
                      data-confirm={"Êtes-vous sûr de vouloir retirer #{member.name} du porte-monnaie ?"}
                      class="btn btn-ghost btn-circle btn-sm text-error hover:bg-error/10"
                      title="Retirer ce membre"
                    >
                      <.icon name="hero-trash" class="size-4" />
                    </button>
                  <% else %>
                    <span class="text-xs text-base-content/40 italic px-2">Non retirable</span>
                  <% end %>
                </div>
              <% end %>
            </div>

            <div class="divider my-2 text-xs text-base-content/50">Ajouter un participant</div>

            <%!-- Ajouter un utilisateur inscrit --%>
            <div :if={@available_users != []} class="space-y-2">
              <label class="text-xs font-semibold text-base-content/70">
                Ajouter un utilisateur inscrit :
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

            <%!-- Ajouter un participant inscrit par email --%>
            <div class="bg-base-200/40 rounded-xl p-4 border border-base-200 space-y-3">
              <label class="text-xs font-semibold text-base-content/80 flex items-center gap-1.5">
                <.icon name="hero-envelope" class="size-4 text-base-content/60" />
                <span>Ajouter un participant inscrit par son adresse email :</span>
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
                  <span>Ajouter au porte-monnaie</span>
                </button>
              </div>
            </div>
          </div>
        </div>

        <%!-- Zone Danger : Suppression du porte-monnaie --%>
        <div class="card bg-base-100 shadow border border-error/30">
          <div class="card-body p-6 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
            <div>
              <h3 class="font-bold text-error flex items-center gap-1.5">
                <.icon name="hero-exclamation-triangle" class="size-5" />
                <span>Zone de danger</span>
              </h3>
              <p class="text-xs text-base-content/70 mt-1">
                Supprimer définitivement ce porte-monnaie et l'ensemble de ses données pour tous les membres.
              </p>
            </div>

            <button
              type="button"
              id="delete-wallet-btn"
              phx-click="delete"
              data-confirm="Êtes-vous sûr de vouloir supprimer définitivement ce porte-monnaie ? Toutes les données associées seront supprimées."
              class="btn btn-error btn-outline btn-sm gap-1.5 whitespace-nowrap"
            >
              <.icon name="hero-trash" class="size-4" />
              <span>Supprimer le porte-monnaie</span>
            </button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
