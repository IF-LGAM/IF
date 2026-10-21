defmodule LesBonsComptes.TpExpensesTest do
  @moduledoc """
  Suite de tests pédagogique pour le TP :
  « Découverte d'Elixir/Phoenix : CRUD des Dépenses & Pagination »

  IMPORTANT - BASE DE DONNÉES PARTAGÉE :
  Lors de ce TP, tous les étudiants peuvent être connectés à la même base de données.
  Grâce à `LesBonsComptes.DataCase` et à l'adaptateur `Ecto.Adapters.SQL.Sandbox`,
  chaque test s'exécute dans une transaction SQL isolée qui est AUTOMATIQUEMENT
  annulée (ROLLBACK) à la fin du test.
  Pour éviter toute collision de clés uniques (comme les adresses email), chaque
  utilisateur généré possède un identifiant unique aléatoire.
  """
  use LesBonsComptes.DataCase, async: false

  alias LesBonsComptes.Accounts
  alias LesBonsComptes.Expenses
  alias LesBonsComptes.Expenses.Expense
  alias LesBonsComptes.Wallets

  # ============================================================================
  # HELPERS DE TEST
  # Fonctions utilitaires pour créer rapidement des données de test isolées
  # ============================================================================

  defp create_user(attrs \\ %{}) do
    unique_id = System.unique_integer([:positive])

    default_attrs = %{
      name: "Étudiant #{unique_id}",
      email: "etudiant_#{unique_id}@tp-if.fr",
      password: "password123"
    }

    {:ok, user} = Accounts.create_user(Map.merge(default_attrs, attrs))
    user
  end

  defp setup_wallet_with_members do
    alice = create_user(%{name: "Alice"})
    bob = create_user(%{name: "Bob"})

    {:ok, wallet} =
      Wallets.create_wallet(alice, %{name: "Vacances TP", currency: "EUR"}, [
        %{name: "Bob", email: bob.email, user_id: bob.id}
      ])

    # wallet.members contient les membres avec leurs IDs respectifs
    %{alice: alice, bob: bob, wallet: wallet}
  end

  # ============================================================================
  # PARTIE 1 : DÉMONSTRATION — COMPRENDRE UN TEST EXUNIT (Ce test est déjà VERT)
  # ============================================================================

  describe "Partie 1 : Découverte d'ExUnit et de la base de données" do
    test "DÉMONSTRATION : structure d'un test, pattern matching et assert" do
      # 1. Mise en place (Setup) : création des données de test
      %{alice: _alice, bob: _bob, wallet: wallet} = setup_wallet_with_members()

      # 2. Assertions sur les données créées
      assert wallet.name == "Vacances TP"
      assert wallet.currency == "EUR"
      assert length(wallet.members) == 2

      # 3. Illustration du Pattern Matching dans une assertion
      # En Elixir, on peut déballer et vérifier simultanément la structure d'un résultat :
      assert %Wallets.Wallet{id: wallet_id} = wallet
      assert is_integer(wallet_id)

      # 4. Vérification que Bob est bien membre
      member_names = Enum.map(wallet.members, & &1.name)
      assert "Alice" in member_names
      assert "Bob" in member_names

      # À la fin de ce test, Ecto effectue automatiquement un ROLLBACK en base.
      # La base de données reste parfaitement propre pour les autres étudiants !
    end
  end

  # ============================================================================
  # PARTIE 2 : À VOUS D'ÉCRIRE UN TEST (TDD - Étape 1)
  # ============================================================================

  describe "Partie 2 : Votre premier test ExUnit à écrire" do
    test "EXERCICE : vérifier qu'une dépense avec un montant négatif est invalide" do
      # CONIGNE :
      # 1. Complétez ce test pour instancier un changeset avec un montant négatif (ex: "-15.00").
      # 2. Vérifiez avec `refute changeset.valid?` que le changeset est invalide.
      # 3. Vérifiez avec `errors_on(changeset)` que l'erreur sur le champ :amount est présente.

      _attrs_invalides = %{
        title: "Test négatif",
        amount: "-15.00",
        date: Date.utc_today(),
        wallet_id: 1,
        payer_id: 1
      }

      # =======================================================================
      # TODO ÉTUDIANT (À vous d'écrire votre premier test !)
      # -----------------------------------------------------------------------
      # 1. Créez le changeset avec `Expense.changeset(%Expense{}, attrs_invalides)`
      # 2. Vérifiez qu'il est invalide avec `refute changeset.valid?`
      # 3. Vérifiez que errors_on(changeset) contient une erreur sur :amount
      #
      # Une fois les 3 lignes écrites, commentez ou supprimez le flunk(...) ci-dessous.
      # =======================================================================
      flunk("👉 Étape 2 : À vous d'écrire les assertions de ce test dans test/les_bons_comptes/tp_expenses_test.exs (lignes 86-98) !")

      # changeset = Expense.changeset(%Expense{}, attrs_invalides)
      # refute changeset.valid?, "Le changeset devrait être invalide avec un montant négatif !"
      # errors = errors_on(changeset)
      # assert errors.amount != nil, "Le champ :amount devrait contenir un message d'erreur"
    end
  end

  # ============================================================================
  # PARTIE 3 : LE CRUD DES DÉPENSES (TDD - Étape 2)
  # ============================================================================

  describe "Partie 3 : Développer le CRUD des Dépenses" do
    test "3.1 - Validations du Changeset : titre et montant obligatoires" do
      # Une dépense vide ne doit pas être valide
      changeset = Expense.changeset(%Expense{}, %{})

      refute changeset.valid?
      errors = errors_on(changeset)

      assert "ce champ est obligatoire" in errors.title
      assert "ce champ est obligatoire" in errors.amount
    end

    test "3.2 - Création d'une dépense valide (Create)" do
      %{alice: alice, wallet: wallet} = setup_wallet_with_members()

      attrs = %{
        title: "Courses supermarché",
        amount: "54.20",
        description: "Pâtes, sauces et fruits",
        date: Date.utc_today()
      }

      assert {:ok, %Expense{} = expense} = Expenses.create_expense(alice, wallet, attrs)
      assert expense.title == "Courses supermarché"
      assert Decimal.equal?(expense.amount, Decimal.new("54.20"))
      assert expense.wallet_id == wallet.id
      assert expense.created_by_id == alice.id
    end

    test "3.3 - Pagination des dépenses (Read paginé)" do
      %{alice: alice, wallet: wallet} = setup_wallet_with_members()

      # Créons 10 dépenses pour ce porte-monnaie
      for i <- 1..10 do
        {:ok, _expense} =
          Expenses.create_expense(alice, wallet, %{
            title: "Dépense n°#{i}",
            amount: "10.00",
            date: Date.utc_today()
          })
      end

      # Page 1 avec page_size = 5
      pagination_page_1 = Expenses.list_expenses_for_wallet_paginated(wallet.id, 1, 5)

      assert length(pagination_page_1.entries) == 5
      assert pagination_page_1.total_entries == 10
      assert pagination_page_1.total_pages == 2
      assert pagination_page_1.page_number == 1
      assert pagination_page_1.has_next == true
      assert pagination_page_1.has_prev == false

      # Page 2 avec page_size = 5
      pagination_page_2 = Expenses.list_expenses_for_wallet_paginated(wallet.id, 2, 5)

      assert length(pagination_page_2.entries) == 5
      assert pagination_page_2.page_number == 2
      assert pagination_page_2.has_next == false
      assert pagination_page_2.has_prev == true
    end

    test "3.4 - Suppression sécurisée d'une dépense (Delete)" do
      %{alice: alice, bob: bob, wallet: wallet} = setup_wallet_with_members()

      {:ok, expense} =
        Expenses.create_expense(alice, wallet, %{
          title: "Billet de train",
          amount: "80.00",
          date: Date.utc_today()
        })

      # Bob ne doit PAS pouvoir supprimer la dépense payée par Alice
      assert {:error, :unauthorized} = Expenses.delete_expense(bob, expense.id)

      # Alice (ou le créateur du wallet) PEUT supprimer la dépense
      assert {:ok, _deleted} = Expenses.delete_expense(alice, expense.id)

      # Vérification qu'elle n'existe plus en base
      assert_raise Ecto.NoResultsError, fn ->
        Expenses.get_expense!(expense.id)
      end
    end
  end
end
