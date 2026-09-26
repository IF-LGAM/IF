defmodule LesBonsComptesWeb.WalletLiveTest do
  use LesBonsComptesWeb.ConnCase
  import Phoenix.LiveViewTest

  alias LesBonsComptes.Accounts
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
      assert html =~ "Invitations en attente"
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
      assert render(edit_view) =~ "En attente"

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
  end
end
