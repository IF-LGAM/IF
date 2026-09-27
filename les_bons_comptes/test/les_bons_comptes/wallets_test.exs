defmodule LesBonsComptes.WalletsTest do
  use LesBonsComptes.DataCase, async: true

  alias LesBonsComptes.Accounts
  alias LesBonsComptes.Wallets
  alias LesBonsComptes.Wallets.Wallet

  defp create_user(attrs \\ %{}) do
    unique_suffix = System.unique_integer([:positive])

    default_attrs = %{
      name: "Utilisateur #{unique_suffix}",
      email: "user_#{unique_suffix}@example.com",
      password: "password123"
    }

    {:ok, user} = Accounts.create_user(Map.merge(default_attrs, attrs))
    user
  end

  describe "create_wallet/3 (IF-31, IF-32, IF-36, IF-30)" do
    test "crée avec succès un porte-monnaie et initialise le propriétaire (IF-31, IF-36)" do
      creator = create_user(%{name: "Alice", email: "alice@test.com"})

      valid_attrs = %{
        name: "Vacances en Corse",
        description: "Frais de groupe été",
        currency: "EUR"
      }

      assert {:ok, %Wallet{} = wallet} = Wallets.create_wallet(creator, valid_attrs)
      assert wallet.name == "Vacances en Corse"
      assert wallet.description == "Frais de groupe été"
      assert wallet.currency == "EUR"
      assert wallet.creator_id == creator.id

      # Vérification de l'initialisation des droits et du propriétaire (IF-36)
      assert length(wallet.members) == 1
      [owner_member] = wallet.members
      assert owner_member.role == "owner"
      assert owner_member.user_id == creator.id
      assert owner_member.name == "Alice"
      assert owner_member.email == "alice@test.com"
    end

    test "associe des participants enregistrés et non enregistrés au porte-monnaie (IF-30)" do
      creator = create_user(%{name: "Alice"})
      registered_friend = create_user(%{name: "Bob", email: "bob@test.com"})

      participants = [
        %{name: "Bob", email: "bob@test.com", user_id: registered_friend.id},
        %{name: "Charlie (sans compte)", email: "charlie@test.com"}
      ]

      attrs = %{name: "Colocation 2026", currency: "EUR"}

      assert {:ok, %Wallet{} = wallet} = Wallets.create_wallet(creator, attrs, participants)
      assert length(wallet.members) == 3

      member_names = Enum.map(wallet.members, & &1.name)
      assert "Alice" in member_names
      assert "Bob" in member_names
      assert "Charlie (sans compte)" in member_names

      # Bob est lié au compte utilisateur
      bob_member = Enum.find(wallet.members, &(&1.name == "Bob"))
      assert bob_member.user_id == registered_friend.id
      assert bob_member.role == "member"

      # Charlie est un participant externe sans compte utilisateur lié
      charlie_member = Enum.find(wallet.members, &(&1.name == "Charlie (sans compte)"))
      assert charlie_member.user_id == nil
      assert charlie_member.role == "member"
    end

    test "rejette la création si le nom est manquant ou trop court (IF-32)" do
      creator = create_user()

      assert {:error, :wallet, changeset} = Wallets.create_wallet(creator, %{name: ""})
      assert "ce champ est obligatoire" in errors_on(changeset).name

      assert {:error, :wallet, changeset} = Wallets.create_wallet(creator, %{name: "A"})
      assert "doit contenir entre 2 et 100 caractères" in errors_on(changeset).name
    end

    test "rejette la création si la devise n'est pas supportée (IF-32)" do
      creator = create_user()

      assert {:error, :wallet, changeset} =
               Wallets.create_wallet(creator, %{name: "Voyage", currency: "INVALID"})

      assert "devise non supportée" in errors_on(changeset).currency
    end

    test "rejette la création si un participant a des données invalides (IF-30, IF-32)" do
      creator = create_user()

      participants = [%{name: "", email: "invalid-email"}]

      assert {:error, :member, changeset} =
               Wallets.create_wallet(creator, %{name: "Voyage"}, participants)

      assert "ce champ est obligatoire" in errors_on(changeset).name
    end
  end

  describe "list_wallets_for_user/1" do
    test "retourne les porte-monnaies dont l'utilisateur est propriétaire ou membre" do
      user1 = create_user(%{name: "User 1"})
      user2 = create_user(%{name: "User 2"})

      # Wallet créé par user1 avec user2
      {:ok, wallet1} =
        Wallets.create_wallet(user1, %{name: "Porte-monnaie 1"}, [
          %{name: user2.name, user_id: user2.id}
        ])

      # Wallet créé par user2 seul
      {:ok, wallet2} = Wallets.create_wallet(user2, %{name: "Porte-monnaie 2"})

      # Wallet d'un tiers sans user1
      user3 = create_user()
      {:ok, _wallet3} = Wallets.create_wallet(user3, %{name: "Porte-monnaie 3"})

      wallets_u1 = Wallets.list_wallets_for_user(user1.id)
      assert length(wallets_u1) == 1
      assert hd(wallets_u1).id == wallet1.id

      wallets_u2 = Wallets.list_wallets_for_user(user2.id)
      assert length(wallets_u2) == 2
      wallet_ids_u2 = Enum.map(wallets_u2, & &1.id)
      assert wallet1.id in wallet_ids_u2
      assert wallet2.id in wallet_ids_u2
    end
  end

  describe "owner?/2" do
    test "retourne true pour le créateur et false pour un autre utilisateur" do
      owner = create_user(%{name: "Owner"})
      other = create_user(%{name: "Other"})
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "Test Wallet"})

      assert Wallets.owner?(wallet, owner) == true
      assert Wallets.owner?(wallet, other) == false
    end
  end

  describe "update_wallet/3" do
    test "permet au propriétaire de modifier le porte-monnaie" do
      owner = create_user()
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "Nom Initial", currency: "EUR"})

      assert {:ok, updated} =
               Wallets.update_wallet(owner, wallet, %{
                 name: "Nouveau Nom",
                 description: "Description mise à jour",
                 currency: "USD"
               })

      assert updated.name == "Nouveau Nom"
      assert updated.description == "Description mise à jour"
      assert updated.currency == "USD"
    end

    test "refuse la modification si l'utilisateur n'est pas le propriétaire" do
      owner = create_user()
      other_user = create_user()
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "Porte-monnaie"})

      assert {:error, :unauthorized} =
               Wallets.update_wallet(other_user, wallet, %{name: "Hacked"})
    end

    test "rejette la modification si les données sont invalides" do
      owner = create_user()
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "Porte-monnaie"})

      assert {:error, %Ecto.Changeset{} = changeset} =
               Wallets.update_wallet(owner, wallet, %{name: ""})

      assert "ce champ est obligatoire" in errors_on(changeset).name
    end

    test "refuse la modification si le porte-monnaie est en cours de virement ou clos" do
      owner = create_user()
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "Porte-monnaie"})

      {:ok, pending_wallet} = Wallets.validate_wallet(owner, wallet)
      assert {:error, :wallet_closed} = Wallets.update_wallet(owner, pending_wallet, %{name: "Modif"})
      assert {:error, :wallet_closed} = Wallets.update_wallet(pending_wallet, %{name: "Modif"})

      {:ok, closed_wallet} = Wallets.close_wallet(owner, pending_wallet)
      assert {:error, :wallet_closed} = Wallets.update_wallet(owner, closed_wallet, %{name: "Modif"})
      assert {:error, :wallet_closed} = Wallets.update_wallet(closed_wallet, %{name: "Modif"})
    end
  end

  describe "delete_wallet/2" do
    test "permet au propriétaire de supprimer le porte-monnaie" do
      owner = create_user()
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "À supprimer"})

      assert {:ok, _deleted} = Wallets.delete_wallet(owner, wallet)
      assert Wallets.get_wallet(wallet.id) == nil
    end

    test "refuse la suppression si l'utilisateur n'est pas le propriétaire" do
      owner = create_user()
      other_user = create_user()
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "Porte-monnaie"})

      assert {:error, :unauthorized} = Wallets.delete_wallet(other_user, wallet)
      assert Wallets.get_wallet(wallet.id) != nil
    end
  end

  describe "Gestion des membres post-création" do
    test "add_member/3 permet au propriétaire d'ajouter un membre" do
      owner = create_user()
      friend = create_user(%{name: "Ami"})
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "Voyage"})

      assert {:ok, member} =
               Wallets.add_member(owner, wallet, %{
                 name: friend.name,
                 user_id: friend.id,
                 email: friend.email
               })

      assert member.user_id == friend.id
      assert length(Wallets.get_wallet!(wallet.id).members) == 2
    end

    test "add_member/3 refuse l'ajout si l'utilisateur n'est pas propriétaire" do
      owner = create_user()
      other_user = create_user()
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "Voyage"})

      assert {:error, :unauthorized} =
               Wallets.add_member(other_user, wallet, %{name: "Inconnu"})
    end

    test "remove_member/3 permet au propriétaire de retirer un participant (non-owner)" do
      owner = create_user()
      friend = create_user()

      {:ok, wallet} =
        Wallets.create_wallet(owner, %{name: "Voyage"}, [%{name: friend.name, user_id: friend.id}])

      [_, friend_member] = Wallets.get_wallet!(wallet.id).members

      assert {:ok, _deleted} = Wallets.remove_member(owner, wallet, friend_member.id)
      assert length(Wallets.get_wallet!(wallet.id).members) == 1
    end

    test "remove_member/3 interdit de retirer le propriétaire" do
      owner = create_user()
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "Voyage"})
      [owner_member] = wallet.members

      assert {:error, :cannot_remove_owner} =
               Wallets.remove_member(owner, wallet, owner_member.id)
    end

    test "leave_wallet/2 permet à un participant de quitter le porte-monnaie" do
      owner = create_user()
      friend = create_user()

      {:ok, wallet} =
        Wallets.create_wallet(owner, %{name: "Voyage"}, [%{name: friend.name, user_id: friend.id}])

      assert {:ok, _member} = Wallets.leave_wallet(friend, wallet)
      assert length(Wallets.get_wallet!(wallet.id).members) == 1
    end

    test "leave_wallet/2 interdit au propriétaire de quitter son propre porte-monnaie" do
      owner = create_user()
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "Voyage"})

      assert {:error, :owner_cannot_leave} = Wallets.leave_wallet(owner, wallet)
    end
  end

  describe "Invitations au porte-monnaie (IF-37, IF-40, IF-41, IF-42, IF-44, IF-45)" do
    test "create_invitation/3 crée une invitation en attente et prépare la notification" do
      owner = create_user(%{name: "Alice"})
      invitee = create_user(%{name: "Bob", email: "bob_invite@test.com"})
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "Vacances 2026"})

      assert {:ok, invitation} =
               Wallets.create_invitation(owner, wallet, %{email: "bob_invite@test.com"})

      assert invitation.status == "pending"
      assert invitation.inviter_id == owner.id
      assert invitation.invitee_id == invitee.id
      assert invitation.wallet_id == wallet.id
      assert invitation.email == "bob_invite@test.com"
    end

    test "create_invitation/3 refuse si l'utilisateur invité est inconnu (IF-41)" do
      owner = create_user()
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "Voyage"})

      assert {:error, msg} =
               Wallets.create_invitation(owner, wallet, %{email: "inconnu@test.com"})

      assert msg =~ "Aucun utilisateur inscrit"
    end

    test "create_invitation/3 refuse si l'utilisateur est déjà membre (IF-41)" do
      owner = create_user()
      member = create_user(%{email: "member@test.com"})

      {:ok, wallet} =
        Wallets.create_wallet(owner, %{name: "Voyage"}, [
          %{name: member.name, email: member.email, user_id: member.id}
        ])

      assert {:error, msg} =
               Wallets.create_invitation(owner, wallet, %{email: "member@test.com"})

      assert msg =~ "fait déjà partie des participants"
    end

    test "create_invitation/3 refuse si une invitation est déjà en attente (IF-41)" do
      owner = create_user()
      _invitee = create_user(%{email: "already_invited@test.com"})
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "Voyage"})

      assert {:ok, _} =
               Wallets.create_invitation(owner, wallet, %{email: "already_invited@test.com"})

      assert {:error, msg} =
               Wallets.create_invitation(owner, wallet, %{email: "already_invited@test.com"})

      assert msg =~ "déjà en attente"
    end

    test "create_invitation/3 refuse si l'émetteur n'est pas le propriétaire" do
      owner = create_user()
      stranger = create_user()
      _invitee = create_user(%{email: "invitee@test.com"})
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "Voyage"})

      assert {:error, :unauthorized} =
               Wallets.create_invitation(stranger, wallet, %{email: "invitee@test.com"})
    end

    test "accept_invitation/2 associe l'utilisateur au porte-monnaie et met à jour le statut (IF-44, IF-45)" do
      owner = create_user(%{name: "Owner"})
      invitee = create_user(%{name: "Invitee", email: "invitee@test.com"})
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "Fête"})

      {:ok, invitation} =
        Wallets.create_invitation(owner, wallet, %{email: "invitee@test.com"})

      assert {:ok, member} = Wallets.accept_invitation(invitee, invitation.id)
      assert member.user_id == invitee.id
      assert member.role == "member"

      # Vérification dans la base
      updated_wallet = Wallets.get_wallet!(wallet.id)
      assert length(updated_wallet.members) == 2
      assert Enum.any?(updated_wallet.members, &(&1.user_id == invitee.id))

      # L'invitation n'est plus en attente
      assert Wallets.list_pending_invitations_for_user(invitee.id) == []
    end

    test "accept_invitation/2 refuse si un autre utilisateur tente d'accepter" do
      owner = create_user()
      _invitee = create_user(%{email: "destinataire@test.com"})
      stranger = create_user()
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "Projet"})

      {:ok, invitation} =
        Wallets.create_invitation(owner, wallet, %{email: "destinataire@test.com"})

      assert {:error, :unauthorized} = Wallets.accept_invitation(stranger, invitation.id)
    end

    test "decline_invitation/2 passe le statut à declined sans créer de membre (IF-44)" do
      owner = create_user()
      invitee = create_user(%{email: "decline@test.com"})
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "Sortie"})

      {:ok, invitation} =
        Wallets.create_invitation(owner, wallet, %{email: "decline@test.com"})

      assert {:ok, declined} = Wallets.decline_invitation(invitee, invitation.id)
      assert declined.status == "declined"

      # Ne fait pas partie des membres
      updated_wallet = Wallets.get_wallet!(wallet.id)
      assert length(updated_wallet.members) == 1
      refute Enum.any?(updated_wallet.members, &(&1.user_id == invitee.id))
      assert Wallets.list_pending_invitations_for_user(invitee.id) == []
    end

    test "cancel_invitation/2 permet au propriétaire d'annuler l'invitation" do
      owner = create_user()
      _invitee = create_user(%{email: "cancel@test.com"})
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "Roadtrip"})

      {:ok, invitation} =
        Wallets.create_invitation(owner, wallet, %{email: "cancel@test.com"})

      assert {:ok, cancelled} = Wallets.cancel_invitation(owner, invitation.id)
      assert cancelled.status == "cancelled"
      assert Wallets.list_pending_invitations_for_wallet(wallet.id) == []
    end
  end

  describe "Statut, cycle de vie en 3 étapes et clôture du porte-monnaie (IF-85)" do
    test "un nouveau porte-monnaie a le statut 'open' par défaut (Étape 1 : Déclarations)" do
      owner = create_user()
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "Porte-monnaie Ouvert"})

      assert wallet.status == "open"
      assert Wallets.open?(wallet)
      refute Wallets.pending_settlement?(wallet)
      refute Wallets.closed?(wallet)
      assert Wallets.step_number(wallet) == 1
      assert Wallets.status_label(wallet) == "Déclarations en cours"
    end

    test "validate_wallet/2 permet au propriétaire de passer à l'attente des virements (Étape 2)" do
      owner = create_user()
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "À Valider"})

      assert {:ok, validated_wallet} = Wallets.validate_wallet(owner, wallet)
      assert validated_wallet.status == "pending_settlement"
      assert Wallets.pending_settlement?(validated_wallet)
      refute Wallets.open?(validated_wallet)
      refute Wallets.closed?(validated_wallet)
      assert Wallets.step_number(validated_wallet) == 2
      assert Wallets.status_label(validated_wallet) == "Attente des virements"
    end

    test "validate_wallet/2 rejette la validation par un non-propriétaire" do
      owner = create_user()
      stranger = create_user(%{email: "stranger_val@test.com"})
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "Protégé"})

      assert Wallets.validate_wallet(stranger, wallet) == {:error, :unauthorized}
      reloaded = Wallets.get_wallet!(wallet.id)
      assert reloaded.status == "open"
    end

    test "close_wallet/2 permet au propriétaire de clôturer le porte-monnaie (Étape 3 : Clôturé)" do
      owner = create_user()
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "À Clôturer"})

      assert {:ok, closed_wallet} = Wallets.close_wallet(owner, wallet)
      assert closed_wallet.status == "closed"
      assert Wallets.closed?(closed_wallet)
      refute Wallets.open?(closed_wallet)
      refute Wallets.pending_settlement?(closed_wallet)
      assert Wallets.step_number(closed_wallet) == 3
      assert Wallets.status_label(closed_wallet) == "Clôturé"
    end

    test "close_wallet/2 rejette la clôture par un non-propriétaire" do
      owner = create_user()
      stranger = create_user(%{email: "stranger@test.com"})
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "Protégé"})

      assert Wallets.close_wallet(stranger, wallet) == {:error, :unauthorized}
      reloaded = Wallets.get_wallet!(wallet.id)
      assert reloaded.status == "open"
    end

    test "reopen_wallet/2 permet de rouvrir un porte-monnaie validé (Étape 2 -> Étape 1)" do
      owner = create_user()
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "À Rouvrir"})
      {:ok, pending_wallet} = Wallets.validate_wallet(owner, wallet)
      assert pending_wallet.status == "pending_settlement"
      assert Wallets.reopenable?(pending_wallet)

      assert {:ok, back_to_open} = Wallets.reopen_wallet(owner, pending_wallet)
      assert back_to_open.status == "open"
      assert Wallets.open?(back_to_open)
      assert Wallets.step_number(back_to_open) == 1
    end

    test "reopen_wallet/2 refuse catégoriquement de rouvrir un porte-monnaie clos (la clôture est définitive)" do
      owner = create_user()
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "Clos Définitif"})
      {:ok, closed_wallet} = Wallets.close_wallet(owner, wallet)
      assert closed_wallet.status == "closed"
      refute Wallets.reopenable?(closed_wallet)

      assert Wallets.reopen_wallet(owner, closed_wallet) == {:error, :closure_is_final}
    end

    test "reopen_wallet/2 rejette la réouverture par un non-propriétaire" do
      owner = create_user()
      stranger = create_user(%{email: "stranger2@test.com"})
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "En attente"})
      {:ok, pending_wallet} = Wallets.validate_wallet(owner, wallet)

      assert Wallets.reopen_wallet(stranger, pending_wallet) == {:error, :unauthorized}
    end

    test "validation du statut dans le changeset pour les 3 étapes" do
      wallet = %Wallet{}

      for status <- ~w(open pending_settlement closed) do
        cs = Wallet.changeset(wallet, %{name: "Test", currency: "EUR", status: status})
        assert cs.valid?, "Le statut #{status} devrait être valide"
      end

      invalid_changeset = Wallet.changeset(wallet, %{name: "Test", currency: "EUR", status: "invalid_status"})
      refute invalid_changeset.valid?
      assert "statut invalide" in errors_on(invalid_changeset).status
    end

    test "les invitations existantes ne fonctionnent plus en phase de virement" do
      owner = create_user()
      invitee = create_user(%{email: "invitee_phase2@test.com"})
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "En Virement"})
      {:ok, invitation} = Wallets.create_invitation(owner, wallet, %{email: invitee.email})

      {:ok, pending_wallet} = Wallets.validate_wallet(owner, wallet)

      # Création refusée
      other = create_user(%{email: "other_phase2@test.com"})
      assert {:error, :invitations_disabled} =
               Wallets.create_invitation(owner, pending_wallet, %{email: other.email})

      # Acceptation de l'invitation existante refusée
      assert {:error, :invitations_disabled} =
               Wallets.accept_invitation(invitee, invitation.id)
    end

    test "les invitations existantes sont supprimées à la clôture du porte-monnaie" do
      owner = create_user()
      invitee = create_user(%{email: "invitee_close@test.com"})
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "Avec Invitations"})
      {:ok, invitation} = Wallets.create_invitation(owner, wallet, %{email: invitee.email})

      assert Wallets.list_pending_invitations_for_wallet(wallet.id) != []

      {:ok, _closed} = Wallets.close_wallet(owner, wallet)

      assert Wallets.list_pending_invitations_for_wallet(wallet.id) == []
      assert_raise Ecto.NoResultsError, fn -> Wallets.get_invitation!(invitation.id) end
    end
  end
end
