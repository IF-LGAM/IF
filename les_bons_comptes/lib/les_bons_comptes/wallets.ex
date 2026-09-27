defmodule LesBonsComptes.Wallets do
  @moduledoc """
  Contexte métier pour la gestion des porte-monnaies communs (Wallets / Tricounts).
  Gère la création du porte-monnaie, l'association des participants, l'initialisation
  des droits (propriétaire) et les validations métier associées.
  """

  import Ecto.Query, warn: false
  alias LesBonsComptes.Repo
  alias LesBonsComptes.Accounts.User
  alias LesBonsComptes.Wallets.{Invitations, Members, Wallet, WalletInvitation, WalletMember}

  # ---------------------------------------------------------------------------
  # Délégations vers Members et Invitations
  # ---------------------------------------------------------------------------

  # Membres et permissions (IF-30, IF-36, IF-38, IF-39)
  defdelegate owner?(wallet, user), to: Members
  defdelegate add_member(wallet, attrs), to: Members, as: :add
  defdelegate add_member(user, wallet, attrs), to: Members, as: :add
  defdelegate remove_member(user, wallet, member_id), to: Members, as: :remove
  defdelegate leave_wallet(user, wallet), to: Members, as: :leave
  defdelegate validate_new_participant(existing_participants, current_user, email), to: Members

  # Invitations (IF-37, IF-40, IF-41, IF-42, IF-43, IF-44, IF-45)
  defdelegate create_invitation(inviter, wallet, attrs), to: Invitations, as: :create

  defdelegate list_pending_invitations_for_user(user_id),
    to: Invitations,
    as: :list_pending_for_user

  defdelegate list_pending_invitations_for_wallet(wallet_id),
    to: Invitations,
    as: :list_pending_for_wallet

  defdelegate get_invitation!(id), to: Invitations, as: :get!
  defdelegate accept_invitation(user, invitation_or_id), to: Invitations, as: :accept
  defdelegate decline_invitation(user, invitation_or_id), to: Invitations, as: :decline
  defdelegate cancel_invitation(user, invitation_id), to: Invitations, as: :cancel

  # Données nécessaires au calcul des soldes, comptes créditeurs, débiteurs et règlements
  defdelegate get_balance_data(wallet_or_id), to: LesBonsComptes.Expenses
  defdelegate fetch_balance_data(wallet_or_id), to: LesBonsComptes.Expenses
  defdelegate calculate_balances(wallet_or_id), to: LesBonsComptes.Expenses
  defdelegate calculate_creditors(wallet_or_id), to: LesBonsComptes.Expenses
  defdelegate calculate_creditor_accounts(wallet_or_id), to: LesBonsComptes.Expenses
  defdelegate list_creditors(wallet_or_id), to: LesBonsComptes.Expenses
  defdelegate calculate_debtors(wallet_or_id), to: LesBonsComptes.Expenses
  defdelegate calculate_debtor_accounts(wallet_or_id), to: LesBonsComptes.Expenses
  defdelegate list_debtors(wallet_or_id), to: LesBonsComptes.Expenses
  defdelegate calculate_settlements(wallet_or_id), to: LesBonsComptes.Expenses
  defdelegate optimize_settlements(wallet_or_id), to: LesBonsComptes.Expenses
  defdelegate mock_settle_transfer(wallet_or_id, params), to: LesBonsComptes.Expenses
  defdelegate mock_settle_transfer(wallet_or_id, from_id, to_id, amount),
    to: LesBonsComptes.Expenses
  defdelegate mock_settle_all(wallet_or_id), to: LesBonsComptes.Expenses

  @doc """
  Retourne tous les porte-monnaies auxquels l'utilisateur participe
  (soit comme créateur, soit comme membre enregistré).
  """
  def list_wallets_for_user(user_id) when is_integer(user_id) do
    from(w in Wallet,
      left_join: m in assoc(w, :members),
      where: w.creator_id == ^user_id or m.user_id == ^user_id,
      distinct: true,
      order_by: [desc: w.inserted_at],
      preload: [:creator, :members]
    )
    |> Repo.all()
  end

  @doc """
  Récupère un porte-monnaie par son ID avec ses membres, ses invitations et son créateur. Lève si introuvable.
  """
  def get_wallet!(id) do
    Wallet
    |> Repo.get!(id)
    |> Repo.preload([
      :creator,
      members: from(m in WalletMember, order_by: [asc: m.id]),
      invitations:
        from(i in WalletInvitation,
          where: i.status in ["pending", "declined"],
          order_by: [desc: i.inserted_at],
          preload: [:invitee, :inviter]
        ),
      expenses:
        from(e in LesBonsComptes.Expenses.Expense,
          order_by: [desc: e.date, desc: e.inserted_at],
          preload: [:payer, :created_by]
        )
    ])
  end

  @doc """
  Récupère un porte-monnaie par son ID. Retourne nil si introuvable.
  """
  def get_wallet(id) do
    case Repo.get(Wallet, id) do
      nil ->
        nil

      wallet ->
        Repo.preload(wallet, [:creator, members: from(m in WalletMember, order_by: [asc: m.id])])
    end
  end

  @doc """
  Initialise un changeset pour un nouveau porte-monnaie.
  """
  def change_wallet(%Wallet{} = wallet, attrs \\ %{}) do
    Wallet.changeset(wallet, attrs)
  end

  @doc """
  Crée un porte-monnaie commun (IF-31), valide ses données (IF-32),
  initialise le propriétaire avec ses droits "owner" (IF-36)
  et associe les membres/participants supplémentaires (IF-30).

  L'opération est transactionnelle via `Ecto.Multi`.
  Si une donnée est invalide, la transaction est annulée.

  ## Paramètres
  - `creator`: Le `%User{}` connecté qui crée le porte-monnaie.
  - `wallet_attrs`: Les attributs du porte-monnaie (`name`, `description`, `currency`).
  - `participants`: Liste de maps pour les autres membres, ex:
    `[%{name: "Alice", email: "alice@example.com", user_id: 2}, %{name: "Bob"}]`
  """
  def create_wallet(%User{} = creator, wallet_attrs, participants \\ []) do
    Repo.transaction(fn ->
      wallet_changeset =
        %Wallet{creator_id: creator.id}
        |> Wallet.changeset(wallet_attrs)

      case Repo.insert(wallet_changeset) do
        {:ok, wallet} ->
          owner_changeset =
            %WalletMember{wallet_id: wallet.id, user_id: creator.id}
            |> WalletMember.changeset(%{
              name: creator.name,
              email: creator.email,
              role: "owner"
            })

          case Repo.insert(owner_changeset) do
            {:ok, _owner} ->
              case Members.insert_additional_members(wallet, creator, participants) do
                :ok ->
                  get_wallet!(wallet.id)

                {:error, :member, member_changeset} ->
                  Repo.rollback({:member, member_changeset})
              end

            {:error, owner_changeset} ->
              Repo.rollback({:owner_member, owner_changeset})
          end

        {:error, changeset} ->
          Repo.rollback({:wallet, changeset})
      end
    end)
    |> case do
      {:ok, wallet} -> {:ok, wallet}
      {:error, {:wallet, changeset}} -> {:error, :wallet, changeset}
      {:error, {:member, changeset}} -> {:error, :member, changeset}
      {:error, {:owner_member, changeset}} -> {:error, :owner_member, changeset}
      {:error, reason} -> {:error, :general, reason}
    end
  end

  @doc """
  Met à jour un porte-monnaie avec vérification que l'utilisateur est bien le propriétaire.
  """
  def update_wallet(%User{} = user, %Wallet{} = wallet, attrs) do
    if owner?(wallet, user) do
      update_wallet(wallet, attrs)
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Met à jour les attributs d'un porte-monnaie.
  """
  def update_wallet(%Wallet{} = wallet, attrs) do
    wallet
    |> Wallet.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Supprime un porte-monnaie avec vérification que l'utilisateur est bien le propriétaire.
  """
  def delete_wallet(%User{} = user, %Wallet{} = wallet) do
    if owner?(wallet, user) do
      delete_wallet(wallet)
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Supprime un porte-monnaie de la base de données.
  """
  def delete_wallet(%Wallet{} = wallet) do
    Repo.delete(wallet)
  end

  @doc """
  Clôture un porte-monnaie (IF-85). Seul le propriétaire peut clore le groupe.
  """
  def close_wallet(%User{} = user, %Wallet{} = wallet) do
    if owner?(wallet, user) do
      close_wallet(wallet)
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Clôture un porte-monnaie en passant son statut à "closed".
  """
  def close_wallet(%Wallet{} = wallet) do
    update_wallet(wallet, %{status: "closed"})
  end

  @doc """
  Rouvre un porte-monnaie clos (IF-85). Seul le propriétaire peut rouvrir le groupe.
  """
  def reopen_wallet(%User{} = user, %Wallet{} = wallet) do
    if owner?(wallet, user) do
      reopen_wallet(wallet)
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Rouvre un porte-monnaie en repassant son statut à "open".
  """
  def reopen_wallet(%Wallet{} = wallet) do
    update_wallet(wallet, %{status: "open"})
  end

  @doc """
  Indique si le porte-monnaie est clos.
  """
  def closed?(%Wallet{} = wallet), do: Wallet.closed?(wallet)
  def closed?(_), do: false

  @doc """
  Indique si le porte-monnaie est ouvert.
  """
  def open?(%Wallet{} = wallet), do: Wallet.open?(wallet)
  def open?(_), do: false
end

