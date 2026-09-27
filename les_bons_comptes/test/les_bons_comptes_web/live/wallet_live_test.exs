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

      # Vérification de la présence des champs du formulaire (IF-33)
      assert has_element?(view, "#wallet-create-form")
      assert has_element?(view, "#wallet-name-input")
      assert has_element?(view, "#wallet-currency-select")
      assert has_element?(view, "#wallet-description-input")
      assert has_element?(view, "#submit-wallet-btn")

      # Vérification de l'initialisation du propriétaire (IF-36)
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

      # Validation en temps réel (phx-change)
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

      # 1. Ajout d'un utilisateur inscrit parmi les suggestions
      assert has_element?(view, "#add-user-btn-#{registered_friend.id}")

      view
      |> element("#add-user-btn-#{registered_friend.id}")
      |> render_click()

      assert render(view) =~ "Bob Inscription"
      assert render(view) =~ "Inscrit"
      refute render(view) =~ "Externe"

      # 2. Ajout manuel d'un participant inscrit par email
      view
      |> element("#add-custom-participant-btn")
      |> render_click(%{"email" => "charlie@email.com"})

      assert render(view) =~ "Charlie Amis"
      assert render(view) =~ "Inscrit"
      refute render(view) =~ "Externe"

      # 3. Retrait d'un participant
      view
      |> element("#participants-list > div:first-child button[phx-click='remove_participant']")
      |> render_click()

      # Il ne reste plus qu'un participant dans la liste des membres ajoutés
      refute has_element?(view, "#participants-list", "Bob Inscription")
      assert has_element?(view, "#participants-list", "Charlie Amis")
      # Et Bob est de nouveau disponible dans les suggestions
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

      # 1. Ajout de Bob
      view
      |> element("#add-user-btn-#{registered_friend.id}")
      |> render_click()

      assert has_element?(view, "#participants-list", "Bob Inscription")

      # 2. Saisie manuelle par email (simulation d'événements de saisie)
      view
      |> element("#custom-participant-email")
      |> render_keyup(%{"value" => "charlie_manuel@example.com"})

      # Bob est toujours présent après la saisie !
      assert has_element?(view, "#participants-list", "Bob Inscription")

      # 3. Clic sur Ajouter ce participant
      view
      |> element("#add-custom-participant-btn")
      |> render_click(%{"email" => "charlie_manuel@example.com"})

      # Les deux participants sont bien présents simultanément avec le badge Inscrit !
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

      # Email vide
      view
      |> element("#add-custom-participant-btn")
      |> render_click(%{"email" => ""})

      assert has_element?(view, "#participant-error-alert", "L'adresse email est obligatoire")

      # Email invalide
      view
      |> element("#add-custom-participant-btn")
      |> render_click(%{"email" => "pas_un_email"})

      assert has_element?(
               view,
               "#participant-error-alert",
               "Veuillez saisir une adresse email valide"
             )

      # Email non inscrit sur la plateforme
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

      # Ajout d'un ami via suggestions
      view
      |> element("#add-user-btn-#{friend.id}")
      |> render_click()

      # Ajout d'un ami inscrit par email manuellement
      view
      |> element("#add-custom-participant-btn")
      |> render_click(%{"email" => "marc@test.com"})

      # Soumission du formulaire (IF-31)
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

      # Suivre la redirection vers la page de confirmation (IF-34)
      {:ok, show_view, html} = live(conn, show_path)

      # Vérification de la confirmation et des informations affichées
      assert has_element?(show_view, "#wallet-name")
      assert element(show_view, "#wallet-name") |> render() =~ "Voyage à Rome"
      assert has_element?(show_view, "#wallet-currency-badge")
      assert element(show_view, "#wallet-currency-badge") |> render() =~ "EUR"
      assert has_element?(show_view, "#wallet-description")

      assert element(show_view, "#wallet-description") |> render() =~
               "Dépenses du voyage entre amis"

      # Vérification du propriétaire (IF-36)
      assert has_element?(show_view, "#owner-name")
      assert element(show_view, "#owner-name") |> render() =~ "Sophie"

      # Vérification des participants (IF-30, IF-37) :
      # Le créateur est le membre initial, Lucas et Marc ont reçu une invitation en attente d'acceptation
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

      # 1. Accès à la page d'édition
      {:ok, edit_view, _html} = live(conn, ~p"/wallets/#{wallet.id}/edit")

      assert has_element?(edit_view, "#wallet-edit-form")
      assert has_element?(edit_view, "#wallet-name-input")
      assert has_element?(edit_view, "#submit-edit-wallet-btn")

      # 2. Soumission des modifications
      {:error, {:live_redirect, %{to: show_path}}} =
        edit_view
        |> form("#wallet-edit-form",
          wallet: %{name: "Vacances Espagne 2026", currency: "USD", description: "Mise à jour"}
        )
        |> render_submit()

      assert show_path == ~p"/wallets/#{wallet.id}"

      # 3. Vérification de la mise à jour effective
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

      # Tentative d'accès à l'édition
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

      # Vue par le propriétaire
      owner_conn = authenticate_user(conn, owner)
      {:ok, owner_view, _html} = live(owner_conn, ~p"/wallets/#{wallet.id}")
      assert has_element?(owner_view, "#edit-wallet-btn")
      assert has_element?(owner_view, "#delete-wallet-btn")

      # Vue par le membre non-propriétaire
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

      # 1. Envoi d'une invitation à un utilisateur inscrit depuis les suggestions (IF-38, IF-40, IF-42, IF-43)
      assert has_element?(edit_view, "#add-user-btn-#{registered_user.id}")

      edit_view
      |> element("#add-user-btn-#{registered_user.id}")
      |> render_click()

      assert render(edit_view) =~ "Invitation envoyée avec succès à Inscrit Nouveau"
      assert has_element?(edit_view, "#pending-invitations-list")
      assert render(edit_view) =~ "Inscrit Nouveau"
      assert render(edit_view) =~ "Invitation envoyée"

      # 2. Envoi d'une invitation manuellement par email (IF-39)
      edit_view
      |> element("#add-custom-participant-btn")
      |> render_click(%{"email" => "manuel@test.com"})

      assert render(edit_view) =~ "Invitation envoyée avec succès à Ami Manuel"
      assert render(edit_view) =~ "Ami Manuel"

      # 3. Annulation d'une invitation en attente
      [invitation | _] = Wallets.list_pending_invitations_for_wallet(wallet.id)

      edit_view
      |> element("#cancel-invitation-btn-#{invitation.id}")
      |> render_click()

      assert render(edit_view) =~ "invitation a été annulée"

      # 4. Retrait d'un membre déjà actif
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
      # L'utilisateur ne fait plus partie des membres
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

      # 1. Vérification de l'affichage de l'invitation reçue (IF-44)
      assert has_element?(view, "#pending-invitations-section")
      assert has_element?(view, "#invitation-card-#{invitation.id}")
      assert render(view) =~ "Festival 2026"
      assert render(view) =~ "Organisateur"

      # 2. Clic sur Accepter (IF-44, IF-45)
      view
      |> element("#accept-invitation-btn-#{invitation.id}")
      |> render_click()

      assert render(view) =~ "Vous avez rejoint le porte-monnaie avec succès"
      refute has_element?(view, "#invitation-card-#{invitation.id}")

      # Le porte-monnaie apparaît désormais dans ses porte-monnaies
      assert has_element?(view, "#wallet-card-#{wallet.id}")
      assert render(view) =~ "Festival 2026"

      # L'utilisateur est bien enregistré en base comme membre du groupe (IF-45)
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

      # Clic sur Refuser
      view
      |> element("#decline-invitation-btn-#{invitation.id}")
      |> render_click()

      assert render(view) =~ "Vous avez refusé"
      refute has_element?(view, "#invitation-card-#{invitation.id}")
      refute has_element?(view, "#wallet-card-#{wallet.id}")

      # N'est pas ajouté comme membre
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

      # L'invité décline
      {:ok, _} = Wallets.decline_invitation(invitee, invitation.id)

      # Le propriétaire consulte la page d'édition
      conn = authenticate_user(conn, owner)
      {:ok, edit_view, _html} = live(conn, ~p"/wallets/#{wallet.id}/edit")

      assert render(edit_view) =~ "Paul Refus"
      assert render(edit_view) =~ "Refusée"
      assert has_element?(edit_view, "#cancel-invitation-btn-#{invitation.id}")

      # Le propriétaire consulte la page show
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

      # Présence de la cloche de notification et de son badge
      assert has_element?(view, "#notifications-bell-btn")
      assert has_element?(view, "#notifications-count-badge")
      assert element(view, "#notifications-count-badge") |> render() =~ "1"

      # Contenu du menu déroulant
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

      # Alice paie 100€, Bob paie 0€. Total = 100€, part = 50€ -> Alice doit recevoir 50€
      {:ok, _expense} =
        Expenses.create_expense(owner, wallet, %{
          title: "Forfaits ski",
          amount: "100.00"
        })

      conn = authenticate_user(conn, owner)
      {:ok, view, _html} = live(conn, ~p"/wallets/#{wallet.id}")

      # Vérification de la section des remboursements
      assert has_element?(view, "#wallet-creditors-section")
      assert has_element?(view, "#wallet-creditors-list")
      assert has_element?(view, "#creditors-count-badge", "1 bénéficiaire(s)")
      refute has_element?(view, "#no-creditors-message")

      # Alice doit être listée avec son montant net à recevoir
      alice_member = Enum.find(wallet.members, &(&1.name == "Alice"))
      assert has_element?(view, "#creditor-item-#{alice_member.id}")
      assert element(view, "#creditor-item-#{alice_member.id}") |> render() =~ "Alice"
      assert element(view, "#creditor-item-#{alice_member.id}") |> render() =~ "+ 50.00 EUR"
      assert element(view, "#creditor-item-#{alice_member.id}") |> render() =~ "A payé 100.00 EUR"
      assert element(view, "#creditor-item-#{alice_member.id}") |> render() =~ "Part due : 50.00 EUR"

      # Bob est débiteur, il ne doit pas être affiché dans les comptes à rembourser
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

      # Identifiant inexistant
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

      # Alice avance 100€, Bob 0€. Part = 50€ chacun. Bob doit 50€ à Alice.
      {:ok, _} =
        Expenses.create_expense(owner, wallet, %{
          title: "Hôtel",
          amount: "100.00"
        })

      conn = authenticate_user(conn, owner)
      {:ok, view, _html} = live(conn, ~p"/wallets/#{wallet.id}")

      # Vérification de la section des virements proposés
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

      # Le bouton n'est pas affiché tant que le porte-monnaie est ouvert (Étape 1)
      refute has_element?(view, "#mock-settle-btn-#{bob_member.id}-#{alice_member.id}")

      # Une fois validé (Étape 2), le créancier (Alice) ne voit pas le bouton
      {:ok, _} = Wallets.validate_wallet(owner, wallet)
      {:ok, view_stage2, _html} = live(conn, ~p"/wallets/#{wallet.id}")
      refute has_element?(view_stage2, "#mock-settle-btn-#{bob_member.id}-#{alice_member.id}")

      # Le débiteur (Bob) voit le bouton de règlement
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
      # ÉTAPE 1 : Déclarations en cours (statut Ouvert)
      # -----------------------------------------------------------------------
      assert has_element?(view, "#wallet-status-badge", "Ouvert")
      assert has_element?(view, "#wallet-lifecycle-stepper")
      assert has_element?(view, "#wallet-open-notice")
      assert has_element?(view, "#validate-wallet-btn")
      assert has_element?(view, "#add-expense-btn")
      assert has_element?(view, "#settlements-summary")
      assert element(view, "#settlement-progress-badge") |> render() =~ "0 / 1 virement(s) réglé(s)"

      # Exigence 1 : Aucun bouton de règlement n'est affiché quand le porte-monnaie est ouvert
      refute has_element?(view, btn_id)
      refute has_element?(view, badge_id)

      # Exigence 2 : Aucun mot "simul" dans l'interface
      refute render(view) =~ "simul"
      assert render(view) =~ "Répartition des remboursements"
      assert render(view) =~ "Restant à régler"

      # -----------------------------------------------------------------------
      # TRANSITION : Validation du porte-monnaie par le propriétaire -> Étape 2
      # -----------------------------------------------------------------------
      view |> element("#validate-wallet-btn") |> render_click()

      assert render(view) =~ "Le porte-monnaie « Weekend Ski » a été validé."
      assert has_element?(view, "#wallet-status-badge", "Attente des virements")
      refute has_element?(view, "#wallet-open-notice")
      refute has_element?(view, "#add-expense-btn")

      # -----------------------------------------------------------------------
      # ÉTAPE 2 : Attente des virements (les boutons de virement apparaissent)
      # -----------------------------------------------------------------------
      # Avant tout règlement : le bouton de réouverture est présent et aucun bouton clôturer n'existe
      assert has_element?(view, "#reopen-wallet-btn")
      refute has_element?(view, "#close-wallet-btn")

      # Alice (créancière) ne peut pas régler le virement
      refute has_element?(view, btn_id)

      # Bob (débiteur) se connecte et voit le bouton
      bob_conn = authenticate_user(Phoenix.ConnTest.build_conn(), bob)
      {:ok, bob_view, _html} = live(bob_conn, ~p"/wallets/#{wallet.id}")
      assert has_element?(bob_view, btn_id)
      assert element(bob_view, btn_id) |> render() =~ "Marquer comme réglé"

      # Bob clique sur "Marquer comme réglé"
      bob_view |> element(btn_id) |> render_click()

      # Notification flash de clôture automatique définitive reçue par Bob
      assert render(bob_view) =~ "Dernier virement de 60.00 EUR de Bob vers Alice réglé !"
      assert render(bob_view) =~ "le porte-monnaie est désormais clôturé définitivement."

      # Le bouton a disparu et est remplacé par le badge "Réglé"
      refute has_element?(bob_view, btn_id)
      assert has_element?(bob_view, badge_id)
      assert element(bob_view, badge_id) |> render() =~ "Réglé"
      refute element(bob_view, badge_id) |> render() =~ "Simulation"

      # La répartition des remboursements est mise à jour (100% réglé)
      assert element(bob_view, "#settlement-progress-badge") |> render() =~ "1 / 1 virement(s) réglé(s)"
      assert element(bob_view, "#summary-settled-amount") |> render() =~ "60.00 EUR"
      assert element(bob_view, "#summary-remaining-amount") |> render() =~ "0.00 EUR"
      assert has_element?(bob_view, "#all-settlements-completed-message")
      assert render(bob_view) =~ "Tous les remboursements ont été effectués avec succès !"
      assert render(bob_view) =~ "Le porte-monnaie est désormais définitivement clôturé"

      # Synchronisation PubSub en temps réel sur la vue d'Alice
      assert has_element?(view, badge_id)
      assert element(view, "#settlement-progress-badge") |> render() =~ "1 / 1 virement(s) réglé(s)"

      # -----------------------------------------------------------------------
      # ÉTAPE 3 : Clôture automatique et stricte irréversibilité
      # -----------------------------------------------------------------------
      # Le porte-monnaie est automatiquement passé au statut Clos
      assert has_element?(view, "#wallet-status-badge", "Clos")
      assert Wallets.get_wallet!(wallet.id).status == "closed"

      # Aucun bouton de clôture manuelle, de réinitialisation ni de réouverture n'existe
      refute has_element?(view, "#close-wallet-btn")
      refute has_element?(view, "#reset-mock-settlements-btn")
      refute has_element?(view, "#reopen-wallet-btn")

      # Tentative de réouverture impossible
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

      # Alice paie 90€ -> Bob doit 30€ et Charlie doit 30€
      {:ok, _} = Expenses.create_expense(owner, wallet, %{title: "Repas commun", amount: "90.00"})

      conn = authenticate_user(conn, owner)
      {:ok, view, _html} = live(conn, ~p"/wallets/#{wallet.id}")

      # Validation par le propriétaire -> Étape 2
      view |> element("#validate-wallet-btn") |> render_click()
      assert has_element?(view, "#wallet-status-badge", "Attente des virements")

      # Avant tout virement : le bouton de réouverture est présent
      assert has_element?(view, "#reopen-wallet-btn")

      # On effectue 1 virement sur 2 (Bob règle à Alice)
      bob_member = Enum.find(wallet.members, &(&1.name == "Bob"))
      alice_member = Enum.find(wallet.members, &(&1.name == "Alice"))
      charlie_member = Enum.find(wallet.members, &(&1.name == "Charlie"))

      bob_btn = "#mock-settle-btn-#{bob_member.id}-#{alice_member.id}"
      charlie_btn = "#mock-settle-btn-#{charlie_member.id}-#{alice_member.id}"

      # Bob effectue son virement
      bob_conn = authenticate_user(Phoenix.ConnTest.build_conn(), bob)
      {:ok, bob_view, _html} = live(bob_conn, ~p"/wallets/#{wallet.id}")
      bob_view |> element(bob_btn) |> render_click()

      # Après un premier virement : le virement est définitif, la réouverture disparaît de l'UI pour Alice
      refute has_element?(view, "#reopen-wallet-btn")

      # Toute tentative d'envoi de l'événement de réouverture est refusée
      render_click(view, "reopen_wallet", %{})
      assert render(view) =~ "Impossible d&#39;annuler la validation : des virements ont déjà été effectués et sont définitifs."

      # Le deuxième virement est effectué par Charlie -> Clôture automatique !
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

      # Alice paie 100€, Bob paie 0€. Total = 100€, part = 50€ -> Bob doit régler 50€
      {:ok, _expense} =
        Expenses.create_expense(owner, wallet, %{
          title: "Location voiture",
          amount: "100.00"
        })

      conn = authenticate_user(conn, owner)
      {:ok, view, _html} = live(conn, ~p"/wallets/#{wallet.id}")

      # Vérification de la section des comptes débiteurs
      assert has_element?(view, "#wallet-debtors-section")
      assert has_element?(view, "#wallet-debtors-list")
      assert has_element?(view, "#debtors-count-badge", "1 débiteur(s)")
      refute has_element?(view, "#no-debtors-message")

      # Bob doit être listé avec son montant net à payer
      bob_member = Enum.find(wallet.members, &(&1.name == "Bob"))
      assert has_element?(view, "#debtor-item-#{bob_member.id}")
      assert element(view, "#debtor-item-#{bob_member.id}") |> render() =~ "Bob"
      assert element(view, "#debtor-item-#{bob_member.id}") |> render() =~ "- 50.00 EUR"
      assert element(view, "#debtor-item-#{bob_member.id}") |> render() =~ "A payé 0.00 EUR"
      assert element(view, "#debtor-item-#{bob_member.id}") |> render() =~ "Part due : 50.00 EUR"
      assert element(view, "#debtor-item-#{bob_member.id}") |> render() =~ "À régler"

      # Alice est créditrice, elle ne doit pas être affichée dans les comptes débiteurs
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

    test "affiche plusieurs comptes débiteurs triés par montant à payer décroissant", %{conn: conn} do
      owner = create_user(%{name: "Alice", email: "alice_multi_deb@test.com"})
      bob = create_user(%{name: "Bob", email: "bob_multi_deb@test.com"})
      charlie = create_user(%{name: "Charlie", email: "charlie_multi_deb@test.com"})

      {:ok, wallet} =
        Wallets.create_wallet(owner, %{name: "Multi Débiteurs", currency: "EUR"}, [
          %{name: "Bob", email: bob.email, user_id: bob.id},
          %{name: "Charlie", email: charlie.email, user_id: charlie.id}
        ])

      # Alice paie 90€, Bob paie 30€, Charlie paie 0€. Total = 120€, part = 40€ chacun
      # Charlie doit 40€, Bob doit 10€, Alice est créditrice de 50€
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
end
