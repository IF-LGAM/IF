defmodule LesBonsComptesWeb.WalletLive.Edit do
  use LesBonsComptesWeb, :live_view

  import LesBonsComptesWeb.WalletLive.WalletComponents

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
  def handle_event("update_custom_email", %{"value" => email}, socket) do
    {:noreply, assign(socket, :custom_email, email)}
  end

  @impl true
  def handle_event("add_registered_user", %{"user_id" => user_id_str}, socket) do
    user_id = String.to_integer(user_id_str)
    user = Accounts.get_user!(user_id)
    current_user = socket.assigns.current_user
    wallet = socket.assigns.wallet

    case Wallets.create_invitation(current_user, wallet, %{email: user.email}) do
      {:ok, invitation} ->
        updated_wallet = Wallets.get_wallet!(wallet.id)
        available_users = compute_available_users(updated_wallet, current_user)

        {:noreply,
         socket
         |> assign(:wallet, updated_wallet)
         |> assign(:available_users, available_users)
         |> assign(:participant_error, nil)
         |> put_flash(
           :info,
           "Invitation envoyée avec succès à #{invitation.invitee.name} (#{invitation.invitee.email})."
         )}

      {:error, reason} when is_binary(reason) ->
        {:noreply, assign(socket, :participant_error, reason)}

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
    email = params["email"] || params["custom_email"] || socket.assigns.custom_email
    current_user = socket.assigns.current_user
    wallet = socket.assigns.wallet

    case Wallets.create_invitation(current_user, wallet, %{email: email}) do
      {:ok, invitation} ->
        updated_wallet = Wallets.get_wallet!(wallet.id)
        available_users = compute_available_users(updated_wallet, current_user)

        {:noreply,
         socket
         |> assign(:wallet, updated_wallet)
         |> assign(:available_users, available_users)
         |> assign(:custom_email, "")
         |> assign(:participant_error, nil)
         |> put_flash(
           :info,
           "Invitation envoyée avec succès à #{invitation.invitee.name} (#{invitation.invitee.email})."
         )}

      {:error, reason} when is_binary(reason) ->
        {:noreply, assign(socket, :participant_error, reason)}

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
  def handle_event("cancel_invitation", %{"id" => id_str}, socket) do
    invitation_id = String.to_integer(id_str)
    current_user = socket.assigns.current_user
    wallet = socket.assigns.wallet

    case Wallets.cancel_invitation(current_user, invitation_id) do
      {:ok, _invitation} ->
        updated_wallet = Wallets.get_wallet!(wallet.id)
        available_users = compute_available_users(updated_wallet, current_user)

        {:noreply,
         socket
         |> assign(:wallet, updated_wallet)
         |> assign(:available_users, available_users)
         |> put_flash(:info, "L'invitation a été annulée avec succès.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Impossible d'annuler cette invitation.")}
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

    pending_invitee_ids =
      wallet.invitations
      |> Enum.map(& &1.invitee_id)
      |> Enum.reject(&is_nil/1)

    excluded_ids = [current_user.id | existing_user_ids ++ pending_invitee_ids]

    Accounts.list_users()
    |> Enum.reject(fn u -> u.id in excluded_ids end)
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

              <.wallet_fields form={@form} />

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

        <%!-- Gestion des Membres / Participants & Invitations (IF-38, IF-39, IF-43) --%>
        <div class="card bg-base-100 shadow-xl border border-base-200">
          <div class="card-body p-6 sm:p-8 space-y-5">
            <div class="flex items-center justify-between">
              <div>
                <h2 class="text-lg font-bold text-base-content flex items-center gap-2">
                  <.icon name="hero-user-group" class="size-5 text-primary" />
                  <span>2. Participants et invitations ({length(@wallet.members)})</span>
                </h2>
                <p class="text-xs text-base-content/60 mt-0.5">
                  Consultez les membres actifs et invitez de nouveaux participants.
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

            <%!-- Liste des membres confirmés --%>
            <div class="space-y-2">
              <label class="text-xs font-semibold text-base-content/70 uppercase tracking-wider">
                Membres actifs ({length(@wallet.members)})
              </label>

              <div id="edit-members-list" class="space-y-2">
                <%= for member <- @wallet.members do %>
                  <div
                    id={"edit-member-item-#{member.id}"}
                    class="flex items-center justify-between p-3 rounded-xl bg-base-200/50 border border-base-200"
                  >
                    <div class="flex items-center gap-3">
                      <.member_avatar name={member.name} is_owner={member.role == "owner"} />
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
            </div>

            <%!-- Liste des invitations envoyées (IF-43) --%>
            <div :if={@wallet.invitations != []} class="space-y-2 pt-2">
              <label class="text-xs font-semibold text-base-content/70 uppercase tracking-wider flex items-center gap-1.5">
                <.icon name="hero-envelope" class="size-4 text-primary" />
                <span>Invitations envoyées ({length(@wallet.invitations)})</span>
              </label>

              <div id="pending-invitations-list" class="space-y-2">
                <%= for invitation <- @wallet.invitations do %>
                  <div
                    id={"pending-invitation-#{invitation.id}"}
                    class={[
                      "flex items-center justify-between p-3 rounded-xl border transition-colors",
                      if(invitation.status == "declined",
                        do: "bg-error/5 border-error/20",
                        else: "bg-warning/5 border-warning/20"
                      )
                    ]}
                  >
                    <div class="flex items-center gap-3">
                      <.member_avatar name={invitation.invitee.name} is_owner={false} />
                      <div>
                        <div class="font-semibold text-sm text-base-content flex items-center gap-2">
                          <span>{invitation.invitee.name}</span>
                          <.invitation_badge status={invitation.status} />
                        </div>
                        <div class="text-xs text-base-content/60">
                          {invitation.email}
                        </div>
                      </div>
                    </div>

                    <button
                      type="button"
                      id={"cancel-invitation-btn-#{invitation.id}"}
                      phx-click="cancel_invitation"
                      phx-value-id={invitation.id}
                      data-confirm={
                        if(invitation.status == "declined",
                          do: "Retirer cette invitation refusée ?",
                          else:
                            "Êtes-vous sûr de vouloir annuler l'invitation envoyée à #{invitation.invitee.name} ?"
                        )
                      }
                      class="btn btn-ghost btn-xs text-error hover:bg-error/10 gap-1"
                      title={
                        if(invitation.status == "declined",
                          do: "Retirer",
                          else: "Annuler l'invitation"
                        )
                      }
                    >
                      <.icon name="hero-trash" class="size-3.5" />
                      <span>{if(invitation.status == "declined", do: "Retirer", else: "Annuler")}</span>
                    </button>
                  </div>
                <% end %>
              </div>
            </div>

            <div class="divider my-2 text-xs text-base-content/50">
              Inviter un nouveau participant
            </div>

            <.participant_selector
              available_users={@available_users}
              custom_email={@custom_email}
              button_label="Envoyer l'invitation"
            />
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
