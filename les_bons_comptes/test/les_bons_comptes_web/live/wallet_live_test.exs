defmodule LesBonsComptesWeb.WalletLiveTest do
  use LesBonsComptesWeb.ConnCase
  import Phoenix.LiveViewTest

  alias LesBonsComptes.Accounts
  alias LesBonsComptes.Expenses
  alias LesBonsComptes.Wallets

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

  defp authenticate_user(conn, user) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
  end

  describe "Accès et authentification" do
    test "redirige vers /sign-in si l'utilisateur n'est pas connecté", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/wallets/new")
      assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/wallets")
    end
  end

  describe "IF-33 & IF-36 : Formulaire de création et initialisation du propriétaire" do
    test "affiche le formulaire avec le créateur en tant que propriétaire verrouillé", %{
      conn: conn
    } do
      user = create_user(%{name: "Alice Dupont", email: "alice@example.com"})
      conn = authenticate_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/wallets/new")

      # Verify form fields presence (IF-33)
      assert has_element?(view, "#wallet-create-form")
      assert has_element?(view, "#wallet-name-input")
      assert has_element?(view, "#wallet-currency-select")
      assert has_element?(view, "#wallet-description-input")
      assert has_element?(view, "#submit-wallet-btn")

      # Verify owner initialization (IF-36)
      assert has_element?(view, "#member-owner-#{user.id}")
      assert element(view, "#member-owner-#{user.id}") |> render() =~ "Alice Dupont"
      assert element(view, "#member-owner-#{user.id}") |> render() =~ "Organisateur (Toi)"
    end
  end

  describe "IF-35 : Gestion des erreurs du formulaire de création" do
    test "affiche une erreur de validation lorsque le nom est trop court ou vide", %{conn: conn} do
      user = create_user()
      conn = authenticate_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/wallets/new")

      # Real-time validation (phx-change)
      html =
        view
        |> form("#wallet-create-form", wallet: %{name: "A", currency: "EUR"})
        |> render_change()

      assert html =~ "doit contenir entre 2 et 100 caractères"
    end
  end

  describe "IF-29 & IF-30 : Sélection et association des participants" do
    test "permet d'ajouter un utilisateur inscrit via suggestion et par email manuellement, puis d'en retirer un",
         %{
           conn: conn
         } do
      current_user = create_user(%{name: "Alice"})
      registered_friend = create_user(%{name: "Bob Inscription", email: "bob@example.com"})
      _charlie_friend = create_user(%{name: "Charlie Amis", email: "charlie@email.com"})
      conn = authenticate_user(conn, current_user)

      {:ok, view, _html} = live(conn, ~p"/wallets/new")

      # 1. Add registered user from suggestions
      assert has_element?(view, "#add-user-btn-#{registered_friend.id}")

      view
      |> element("#add-user-btn-#{registered_friend.id}")
      |> render_click()

      assert render(view) =~ "Bob Inscription"
      assert render(view) =~ "Inscrit"
      refute render(view) =~ "Externe"

      # 2. Manual addition of registered participant by email
      view
      |> element("#add-custom-participant-btn")
      |> render_click(%{"email" => "charlie@email.com"})

      assert render(view) =~ "Charlie Amis"
      assert render(view) =~ "Inscrit"
      refute render(view) =~ "Externe"

      # 3. Remove a participant
      view
      |> element("#participants-list > div:first-child button[phx-click='remove_participant']")
      |> render_click()

      # Only one participant remains in added members list
      refute has_element?(view, "#participants-list", "Bob Inscription")
      assert has_element?(view, "#participants-list", "Charlie Amis")
      # And Bob is available again in suggestions
      assert has_element?(view, "#add-user-btn-#{registered_friend.id}")
    end

    test "conserve les participants déjà ajoutés lors de la saisie et de l'ajout d'un participant manuel par email",
         %{conn: conn} do
      current_user = create_user(%{name: "Alice"})
      registered_friend = create_user(%{name: "Bob Inscription", email: "bob@example.com"})

      _charlie_friend =
        create_user(%{name: "Charlie Manuel", email: "charlie_manuel@example.com"})

      conn = authenticate_user(conn, current_user)

      {:ok, view, _html} = live(conn, ~p"/wallets/new")

      # 1. Add Bob
      view
      |> element("#add-user-btn-#{registered_friend.id}")
      |> render_click()

      assert has_element?(view, "#participants-list", "Bob Inscription")

      # 2. Manual email entry (input event simulation)
      view
      |> element("#custom-participant-email")
      |> render_keyup(%{"value" => "charlie_manuel@example.com"})

      # Bob is still present after input!
      assert has_element?(view, "#participants-list", "Bob Inscription")

      # 3. Click Add this participant
      view
      |> element("#add-custom-participant-btn")
      |> render_click(%{"email" => "charlie_manuel@example.com"})

      # Both participants are present simultaneously with Registered badge!
      assert has_element?(view, "#participants-list", "Bob Inscription")
      assert has_element?(view, "#participants-list", "Charlie Manuel")
      assert render(view) =~ "Inscrit"
      refute render(view) =~ "Externe"
    end

    test "affiche une erreur si l'email du participant manuel est vide, invalide ou non inscrit",
         %{conn: conn} do
      user = create_user()
      conn = authenticate_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/wallets/new")

      # Empty email
      view
      |> element("#add-custom-participant-btn")
      |> render_click(%{"email" => ""})

      assert has_element?(view, "#participant-error-alert", "L'adresse email est obligatoire")

      # Invalid email
      view
      |> element("#add-custom-participant-btn")
      |> render_click(%{"email" => "pas_un_email"})

      assert has_element?(
               view,
               "#participant-error-alert",
               "Veuillez saisir une adresse email valide"
             )

      # Email not registered on platform
      view
      |> element("#add-custom-participant-btn")
      |> render_click(%{"email" => "inconnu@test.com"})

      assert has_element?(
               view,
               "#participant-error-alert",
               "Aucun utilisateur inscrit avec l'email"
             )
    end
  end

  describe "IF-31 & IF-34 : Création du porte-monnaie et confirmation" do
    test "crée le porte-monnaie avec succès, redirige et affiche la confirmation complète", %{
      conn: conn
    } do
      creator = create_user(%{name: "Sophie", email: "sophie@test.com"})
      friend = create_user(%{name: "Lucas", email: "lucas@test.com"})
      _marc = create_user(%{name: "Marc", email: "marc@test.com"})
      conn = authenticate_user(conn, creator)

      {:ok, view, _html} = live(conn, ~p"/wallets/new")

      # Add friend via suggestions
      view
      |> element("#add-user-btn-#{friend.id}")
      |> render_click()

      # Add registered friend manually by email
      view
      |> element("#add-custom-participant-btn")
      |> render_click(%{"email" => "marc@test.com"})

      # Form submission (IF-31)
      {:error, {:live_redirect, %{to: show_path}}} =
        view
        |> form("#wallet-create-form",
          wallet: %{
            name: "Voyage à Rome",
            currency: "EUR",
            description: "Dépenses du voyage entre amis"
          }
        )
        |> render_submit()

      assert show_path =~ ~r"^/wallets/\d+$"

      # Follow redirect to confirmation page (IF-34)
      {:ok, show_view, html} = live(conn, show_path)

      # Verify confirmation and displayed information
      assert has_element?(show_view, "#wallet-name")
      assert element(show_view, "#wallet-name") |> render() =~ "Voyage à Rome"
      assert has_element?(show_view, "#wallet-currency-badge")
      assert element(show_view, "#wallet-currency-badge") |> render() =~ "EUR"
      assert has_element?(show_view, "#wallet-description")

      assert element(show_view, "#wallet-description") |> render() =~
               "Dépenses du voyage entre amis"

      # Verify owner (IF-36)
      assert has_element?(show_view, "#owner-name")
      assert element(show_view, "#owner-name") |> render() =~ "Sophie"

      # Verify participants (IF-30, IF-37):
      # Creator is initial member, Lucas and Marc received pending invitations
      assert element(show_view, "#members-count") |> render() =~ "1"
      assert html =~ "Sophie"
      assert html =~ "Invitations envoyées"
      assert html =~ "Lucas"
      assert html =~ "Marc"
    end
  end

  describe "Index des porte-monnaies" do
    test "affiche l'état vide si l'utilisateur n'a aucun porte-monnaie", %{conn: conn} do
      user = create_user()
      conn = authenticate_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/wallets")

      assert has_element?(view, "#empty-wallets-state")
      assert has_element?(view, "#new-wallet-btn")
    end

    test "affiche les cartes des porte-monnaies de l'utilisateur", %{conn: conn} do
      user = create_user()
      conn = authenticate_user(conn, user)

      {:ok, wallet} = Wallets.create_wallet(user, %{name: "Colocation Lille", currency: "EUR"})

      {:ok, view, _html} = live(conn, ~p"/wallets")

      assert has_element?(view, "#wallet-card-#{wallet.id}")
      assert element(view, "#wallet-card-#{wallet.id}") |> render() =~ "Colocation Lille"
    end
  end

  describe "Modification du porte-monnaie (seul le propriétaire)" do
    test "le propriétaire accède à la page d'édition, modifie le porte-monnaie et est redirigé",
         %{
           conn: conn
         } do
      owner = create_user(%{name: "Alice"})
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "Vacances 2026", currency: "EUR"})
      conn = authenticate_user(conn, owner)

      # 1. Access edit page
      {:ok, edit_view, _html} = live(conn, ~p"/wallets/#{wallet.id}/edit")

      assert has_element?(edit_view, "#wallet-edit-form")
      assert has_element?(edit_view, "#wallet-name-input")
      assert has_element?(edit_view, "#submit-edit-wallet-btn")

      # 2. Submit modifications
      {:error, {:live_redirect, %{to: show_path}}} =
        edit_view
        |> form("#wallet-edit-form",
          wallet: %{name: "Vacances Espagne 2026", currency: "USD", description: "Mise à jour"}
        )
        |> render_submit()

      assert show_path == ~p"/wallets/#{wallet.id}"

      # 3. Verify effective update
      {:ok, show_view, _html} = live(conn, show_path)
      assert element(show_view, "#wallet-name") |> render() =~ "Vacances Espagne 2026"
      assert element(show_view, "#wallet-currency-badge") |> render() =~ "USD"
      assert element(show_view, "#wallet-description") |> render() =~ "Mise à jour"
    end

    test "un utilisateur non-propriétaire est rejeté de la page d'édition", %{conn: conn} do
      owner = create_user(%{name: "Owner"})
      other = create_user(%{name: "Other"})
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "Privé", currency: "EUR"})
      conn = authenticate_user(conn, other)

      # Attempt to access edit page
      {:error, {:live_redirect, %{to: redirect_to, flash: flash}}} =
        live(conn, ~p"/wallets/#{wallet.id}/edit")

      assert redirect_to == ~p"/wallets/#{wallet.id}"
      assert flash["error"] =~ "Seul le propriétaire peut modifier ce porte-monnaie"
    end

    test "les boutons Modifier et Supprimer ne sont visibles que par le propriétaire sur la page Show",
         %{
           conn: conn
         } do
      owner = create_user(%{name: "Proprio"})
      other = create_user(%{name: "Membre"})

      {:ok, wallet} =
        Wallets.create_wallet(owner, %{name: "Groupe"}, [%{name: "Membre", user_id: other.id}])

      # View by owner
      owner_conn = authenticate_user(conn, owner)
      {:ok, owner_view, _html} = live(owner_conn, ~p"/wallets/#{wallet.id}")
      assert has_element?(owner_view, "#edit-wallet-btn")
      assert has_element?(owner_view, "#delete-wallet-btn")

      # View by non-owner member
      other_conn = authenticate_user(conn, other)
      {:ok, other_view, _html} = live(other_conn, ~p"/wallets/#{wallet.id}")
      refute has_element?(other_view, "#edit-wallet-btn")
      refute has_element?(other_view, "#delete-wallet-btn")
    end
  end

  describe "Suppression du porte-monnaie (seul le propriétaire)" do
    test "le propriétaire peut supprimer le porte-monnaie depuis la page Show", %{conn: conn} do
      owner = create_user(%{name: "Proprio"})
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "Suppression Test"})
      conn = authenticate_user(conn, owner)

      {:ok, view, _html} = live(conn, ~p"/wallets/#{wallet.id}")

      {:error, {:live_redirect, %{to: index_path}}} =
        view
        |> element("#delete-wallet-btn")
        |> render_click()

      assert index_path == ~p"/wallets"
      assert Wallets.get_wallet(wallet.id) == nil
    end
  end

  describe "Gestion des membres et invitations dans l'interface (IF-38, IF-39, IF-43)" do
    test "le propriétaire peut inviter un utilisateur inscrit via suggestion ou email, annuler une invitation et retirer un membre",
         %{conn: conn} do
      owner = create_user(%{name: "Proprio"})
      registered_user = create_user(%{name: "Inscrit Nouveau", email: "inscrit@test.com"})
      _manual_user = create_user(%{name: "Ami Manuel", email: "manuel@test.com"})
      existing_member = create_user(%{name: "Membre Actuel", email: "actuel@test.com"})

      {:ok, wallet} =
        Wallets.create_wallet(owner, %{name: "Vacances"}, [
          %{name: existing_member.name, email: existing_member.email, user_id: existing_member.id}
        ])

      conn = authenticate_user(conn, owner)

      {:ok, edit_view, _html} = live(conn, ~p"/wallets/#{wallet.id}/edit")

      # 1. Send invitation to registered user from suggestions (IF-38, IF-40, IF-42, IF-43)
      assert has_element?(edit_view, "#add-user-btn-#{registered_user.id}")

      edit_view
      |> element("#add-user-btn-#{registered_user.id}")
      |> render_click()

      assert render(edit_view) =~ "Invitation envoyée avec succès à Inscrit Nouveau"
      assert has_element?(edit_view, "#pending-invitations-list")
      assert render(edit_view) =~ "Inscrit Nouveau"
      assert render(edit_view) =~ "Invitation envoyée"

      # 2. Send invitation manually by email (IF-39)
      edit_view
      |> element("#add-custom-participant-btn")
      |> render_click(%{"email" => "manuel@test.com"})

      assert render(edit_view) =~ "Invitation envoyée avec succès à Ami Manuel"
      assert render(edit_view) =~ "Ami Manuel"

      # 3. Cancel pending invitation
      [invitation | _] = Wallets.list_pending_invitations_for_wallet(wallet.id)

      edit_view
      |> element("#cancel-invitation-btn-#{invitation.id}")
      |> render_click()

      assert render(edit_view) =~ "invitation a été annulée"

      # 4. Remove active member
      [_, registered_member | _] = Wallets.get_wallet!(wallet.id).members

      edit_view
      |> element("#remove-member-btn-#{registered_member.id}")
      |> render_click()

      refute has_element?(edit_view, "#remove-member-btn-#{registered_member.id}")
    end

    test "un membre non-propriétaire peut quitter le porte-monnaie depuis la page Show", %{
      conn: conn
    } do
      owner = create_user(%{name: "Proprio"})
      member_user = create_user(%{name: "Membre Simple"})

      {:ok, wallet} =
        Wallets.create_wallet(owner, %{name: "Coloc"}, [
          %{name: member_user.name, user_id: member_user.id}
        ])

      conn = authenticate_user(conn, member_user)
      {:ok, view, _html} = live(conn, ~p"/wallets/#{wallet.id}")

      assert has_element?(view, "#leave-wallet-btn")

      {:error, {:live_redirect, %{to: index_path}}} =
        view
        |> element("#leave-wallet-btn")
        |> render_click()

      assert index_path == ~p"/wallets"
      # User is no longer part of members
      wallet_members = Wallets.get_wallet!(wallet.id).members
      refute Enum.any?(wallet_members, &(&1.user_id == member_user.id))
    end
  end

  describe "IF-44 & IF-45 : Acceptation ou refus d'invitation" do
    test "l'utilisateur peut accepter une invitation, rejoindre le porte-monnaie et le voir dans sa liste",
         %{conn: conn} do
      owner = create_user(%{name: "Organisateur"})
      invitee = create_user(%{name: "Invité Récepteur", email: "recepteur@test.com"})
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "Festival 2026", currency: "EUR"})

      {:ok, invitation} =
        Wallets.create_invitation(owner, wallet, %{email: "recepteur@test.com"})

      conn = authenticate_user(conn, invitee)

      {:ok, view, _html} = live(conn, ~p"/wallets")

      # 1. Verify display of received invitation (IF-44)
      assert has_element?(view, "#pending-invitations-section")
      assert has_element?(view, "#invitation-card-#{invitation.id}")
      assert render(view) =~ "Festival 2026"
      assert render(view) =~ "Organisateur"

      # 2. Click Accept (IF-44, IF-45)
      view
      |> element("#accept-invitation-btn-#{invitation.id}")
      |> render_click()

      assert render(view) =~ "Vous avez rejoint le porte-monnaie avec succès"
      refute has_element?(view, "#invitation-card-#{invitation.id}")

      # The wallet now appears in user's wallets
      assert has_element?(view, "#wallet-card-#{wallet.id}")
      assert render(view) =~ "Festival 2026"

      # User is persisted in database as group member (IF-45)
      wallet_members = Wallets.get_wallet!(wallet.id).members
      assert Enum.any?(wallet_members, &(&1.user_id == invitee.id))
    end

    test "l'utilisateur peut refuser une invitation sans rejoindre le groupe", %{conn: conn} do
      owner = create_user(%{name: "Organisateur"})
      invitee = create_user(%{name: "Refusant", email: "refus@test.com"})
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "Ski 2026", currency: "EUR"})

      {:ok, invitation} =
        Wallets.create_invitation(owner, wallet, %{email: "refus@test.com"})

      conn = authenticate_user(conn, invitee)

      {:ok, view, _html} = live(conn, ~p"/wallets")

      assert has_element?(view, "#invitation-card-#{invitation.id}")

      # Click Decline
      view
      |> element("#decline-invitation-btn-#{invitation.id}")
      |> render_click()

      assert render(view) =~ "Vous avez refusé"
      refute has_element?(view, "#invitation-card-#{invitation.id}")
      refute has_element?(view, "#wallet-card-#{wallet.id}")

      # Is not added as member
      wallet_members = Wallets.get_wallet!(wallet.id).members
      refute Enum.any?(wallet_members, &(&1.user_id == invitee.id))
    end

    test "le propriétaire voit le statut Refusée lorsqu'un invité a décliné l'invitation", %{
      conn: conn
    } do
      owner = create_user(%{name: "Propriétaire"})
      invitee = create_user(%{name: "Paul Refus", email: "paul@test.com"})
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "Soirée"})

      {:ok, invitation} =
        Wallets.create_invitation(owner, wallet, %{email: "paul@test.com"})

      # Invitee declines
      {:ok, _} = Wallets.decline_invitation(invitee, invitation.id)

      # Owner views edit page
      conn = authenticate_user(conn, owner)
      {:ok, edit_view, _html} = live(conn, ~p"/wallets/#{wallet.id}/edit")

      assert render(edit_view) =~ "Paul Refus"
      assert render(edit_view) =~ "Refusée"
      assert has_element?(edit_view, "#cancel-invitation-btn-#{invitation.id}")

      # Owner views show page
      {:ok, show_view, _html} = live(conn, ~p"/wallets/#{wallet.id}")
      assert render(show_view) =~ "Paul Refus"
      assert render(show_view) =~ "Refusée"
    end

    test "la cloche de notification affiche le nombre d'invitations reçues dans la navbar", %{
      conn: conn
    } do
      owner = create_user(%{name: "Amis Groupe"})
      user = create_user(%{name: "Receveur Notif", email: "notif@test.com"})
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "Anniversaire"})

      {:ok, _invitation} =
        Wallets.create_invitation(owner, wallet, %{email: "notif@test.com"})

      conn = authenticate_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/wallets")

      # Presence of notification bell and badge
      assert has_element?(view, "#notifications-bell-btn")
      assert has_element?(view, "#notifications-count-badge")
      assert element(view, "#notifications-count-badge") |> render() =~ "1"

      # Dropdown menu content
      assert has_element?(view, "#notifications-dropdown-menu")
      assert render(view) =~ "Anniversaire"
      assert render(view) =~ "Amis Groupe"
    end
  end

  describe "Affichage des comptes à rembourser et gestion des états vides (IF - Comptes créditeurs)" do
    test "affiche la liste des comptes à rembourser et les montants exacts quand des dépenses existent",
         %{conn: conn} do
      owner = create_user(%{name: "Alice", email: "alice_cred@test.com"})
      bob = create_user(%{name: "Bob", email: "bob_cred@test.com"})

      {:ok, wallet} =
        Wallets.create_wallet(owner, %{name: "Vacances Ski", currency: "EUR"}, [
          %{name: "Bob", email: bob.email, user_id: bob.id}
        ])

      # Alice pays €100, Bob pays €0. Total = €100, share = €50 -> Alice should receive €50
      {:ok, _expense} =
        Expenses.create_expense(owner, wallet, %{
          title: "Forfaits ski",
          amount: "100.00"
        })

      conn = authenticate_user(conn, owner)
      {:ok, view, _html} = live(conn, ~p"/wallets/#{wallet.id}")

      # Verify settlements section
      assert has_element?(view, "#wallet-creditors-section")
      assert has_element?(view, "#wallet-creditors-list")
      assert has_element?(view, "#creditors-count-badge", "1 bénéficiaire(s)")
      refute has_element?(view, "#no-creditors-message")

      # Alice must be listed with net amount to receive
      alice_member = Enum.find(wallet.members, &(&1.name == "Alice"))
      assert has_element?(view, "#creditor-item-#{alice_member.id}")
      assert element(view, "#creditor-item-#{alice_member.id}") |> render() =~ "Alice"
      assert element(view, "#creditor-item-#{alice_member.id}") |> render() =~ "+ 50.00 EUR"
      assert element(view, "#creditor-item-#{alice_member.id}") |> render() =~ "A payé 100.00 EUR"

      assert element(view, "#creditor-item-#{alice_member.id}") |> render() =~
               "Part due : 50.00 EUR"

      # Bob is debtor, must not be displayed in accounts to reimburse
      bob_member = Enum.find(wallet.members, &(&1.name == "Bob"))
      refute has_element?(view, "#creditor-item-#{bob_member.id}")
    end

    test "affiche un état vide informatif quand aucune dépense n'est enregistrée", %{conn: conn} do
      owner = create_user(%{name: "Alice", email: "alice_empty@test.com"})
      bob = create_user(%{name: "Bob", email: "bob_empty@test.com"})

      {:ok, wallet} =
        Wallets.create_wallet(owner, %{name: "Voyage Vide", currency: "EUR"}, [
          %{name: "Bob", email: bob.email, user_id: bob.id}
        ])

      conn = authenticate_user(conn, owner)
      {:ok, view, _html} = live(conn, ~p"/wallets/#{wallet.id}")

      assert has_element?(view, "#wallet-creditors-section")
      assert has_element?(view, "#no-creditors-message")
      assert has_element?(view, "#no-creditors-message", "Aucun remboursement en attente")
      assert render(view) =~ "Ajoutez des dépenses au groupe"
      refute has_element?(view, "#wallet-creditors-list")
    end

    test "affiche un état vide équilibré quand chaque membre a payé sa part exacte", %{conn: conn} do
      owner = create_user(%{name: "Alice", email: "alice_eq@test.com"})
      bob = create_user(%{name: "Bob", email: "bob_eq@test.com"})

      {:ok, wallet} =
        Wallets.create_wallet(owner, %{name: "Dépenses Égales", currency: "EUR"}, [
          %{name: "Bob", email: bob.email, user_id: bob.id}
        ])

      {:ok, _e1} =
        Expenses.create_expense(owner, wallet, %{title: "Repas 1", amount: "40.00"})

      {:ok, _e2} =
        Expenses.create_expense(bob, wallet, %{title: "Repas 2", amount: "40.00"})

      conn = authenticate_user(conn, owner)
      {:ok, view, _html} = live(conn, ~p"/wallets/#{wallet.id}")

      assert has_element?(view, "#wallet-creditors-section")
      assert has_element?(view, "#no-creditors-message")
      assert has_element?(view, "#no-creditors-message", "Les comptes sont équilibrés !")
      assert render(view) =~ "Chaque participant a payé exactement sa part"
      refute has_element?(view, "#wallet-creditors-list")
    end

    test "redirige vers /wallets avec un message d'erreur si le porte-monnaie est introuvable", %{
      conn: conn
    } do
      user = create_user()
      conn = authenticate_user(conn, user)

      # Non-existent identifier
      assert {:error, {:live_redirect, %{to: "/wallets", flash: %{"error" => msg}}}} =
               live(conn, ~p"/wallets/999999")

      assert msg =~ "n'existe pas ou est introuvable"
    end
  end

  describe "Virements proposés et remboursement mock (IF-84)" do
    test "affiche la section des virements proposés avec le flux et le montant exact", %{
      conn: conn
    } do
      owner = create_user(%{name: "Alice", email: "alice_virement@test.com"})
      bob = create_user(%{name: "Bob", email: "bob_virement@test.com"})

      {:ok, wallet} =
        Wallets.create_wallet(owner, %{name: "Vacances Barcelone", currency: "EUR"}, [
          %{name: "Bob", email: bob.email, user_id: bob.id}
        ])

      # Alice fronts €100, Bob €0. Share = €50 each. Bob owes €50 to Alice.
      {:ok, _} =
        Expenses.create_expense(owner, wallet, %{
          title: "Hôtel",
          amount: "100.00"
        })

      conn = authenticate_user(conn, owner)
      {:ok, view, _html} = live(conn, ~p"/wallets/#{wallet.id}")

      # Verify proposed settlements section
      assert has_element?(view, "#wallet-settlements-section")
      assert has_element?(view, "#wallet-settlements-list")
      assert has_element?(view, "#settlements-count-badge", "1 virement(s)")
      refute has_element?(view, "#no-settlements-message")

      alice_member = Enum.find(wallet.members, &(&1.name == "Alice"))
      bob_member = Enum.find(wallet.members, &(&1.name == "Bob"))

      item_id = "#settlement-item-#{bob_member.id}-#{alice_member.id}"
      assert has_element?(view, item_id)
      rendered_item = element(view, item_id) |> render()
      assert rendered_item =~ "Bob"
      assert rendered_item =~ "Alice"
      assert rendered_item =~ "doit donner"
      assert rendered_item =~ "50.00 EUR"
      assert rendered_item =~ "Virement conseillé"

      # Button is not displayed while wallet is open (Step 1)
      refute has_element?(view, "#mock-settle-btn-#{bob_member.id}-#{alice_member.id}")

      # Once validated (Step 2), creditor (Alice) does not see button
      {:ok, _} = Wallets.validate_wallet(owner, wallet)
      {:ok, view_stage2, _html} = live(conn, ~p"/wallets/#{wallet.id}")
      refute has_element?(view_stage2, "#mock-settle-btn-#{bob_member.id}-#{alice_member.id}")

      # Debtor (Bob) sees settlement button
      bob_conn = authenticate_user(Phoenix.ConnTest.build_conn(), bob)
      {:ok, bob_view, _html} = live(bob_conn, ~p"/wallets/#{wallet.id}")
      assert has_element?(bob_view, "#mock-settle-btn-#{bob_member.id}-#{alice_member.id}")

      assert element(bob_view, "#mock-settle-btn-#{bob_member.id}-#{alice_member.id}") |> render() =~
               "Marquer comme réglé"
    end

    test "affiche un état vide informatif quand aucune dépense n'existe", %{conn: conn} do
      owner = create_user(%{name: "Alice", email: "alice_vide@test.com"})
      bob = create_user(%{name: "Bob", email: "bob_vide@test.com"})

      {:ok, wallet} =
        Wallets.create_wallet(owner, %{name: "Porte-monnaie Vide", currency: "EUR"}, [
          %{name: "Bob", email: bob.email, user_id: bob.id}
        ])

      conn = authenticate_user(conn, owner)
      {:ok, view, _html} = live(conn, ~p"/wallets/#{wallet.id}")

      assert has_element?(view, "#wallet-settlements-section")
      assert has_element?(view, "#no-settlements-message")
      assert render(view) =~ "Aucun virement nécessaire"
      assert render(view) =~ "Ajoutez des dépenses au groupe"
      refute has_element?(view, "#wallet-settlements-list")
    end

    test "affiche un état vide équilibré quand les dépenses sont réparties également", %{
      conn: conn
    } do
      owner = create_user(%{name: "Alice", email: "alice_equilibre@test.com"})
      bob = create_user(%{name: "Bob", email: "bob_equilibre@test.com"})

      {:ok, wallet} =
        Wallets.create_wallet(owner, %{name: "Équilibré", currency: "EUR"}, [
          %{name: "Bob", email: bob.email, user_id: bob.id}
        ])

      {:ok, _} =
        Expenses.create_expense(owner, wallet, %{title: "Repas Alice", amount: "60.00"})

      {:ok, _} =
        Expenses.create_expense(bob, wallet, %{title: "Repas Bob", amount: "60.00"})

      conn = authenticate_user(conn, owner)
      {:ok, view, _html} = live(conn, ~p"/wallets/#{wallet.id}")

      assert has_element?(view, "#wallet-settlements-section")
      assert has_element?(view, "#no-settlements-message")
      assert render(view) =~ "Les comptes sont parfaitement équilibrés !"
      refute has_element?(view, "#wallet-settlements-list")
    end

    test "cycle complet en 3 étapes : déclarations (étape 1), validation et virements réglés (étape 2), puis clôture (étape 3)",
         %{conn: conn} do
      owner = create_user(%{name: "Alice", email: "alice_ski@test.com"})
      bob = create_user(%{name: "Bob", email: "bob_ski@test.com"})

      {:ok, wallet} =
        Wallets.create_wallet(owner, %{name: "Weekend Ski", currency: "EUR"}, [
          %{name: "Bob", email: bob.email, user_id: bob.id}
        ])

      {:ok, _} =
        Expenses.create_expense(owner, wallet, %{title: "Location chalet", amount: "120.00"})

      conn = authenticate_user(conn, owner)
      {:ok, view, _html} = live(conn, ~p"/wallets/#{wallet.id}")

      alice_member = Enum.find(wallet.members, &(&1.name == "Alice"))
      bob_member = Enum.find(wallet.members, &(&1.name == "Bob"))

      btn_id = "#mock-settle-btn-#{bob_member.id}-#{alice_member.id}"
      badge_id = "#mock-settled-badge-#{bob_member.id}-#{alice_member.id}"

      # -----------------------------------------------------------------------
      # STEP 1: Declarations in progress (Open status)
      # -----------------------------------------------------------------------
      assert has_element?(view, "#wallet-status-badge", "Ouvert")
      assert has_element?(view, "#wallet-lifecycle-stepper")
      assert has_element?(view, "#wallet-open-notice")
      assert has_element?(view, "#validate-wallet-btn")
      assert has_element?(view, "#add-expense-btn")
      assert has_element?(view, "#settlements-summary")

      assert element(view, "#settlement-progress-badge") |> render() =~
               "0 / 1 virement(s) réglé(s)"

      # Requirement 1: No settlement button displayed when wallet is open
      refute has_element?(view, btn_id)
      refute has_element?(view, badge_id)

      # Requirement 2: No word "simul" in the interface
      refute render(view) =~ "simul"
      assert render(view) =~ "Répartition des remboursements"
      assert render(view) =~ "Restant à régler"

      # -----------------------------------------------------------------------
      # TRANSITION: Wallet validation by owner -> Step 2
      # -----------------------------------------------------------------------
      view |> element("#validate-wallet-btn") |> render_click()

      assert render(view) =~ "Le porte-monnaie « Weekend Ski » a été validé."
      assert has_element?(view, "#wallet-status-badge", "Attente des virements")
      refute has_element?(view, "#wallet-open-notice")
      refute has_element?(view, "#add-expense-btn")

      # -----------------------------------------------------------------------
      # STEP 2: Awaiting bank transfers (settlement buttons appear)
      # -----------------------------------------------------------------------
      # Before any settlement: reopen button is present and no close button exists
      assert has_element?(view, "#reopen-wallet-btn")
      refute has_element?(view, "#close-wallet-btn")

      # Alice (creditor) cannot settle the transfer
      refute has_element?(view, btn_id)

      # Bob (debtor) logs in and sees the button
      bob_conn = authenticate_user(Phoenix.ConnTest.build_conn(), bob)
      {:ok, bob_view, _html} = live(bob_conn, ~p"/wallets/#{wallet.id}")
      assert has_element?(bob_view, btn_id)
      assert element(bob_view, btn_id) |> render() =~ "Marquer comme réglé"

      # Bob clicks "Marquer comme réglé"
      bob_view |> element(btn_id) |> render_click()

      # Final automatic closure flash notification received by Bob
      assert render(bob_view) =~ "Dernier virement de 60.00 EUR de Bob vers Alice réglé !"
      assert render(bob_view) =~ "le porte-monnaie est désormais clôturé définitivement."

      # Button disappeared and is replaced by "Réglé" badge
      refute has_element?(bob_view, btn_id)
      assert has_element?(bob_view, badge_id)
      assert element(bob_view, badge_id) |> render() =~ "Réglé"
      refute element(bob_view, badge_id) |> render() =~ "Simulation"

      # Settlement distribution is updated (100% settled)
      assert element(bob_view, "#settlement-progress-badge") |> render() =~
               "1 / 1 virement(s) réglé(s)"

      assert element(bob_view, "#summary-settled-amount") |> render() =~ "60.00 EUR"
      assert element(bob_view, "#summary-remaining-amount") |> render() =~ "0.00 EUR"
      assert has_element?(bob_view, "#all-settlements-completed-message")
      assert render(bob_view) =~ "Tous les remboursements ont été effectués avec succès !"
      assert render(bob_view) =~ "Le porte-monnaie est désormais définitivement clôturé"

      # Real-time PubSub synchronization on Alice's view
      assert has_element?(view, badge_id)

      assert element(view, "#settlement-progress-badge") |> render() =~
               "1 / 1 virement(s) réglé(s)"

      # -----------------------------------------------------------------------
      # STEP 3: Automatic closure and strict irreversibility
      # -----------------------------------------------------------------------
      # Wallet automatically transitioned to Closed status
      assert has_element?(view, "#wallet-status-badge", "Clos")
      assert Wallets.get_wallet!(wallet.id).status == "closed"

      # No manual close, reset, or reopen button exists
      refute has_element?(view, "#close-wallet-btn")
      refute has_element?(view, "#reset-mock-settlements-btn")
      refute has_element?(view, "#reopen-wallet-btn")

      # Reopen attempt impossible
      render_click(view, "reopen_wallet", %{})
      assert render(view) =~ "La clôture de ce porte-monnaie est définitive."
    end

    test "la réouverture en Étape 2 est autorisée tant qu'aucun virement n'a été effectué, puis devient impossible dès qu'un virement a été fait",
         %{conn: conn} do
      owner = create_user(%{name: "Alice", email: "alice_reopen_test@test.com"})
      bob = create_user(%{name: "Bob", email: "bob_reopen_test@test.com"})
      charlie = create_user(%{name: "Charlie", email: "charlie_reopen_test@test.com"})

      {:ok, wallet} =
        Wallets.create_wallet(owner, %{name: "Test Irréversibilité", currency: "EUR"}, [
          %{name: "Bob", email: bob.email, user_id: bob.id},
          %{name: "Charlie", email: charlie.email, user_id: charlie.id}
        ])

      # Alice pays €90 -> Bob owes €30 and Charlie owes €30
      {:ok, _} = Expenses.create_expense(owner, wallet, %{title: "Repas commun", amount: "90.00"})

      conn = authenticate_user(conn, owner)
      {:ok, view, _html} = live(conn, ~p"/wallets/#{wallet.id}")

      # Validation by owner -> Step 2
      view |> element("#validate-wallet-btn") |> render_click()
      assert has_element?(view, "#wallet-status-badge", "Attente des virements")

      # Before any transfer: reopen button is present
      assert has_element?(view, "#reopen-wallet-btn")

      # Perform 1 of 2 transfers (Bob settles to Alice)
      bob_member = Enum.find(wallet.members, &(&1.name == "Bob"))
      alice_member = Enum.find(wallet.members, &(&1.name == "Alice"))
      charlie_member = Enum.find(wallet.members, &(&1.name == "Charlie"))

      bob_btn = "#mock-settle-btn-#{bob_member.id}-#{alice_member.id}"
      charlie_btn = "#mock-settle-btn-#{charlie_member.id}-#{alice_member.id}"

      # Bob performs his transfer
      bob_conn = authenticate_user(Phoenix.ConnTest.build_conn(), bob)
      {:ok, bob_view, _html} = live(bob_conn, ~p"/wallets/#{wallet.id}")
      bob_view |> element(bob_btn) |> render_click()

      # After a first transfer: transfer is permanent, reopen disappears from UI for Alice
      refute has_element?(view, "#reopen-wallet-btn")

      # Any attempt to send reopen event is rejected
      render_click(view, "reopen_wallet", %{})

      assert render(view) =~
               "Impossible d&#39;annuler la validation : des virements ont déjà été effectués et sont définitifs."

      # Second transfer performed by Charlie -> Automatic closure!
      charlie_conn = authenticate_user(Phoenix.ConnTest.build_conn(), charlie)
      {:ok, charlie_view, _html} = live(charlie_conn, ~p"/wallets/#{wallet.id}")
      charlie_view |> element(charlie_btn) |> render_click()

      assert has_element?(view, "#wallet-status-badge", "Clos")
      assert Wallets.get_wallet!(wallet.id).status == "closed"
      refute has_element?(view, "#reopen-wallet-btn")
      refute has_element?(view, "#close-wallet-btn")
    end

    test "un membre non propriétaire ne voit pas les boutons pour valider, clore ou rouvrir le porte-monnaie",
         %{conn: conn} do
      owner = create_user(%{name: "Alice", email: "alice_non_owner@test.com"})
      bob = create_user(%{name: "Bob", email: "bob_non_owner@test.com"})

      {:ok, wallet} =
        Wallets.create_wallet(owner, %{name: "Groupe Amis", currency: "EUR"}, [
          %{name: "Bob", email: bob.email, user_id: bob.id}
        ])

      conn = authenticate_user(conn, bob)
      {:ok, view, _html} = live(conn, ~p"/wallets/#{wallet.id}")

      refute has_element?(view, "#validate-wallet-btn")
      refute has_element?(view, "#close-wallet-btn")
      refute has_element?(view, "#reopen-wallet-btn")
      refute has_element?(view, "#notice-validate-wallet-btn")
      refute has_element?(view, "#notice-close-wallet-btn")
    end
  end

  describe "Affichage des comptes qui doivent donner de l'argent et gestion des états vides (IF - Comptes débiteurs)" do
    test "affiche la liste des comptes débiteurs et les montants exacts quand des dépenses existent",
         %{conn: conn} do
      owner = create_user(%{name: "Alice", email: "alice_deb@test.com"})
      bob = create_user(%{name: "Bob", email: "bob_deb@test.com"})

      {:ok, wallet} =
        Wallets.create_wallet(owner, %{name: "Vacances Espagne", currency: "EUR"}, [
          %{name: "Bob", email: bob.email, user_id: bob.id}
        ])

      # Alice pays €100, Bob pays €0. Total = €100, share = €50 -> Bob must pay €50
      {:ok, _expense} =
        Expenses.create_expense(owner, wallet, %{
          title: "Location voiture",
          amount: "100.00"
        })

      conn = authenticate_user(conn, owner)
      {:ok, view, _html} = live(conn, ~p"/wallets/#{wallet.id}")

      # Verify debtor accounts section
      assert has_element?(view, "#wallet-debtors-section")
      assert has_element?(view, "#wallet-debtors-list")
      assert has_element?(view, "#debtors-count-badge", "1 débiteur(s)")
      refute has_element?(view, "#no-debtors-message")

      # Bob must be listed with net amount to pay
      bob_member = Enum.find(wallet.members, &(&1.name == "Bob"))
      assert has_element?(view, "#debtor-item-#{bob_member.id}")
      assert element(view, "#debtor-item-#{bob_member.id}") |> render() =~ "Bob"
      assert element(view, "#debtor-item-#{bob_member.id}") |> render() =~ "- 50.00 EUR"
      assert element(view, "#debtor-item-#{bob_member.id}") |> render() =~ "A payé 0.00 EUR"
      assert element(view, "#debtor-item-#{bob_member.id}") |> render() =~ "Part due : 50.00 EUR"
      assert element(view, "#debtor-item-#{bob_member.id}") |> render() =~ "À régler"

      # Alice is creditor, must not be displayed in debtor accounts
      alice_member = Enum.find(wallet.members, &(&1.name == "Alice"))
      refute has_element?(view, "#debtor-item-#{alice_member.id}")
    end

    test "affiche un état vide informatif quand aucune dépense n'est enregistrée", %{conn: conn} do
      owner = create_user(%{name: "Alice", email: "alice_deb_empty@test.com"})
      bob = create_user(%{name: "Bob", email: "bob_deb_empty@test.com"})

      {:ok, wallet} =
        Wallets.create_wallet(owner, %{name: "Voyage Vide Débiteur", currency: "EUR"}, [
          %{name: "Bob", email: bob.email, user_id: bob.id}
        ])

      conn = authenticate_user(conn, owner)
      {:ok, view, _html} = live(conn, ~p"/wallets/#{wallet.id}")

      assert has_element?(view, "#wallet-debtors-section")
      assert has_element?(view, "#no-debtors-message")
      assert has_element?(view, "#no-debtors-message", "Aucun montant à régler")
      assert render(view) =~ "Ajoutez des dépenses au groupe"
      refute has_element?(view, "#wallet-debtors-list")
      refute has_element?(view, "#debtors-count-badge")
    end

    test "affiche un état vide équilibré quand chaque membre a payé sa part exacte", %{conn: conn} do
      owner = create_user(%{name: "Alice", email: "alice_deb_eq@test.com"})
      bob = create_user(%{name: "Bob", email: "bob_deb_eq@test.com"})

      {:ok, wallet} =
        Wallets.create_wallet(owner, %{name: "Équilibre Débiteur", currency: "EUR"}, [
          %{name: "Bob", email: bob.email, user_id: bob.id}
        ])

      {:ok, _e1} =
        Expenses.create_expense(owner, wallet, %{title: "Courses", amount: "50.00"})

      {:ok, _e2} =
        Expenses.create_expense(bob, wallet, %{title: "Carburant", amount: "50.00"})

      conn = authenticate_user(conn, owner)
      {:ok, view, _html} = live(conn, ~p"/wallets/#{wallet.id}")

      assert has_element?(view, "#wallet-debtors-section")
      assert has_element?(view, "#no-debtors-message")
      assert has_element?(view, "#no-debtors-message", "Les comptes sont équilibrés !")
      assert render(view) =~ "Chaque participant a payé sa part exacte"
      refute has_element?(view, "#wallet-debtors-list")
    end

    test "affiche plusieurs comptes débiteurs triés par montant à payer décroissant", %{
      conn: conn
    } do
      owner = create_user(%{name: "Alice", email: "alice_multi_deb@test.com"})
      bob = create_user(%{name: "Bob", email: "bob_multi_deb@test.com"})
      charlie = create_user(%{name: "Charlie", email: "charlie_multi_deb@test.com"})

      {:ok, wallet} =
        Wallets.create_wallet(owner, %{name: "Multi Débiteurs", currency: "EUR"}, [
          %{name: "Bob", email: bob.email, user_id: bob.id},
          %{name: "Charlie", email: charlie.email, user_id: charlie.id}
        ])

      # Alice pays €90, Bob pays €30, Charlie pays €0. Total = €120, share = €40 each
      # Charlie owes €40, Bob owes €10, Alice is creditor of €50
      {:ok, _e1} =
        Expenses.create_expense(owner, wallet, %{title: "Hébergement", amount: "90.00"})

      {:ok, _e2} =
        Expenses.create_expense(bob, wallet, %{title: "Repas", amount: "30.00"})

      conn = authenticate_user(conn, owner)
      {:ok, view, _html} = live(conn, ~p"/wallets/#{wallet.id}")

      assert has_element?(view, "#debtors-count-badge", "2 débiteur(s)")

      bob_member = Enum.find(wallet.members, &(&1.name == "Bob"))
      charlie_member = Enum.find(wallet.members, &(&1.name == "Charlie"))

      assert has_element?(view, "#debtor-item-#{charlie_member.id}")
      assert element(view, "#debtor-item-#{charlie_member.id}") |> render() =~ "- 40.00 EUR"

      assert has_element?(view, "#debtor-item-#{bob_member.id}")
      assert element(view, "#debtor-item-#{bob_member.id}") |> render() =~ "- 10.00 EUR"
    end
  end

  describe "Epic: Lister les portes-monnaies invités & US associées" do
    test "affichage de la liste des portes-monnaies invités via l'onglet dédié et URL directe", %{
      conn: conn
    } do
      owner = create_user(%{name: "Marc Organisateur"})
      invitee = create_user(%{name: "Sophie Invitee", email: "sophie@test.com"})

      {:ok, wallet1} = Wallets.create_wallet(owner, %{name: "Weekend Londres", currency: "GBP"})
      {:ok, wallet2} = Wallets.create_wallet(owner, %{name: "Coloc Lille", currency: "EUR"})

      {:ok, inv1} = Wallets.create_invitation(owner, wallet1, %{email: invitee.email})
      {:ok, _inv2} = Wallets.create_invitation(owner, wallet2, %{email: invitee.email})

      conn = authenticate_user(conn, invitee)

      # 1. Navigation from /wallets by clicking "Portes-monnaies invités" tab
      {:ok, view, _html} = live(conn, ~p"/wallets")
      assert has_element?(view, "#tab-invited-wallets")

      view
      |> element("#tab-invited-wallets")
      |> render_click()

      assert has_element?(view, "#invited-wallets-section")
      assert has_element?(view, "#invited-wallets-grid")
      assert has_element?(view, "#invited-wallet-card-#{wallet1.id}")
      assert has_element?(view, "#invited-wallet-card-#{wallet2.id}")
      assert render(view) =~ "Weekend Londres"
      assert render(view) =~ "Marc Organisateur"

      # 2. Direct access via /wallets/invited
      {:ok, view_direct, _html} = live(conn, ~p"/wallets/invited")
      assert has_element?(view_direct, "#invited-wallets-section")
      assert has_element?(view_direct, "#invited-wallet-card-#{wallet1.id}")

      # 3. Accept invitation from card
      view_direct
      |> element("#accept-invited-wallet-btn-#{inv1.id}")
      |> render_click()

      assert render(view_direct) =~ "Vous avez rejoint le porte-monnaie avec succès"
      assert has_element?(view_direct, "#view-invited-wallet-btn-#{wallet1.id}")
    end

    test "filtrage interactif des portes-monnaies par statut d'invitation", %{conn: conn} do
      owner = create_user(%{name: "Organisateur Filtre"})
      invitee = create_user(%{name: "Testeur Filtres", email: "filtres@test.com"})

      {:ok, w_pending} = Wallets.create_wallet(owner, %{name: "Porte-monnaie En Attente"})
      {:ok, w_accepted} = Wallets.create_wallet(owner, %{name: "Porte-monnaie Accepté"})
      {:ok, w_declined} = Wallets.create_wallet(owner, %{name: "Porte-monnaie Refusé"})

      {:ok, _inv1} = Wallets.create_invitation(owner, w_pending, %{email: invitee.email})

      {:ok, inv2} = Wallets.create_invitation(owner, w_accepted, %{email: invitee.email})
      {:ok, _} = Wallets.accept_invitation(invitee, inv2.id)

      {:ok, inv3} = Wallets.create_invitation(owner, w_declined, %{email: invitee.email})
      {:ok, _} = Wallets.decline_invitation(invitee, inv3.id)

      conn = authenticate_user(conn, invitee)
      {:ok, view, _html} = live(conn, ~p"/wallets/invited")

      # All invitations are displayed (3)
      assert has_element?(view, "#invited-wallet-card-#{w_pending.id}")
      assert has_element?(view, "#invited-wallet-card-#{w_accepted.id}")
      assert has_element?(view, "#invited-wallet-card-#{w_declined.id}")

      # Filter by "pending"
      view
      |> element("#filter-status-pending")
      |> render_click()

      assert has_element?(view, "#invited-wallet-card-#{w_pending.id}")
      refute has_element?(view, "#invited-wallet-card-#{w_accepted.id}")
      refute has_element?(view, "#invited-wallet-card-#{w_declined.id}")

      # Filter by "accepted"
      view
      |> element("#filter-status-accepted")
      |> render_click()

      refute has_element?(view, "#invited-wallet-card-#{w_pending.id}")
      assert has_element?(view, "#invited-wallet-card-#{w_accepted.id}")
      refute has_element?(view, "#invited-wallet-card-#{w_declined.id}")

      # Filter by "declined"
      view
      |> element("#filter-status-declined")
      |> render_click()

      refute has_element?(view, "#invited-wallet-card-#{w_pending.id}")
      refute has_element?(view, "#invited-wallet-card-#{w_accepted.id}")
      assert has_element?(view, "#invited-wallet-card-#{w_declined.id}")

      # Return to "all"
      view
      |> element("#filter-status-all")
      |> render_click()

      assert has_element?(view, "#invited-wallet-card-#{w_pending.id}")
      assert has_element?(view, "#invited-wallet-card-#{w_accepted.id}")
      assert has_element?(view, "#invited-wallet-card-#{w_declined.id}")
    end

    test "gestion des états vides et réinitialisation des filtres", %{conn: conn} do
      user = create_user(%{name: "Isolé", email: "isole@test.com"})
      conn = authenticate_user(conn, user)

      # 1. No invited wallets
      {:ok, view, _html} = live(conn, ~p"/wallets/invited")
      assert has_element?(view, "#empty-invited-wallets-state")
      assert render(view) =~ "Aucun porte-monnaie invité pour le moment"

      # 2. User with a single pending invitation
      owner = create_user()
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "Groupe Seul"})
      {:ok, _inv} = Wallets.create_invitation(owner, wallet, %{email: user.email})

      {:ok, view2, _html} = live(conn, ~p"/wallets/invited")
      refute has_element?(view2, "#empty-invited-wallets-state")
      assert has_element?(view2, "#invited-wallet-card-#{wallet.id}")

      # When filtering by status without invitations ("declined"), empty state with reset button is displayed
      view2
      |> element("#filter-status-declined")
      |> render_click()

      assert has_element?(view2, "#empty-invited-wallets-state")
      assert render(view2) =~ "Aucune invitation correspondante"
      assert has_element?(view2, "#reset-filter-btn")

      # Click Reset filters
      view2
      |> element("#reset-filter-btn")
      |> render_click()

      assert has_element?(view2, "#invited-wallet-card-#{wallet.id}")
    end

    test "gestion de l'état d'erreur de chargement et bouton de réessai", %{conn: conn} do
      user = create_user(%{name: "Erreur User", email: "err_user@test.com"})
      owner = create_user()
      {:ok, wallet} = Wallets.create_wallet(owner, %{name: "Groupe Réseau"})
      {:ok, _inv} = Wallets.create_invitation(owner, wallet, %{email: user.email})

      conn = authenticate_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/wallets/invited")

      assert has_element?(view, "#invited-wallet-card-#{wallet.id}")

      # Trigger loading error
      render_hook(view, "simulate_loading_error", %{})

      assert has_element?(view, "#invited-wallets-error-state")
      assert render(view) =~ "Erreur de chargement des portes-monnaies invités"
      assert has_element?(view, "#retry-loading-btn")

      # Click Retry to recover from error
      view
      |> element("#retry-loading-btn")
      |> render_click()

      refute has_element?(view, "#invited-wallets-error-state")
      assert has_element?(view, "#invited-wallet-card-#{wallet.id}")
    end
  end

  describe "Epic: Lister les portes-monnaies ouverts & US associées" do
    test "affiche la liste des portes-monnaies ouverts avec filtrage", %{conn: conn} do
      user = create_user()
      {:ok, open_wallet} = Wallets.create_wallet(user, %{name: "Vacances Espagne"})
      {:ok, closed_wallet} = Wallets.create_wallet(user, %{name: "Ski 2025"})
      {:ok, _closed} = Wallets.close_wallet(user, closed_wallet)

      conn = authenticate_user(conn, user)

      # 1. Direct navigation via /wallets/open
      {:ok, view, _html} = live(conn, ~p"/wallets/open")

      assert has_element?(view, "#page-main-heading", "Portes-monnaies ouverts")
      assert has_element?(view, "#wallet-card-#{open_wallet.id}")
      assert has_element?(view, "#wallet-status-badge-#{open_wallet.id}")
      assert element(view, "#wallet-status-badge-#{open_wallet.id}") |> render() =~ "Ouvert"
      refute has_element?(view, "#wallet-card-#{closed_wallet.id}")

      # 2. Interactive filtering from /wallets via "Ouverts" filter button
      {:ok, index_view, _html} = live(conn, ~p"/wallets")
      assert has_element?(index_view, "#wallet-filter-open")

      index_view
      |> element("#wallet-filter-open")
      |> render_click()

      assert_patch(index_view, ~p"/wallets/open")
      assert has_element?(index_view, "#wallet-card-#{open_wallet.id}")
      refute has_element?(index_view, "#wallet-card-#{closed_wallet.id}")
    end

    test "gestion des états vides pour les portes-monnaies ouverts", %{conn: conn} do
      user = create_user()
      {:ok, closed_wallet} = Wallets.create_wallet(user, %{name: "Weekend Passé"})
      {:ok, _closed} = Wallets.close_wallet(user, closed_wallet)

      conn = authenticate_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/wallets/open")

      assert has_element?(view, "#empty-open-wallets-state")
      assert render(view) =~ "Aucun porte-monnaie ouvert pour le moment"
      assert has_element?(view, "#create-open-wallet-btn")
      assert has_element?(view, "#reset-open-wallet-filter-btn")

      # Click reset button
      view
      |> element("#reset-open-wallet-filter-btn")
      |> render_click()

      assert_patch(view, ~p"/wallets")
      assert has_element?(view, "#wallet-card-#{closed_wallet.id}")
    end

    test "gestion de l'erreur de chargement des portes-monnaies et réessai", %{conn: conn} do
      user = create_user()
      {:ok, wallet} = Wallets.create_wallet(user, %{name: "Projet Coloc"})

      conn = authenticate_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/wallets/open")

      assert has_element?(view, "#wallet-card-#{wallet.id}")

      # Error simulation
      render_hook(view, "simulate_wallets_error", %{})

      assert has_element?(view, "#wallets-error-state")
      assert render(view) =~ "Erreur de chargement des porte-monnaies"
      assert has_element?(view, "#retry-load-wallets-btn")
      refute has_element?(view, "#wallet-card-#{wallet.id}")

      # Retry
      view
      |> element("#retry-load-wallets-btn")
      |> render_click()

      refute has_element?(view, "#wallets-error-state")
      assert has_element?(view, "#wallet-card-#{wallet.id}")
    end
  end

  describe "Epic: Lister les portes-monnaies clos & US associées" do
    test "affiche la liste des portes-monnaies clos avec filtrage", %{conn: conn} do
      user = create_user()
      {:ok, open_wallet} = Wallets.create_wallet(user, %{name: "Compte Actif"})
      {:ok, closed_wallet} = Wallets.create_wallet(user, %{name: "Compte Terminé"})
      {:ok, _closed} = Wallets.close_wallet(user, closed_wallet)

      conn = authenticate_user(conn, user)

      # 1. Direct navigation via /wallets/closed
      {:ok, view, _html} = live(conn, ~p"/wallets/closed")

      assert has_element?(view, "#page-main-heading", "Portes-monnaies clos")
      assert has_element?(view, "#wallet-card-#{closed_wallet.id}")
      assert has_element?(view, "#wallet-status-badge-#{closed_wallet.id}")
      assert element(view, "#wallet-status-badge-#{closed_wallet.id}") |> render() =~ "Clos"
      refute has_element?(view, "#wallet-card-#{open_wallet.id}")

      # 2. Interactive filtering from /wallets via "Clos" filter button
      {:ok, index_view, _html} = live(conn, ~p"/wallets")
      assert has_element?(index_view, "#wallet-filter-closed")

      index_view
      |> element("#wallet-filter-closed")
      |> render_click()

      assert_patch(index_view, ~p"/wallets/closed")
      assert has_element?(index_view, "#wallet-card-#{closed_wallet.id}")
      refute has_element?(index_view, "#wallet-card-#{open_wallet.id}")
    end

    test "gestion des états vides pour les portes-monnaies clos", %{conn: conn} do
      user = create_user()
      {:ok, open_wallet} = Wallets.create_wallet(user, %{name: "Compte En Cours"})

      conn = authenticate_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/wallets/closed")

      assert has_element?(view, "#empty-closed-wallets-state")
      assert render(view) =~ "Aucun porte-monnaie clos pour le moment"
      assert has_element?(view, "#reset-closed-wallet-filter-btn")

      # Click reset button
      view
      |> element("#reset-closed-wallet-filter-btn")
      |> render_click()

      assert_patch(view, ~p"/wallets")
      assert has_element?(view, "#wallet-card-#{open_wallet.id}")
    end
  end
end
