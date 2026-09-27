defmodule LesBonsComptes.ExpensesTest do
  use LesBonsComptes.DataCase, async: true

  alias LesBonsComptes.Accounts
  alias LesBonsComptes.Expenses
  alias LesBonsComptes.Expenses.Expense
  alias LesBonsComptes.Wallets

  defp create_user(attrs) do
    unique_suffix = System.unique_integer([:positive])

    default_attrs = %{
      name: "User #{unique_suffix}",
      email: "user_#{unique_suffix}@example.com",
      password: "password123"
    }

    {:ok, user} = Accounts.create_user(Map.merge(default_attrs, attrs))
    user
  end

  defp setup_wallet_with_members do
    creator = create_user(%{name: "Alice"})
    bob_user = create_user(%{name: "Bob"})

    {:ok, wallet} =
      Wallets.create_wallet(creator, %{name: "Voyage Madrid", currency: "EUR"}, [
        %{name: "Bob", email: bob_user.email, user_id: bob_user.id}
      ])

    %{creator: creator, bob: bob_user, wallet: wallet}
  end

  describe "create_expense/3 (IF-66, IF-69, IF-70)" do
    test "crée avec succès une dépense directement affectée au membre connecté (IF-66, IF-70)" do
      %{creator: creator, wallet: wallet} = setup_wallet_with_members()

      attrs = %{
        title: "Billets de train",
        amount: "120.50",
        description: "Aller-retour Madrid"
      }

      assert {:ok, %Expense{} = expense} = Expenses.create_expense(creator, wallet, attrs)
      assert expense.title == "Billets de train"
      assert Decimal.equal?(expense.amount, Decimal.new("120.50"))
      assert expense.description == "Aller-retour Madrid"
      assert expense.currency == "EUR"
      assert expense.wallet_id == wallet.id
      assert expense.created_by_id == creator.id
      assert expense.date == Date.utc_today()

      # Directement affectée au compte dépenseur du créateur
      [owner_member | _] = wallet.members
      assert expense.payer_id == owner_member.id
      assert expense.payer.name == "Alice"
    end

    test "permet de sélectionner un autre membre du porte-monnaie comme dépenseur (IF-68, IF-70)" do
      %{creator: creator, bob: _bob, wallet: wallet} = setup_wallet_with_members()
      bob_member = Enum.find(wallet.members, &(&1.name == "Bob"))

      attrs = %{
        title: "Tapas",
        amount: "45.00",
        payer_id: bob_member.id
      }

      assert {:ok, %Expense{} = expense} = Expenses.create_expense(creator, wallet, attrs)
      assert expense.payer_id == bob_member.id
      assert expense.payer.name == "Bob"
      assert expense.created_by_id == creator.id
    end

    test "refuse la création si le dépenseur ne fait pas partie du porte-monnaie (IF-69, IF-70)" do
      %{creator: creator, wallet: wallet} = setup_wallet_with_members()

      attrs = %{
        title: "Musée",
        amount: "30.00",
        payer_id: 999_999
      }

      assert {:error, changeset} = Expenses.create_expense(creator, wallet, attrs)

      assert "Le membre sélectionné ne fait pas partie de ce porte-monnaie" in errors_on(
               changeset
             ).payer_id
    end

    test "refuse la création si l'utilisateur n'est pas membre du porte-monnaie (IF-66)" do
      %{wallet: wallet} = setup_wallet_with_members()
      intruder = create_user(%{name: "Inconnu"})

      attrs = %{
        title: "Hôtel",
        amount: "200.00"
      }

      assert {:error, :unauthorized} = Expenses.create_expense(intruder, wallet, attrs)
    end

    test "rejette la dépense si le montant est <= 0 ou invalide (IF-69)" do
      %{creator: creator, wallet: wallet} = setup_wallet_with_members()

      assert {:error, changeset} =
               Expenses.create_expense(creator, wallet, %{title: "Test", amount: "0.00"})

      assert "doit être supérieur à 0" in errors_on(changeset).amount

      assert {:error, changeset} =
               Expenses.create_expense(creator, wallet, %{title: "Test", amount: "-15.00"})

      assert "doit être supérieur à 0" in errors_on(changeset).amount
    end

    test "rejette la dépense si le titre est manquant ou trop court (IF-69)" do
      %{creator: creator, wallet: wallet} = setup_wallet_with_members()

      assert {:error, changeset} =
               Expenses.create_expense(creator, wallet, %{title: "", amount: "10.00"})

      assert "ce champ est obligatoire" in errors_on(changeset).title

      assert {:error, changeset} =
               Expenses.create_expense(creator, wallet, %{title: "A", amount: "10.00"})

      assert "doit contenir entre 2 et 100 caractères" in errors_on(changeset).title
    end

    test "rejette la dépense si la date est dans le futur (IF-69)" do
      %{creator: creator, wallet: wallet} = setup_wallet_with_members()
      future_date = Date.add(Date.utc_today(), 5)

      assert {:error, changeset} =
               Expenses.create_expense(creator, wallet, %{
                 title: "Achat futur",
                 amount: "25.00",
                 date: future_date
               })

      assert "la date ne peut pas être dans le futur" in errors_on(changeset).date
    end
  end

  describe "list_expenses_for_wallet/1 et total_expenses_for_wallet/1" do
    test "calcule le total et liste les dépenses enregistrées" do
      %{creator: creator, bob: bob, wallet: wallet} = setup_wallet_with_members()

      assert Expenses.list_expenses_for_wallet(wallet.id) == []
      assert Decimal.equal?(Expenses.total_expenses_for_wallet(wallet.id), Decimal.new("0.0"))

      {:ok, _e1} =
        Expenses.create_expense(creator, wallet, %{
          title: "Course 1",
          amount: "50.00",
          date: ~D[2026-09-20]
        })

      {:ok, _e2} =
        Expenses.create_expense(bob, wallet, %{
          title: "Course 2",
          amount: "30.50",
          date: ~D[2026-09-25]
        })

      expenses = Expenses.list_expenses_for_wallet(wallet.id)
      assert length(expenses) == 2

      # Triées par date décroissante
      [first, second] = expenses
      assert first.title == "Course 2"
      assert second.title == "Course 1"

      total = Expenses.total_expenses_for_wallet(wallet.id)
      assert Decimal.equal?(total, Decimal.new("80.50"))
    end
  end

  describe "delete_expense/2 et can_delete_expense?/2 (IF-77, IF-78, IF-79)" do
    test "le créateur de la dépense peut la supprimer" do
      %{creator: _creator, bob: bob, wallet: wallet} = setup_wallet_with_members()

      {:ok, expense} =
        Expenses.create_expense(bob, wallet, %{title: "Restaurant", amount: "50.00"})

      assert Expenses.can_delete_expense?(bob, expense)
      assert {:ok, _deleted} = Expenses.delete_expense(bob, expense)
      assert_raise Ecto.NoResultsError, fn -> Expenses.get_expense!(expense.id) end
    end

    test "le propriétaire du porte-monnaie peut supprimer n'importe quelle dépense du groupe" do
      %{creator: creator, bob: bob, wallet: wallet} = setup_wallet_with_members()

      {:ok, expense} =
        Expenses.create_expense(bob, wallet, %{title: "Taxi", amount: "20.00"})

      assert Expenses.can_delete_expense?(creator, expense)
      assert {:ok, _deleted} = Expenses.delete_expense(creator, expense)
      assert_raise Ecto.NoResultsError, fn -> Expenses.get_expense!(expense.id) end
    end

    test "le membre dépenseur peut supprimer la dépense même créée par un autre" do
      %{creator: creator, bob: bob, wallet: wallet} = setup_wallet_with_members()
      bob_member = Enum.find(wallet.members, &(&1.name == "Bob"))

      # Le créateur Alice crée la dépense pour le compte dépenseur de Bob
      {:ok, expense} =
        Expenses.create_expense(creator, wallet, %{
          title: "Cadeau",
          amount: "30.00",
          payer_id: bob_member.id
        })

      assert Expenses.can_delete_expense?(bob, expense)
      assert {:ok, _deleted} = Expenses.delete_expense(bob, expense)
    end

    test "un autre membre ne peut pas supprimer la dépense (IF-79)" do
      %{creator: creator, wallet: wallet} = setup_wallet_with_members()
      charlie_user = create_user(%{name: "Charlie"})

      {:ok, _member} =
        Wallets.add_member(creator, wallet, %{
          name: "Charlie",
          email: charlie_user.email,
          user_id: charlie_user.id
        })

      wallet = Wallets.get_wallet!(wallet.id)

      # Alice crée une dépense
      {:ok, expense} =
        Expenses.create_expense(creator, wallet, %{title: "Courses", amount: "60.00"})

      # Charlie tente de la supprimer
      refute Expenses.can_delete_expense?(charlie_user, expense)
      assert {:error, :unauthorized} = Expenses.delete_expense(charlie_user, expense)
    end
  end

  describe "calculate_creditors/1 et calculate_balances/1 (Calcul des comptes créditeurs)" do
    test "porte-monnaie sans dépenses : aucun créditeur et soldes à zéro" do
      %{wallet: wallet} = setup_wallet_with_members()

      assert Expenses.calculate_creditors(wallet) == []
      assert Expenses.list_creditors(wallet) == []
      assert Expenses.calculate_creditor_accounts(wallet) == []

      balances = Expenses.calculate_balances(wallet)
      assert length(balances) == 2
      assert Enum.all?(balances, &(&1.type == :balanced))
      assert Enum.all?(balances, &Decimal.equal?(&1.balance, Decimal.new("0.00")))
      assert Enum.all?(balances, &Decimal.equal?(&1.total_paid, Decimal.new("0.00")))
    end

    test "porte-monnaie avec un seul membre : aucun créditeur" do
      creator = create_user(%{name: "Solitaire"})
      {:ok, wallet} = Wallets.create_wallet(creator, %{name: "Projet Solo", currency: "EUR"})

      {:ok, _exp} =
        Expenses.create_expense(creator, wallet, %{title: "Abonnement", amount: "50.00"})

      assert Expenses.calculate_creditors(wallet) == []
      [single_balance] = Expenses.calculate_balances(wallet)
      assert single_balance.type == :balanced
      assert Decimal.equal?(single_balance.balance, Decimal.new("0.00"))
    end

    test "deux membres : calcul exact du compte créditeur et du montant à recevoir" do
      %{creator: creator, wallet: wallet} = setup_wallet_with_members()

      {:ok, _exp} =
        Expenses.create_expense(creator, wallet, %{
          title: "Courses supermarché",
          amount: "100.00"
        })

      # Alice a payé 100€, Bob 0€. Total = 100€, part par membre = 50€
      # Alice doit recevoir 50€
      assert [creditor] = Expenses.calculate_creditors(wallet)

      assert creditor.name == "Alice"
      assert Decimal.equal?(creditor.amount_to_receive, Decimal.new("50.00"))
      assert Decimal.equal?(creditor.amount, Decimal.new("50.00"))
      assert Decimal.equal?(creditor.total_paid, Decimal.new("100.00"))
      assert Decimal.equal?(creditor.fair_share, Decimal.new("50.00"))
      assert Decimal.equal?(creditor.balance, Decimal.new("50.00"))
      assert creditor.currency == "EUR"
      assert creditor.member.id == Enum.find(wallet.members, &(&1.name == "Alice")).id
    end

    test "plusieurs membres et dépenses : liste les créditeurs triés par montant décroissant" do
      creator = create_user(%{name: "Alice"})
      bob = create_user(%{name: "Bob"})
      charlie = create_user(%{name: "Charlie"})
      david = create_user(%{name: "David"})

      {:ok, wallet} =
        Wallets.create_wallet(creator, %{name: "Voyage à 4", currency: "EUR"}, [
          %{name: "Bob", email: bob.email, user_id: bob.id},
          %{name: "Charlie", email: charlie.email, user_id: charlie.id},
          %{name: "David", email: david.email, user_id: david.id}
        ])

      # Total = 80 + 40 + 60 + 20 = 200€
      # Nombre de membres = 4 -> part équitable = 50€
      # Alice paie : 80 + 40 = 120€ -> balance = +70€ (créditeur 1)
      # Bob paie : 60€ -> balance = +10€ (créditeur 2)
      # Charlie paie : 20€ -> balance = -30€ (débiteur)
      # David paie : 0€ -> balance = -50€ (débiteur)

      {:ok, _e1} =
        Expenses.create_expense(creator, wallet, %{title: "Location", amount: "80.00"})

      {:ok, _e2} =
        Expenses.create_expense(creator, wallet, %{title: "Essence", amount: "40.00"})

      {:ok, _e3} =
        Expenses.create_expense(bob, wallet, %{title: "Restaurant", amount: "60.00"})

      {:ok, _e4} =
        Expenses.create_expense(charlie, wallet, %{title: "Péage", amount: "20.00"})

      creditors = Expenses.calculate_creditors(wallet)
      assert length(creditors) == 2

      [first, second] = creditors

      # Trié par montant à recevoir décroissant
      assert first.name == "Alice"
      assert Decimal.equal?(first.amount_to_receive, Decimal.new("70.00"))
      assert Decimal.equal?(first.total_paid, Decimal.new("120.00"))
      assert Decimal.equal?(first.fair_share, Decimal.new("50.00"))

      assert second.name == "Bob"
      assert Decimal.equal?(second.amount_to_receive, Decimal.new("10.00"))
      assert Decimal.equal?(second.total_paid, Decimal.new("60.00"))
      assert Decimal.equal?(second.fair_share, Decimal.new("50.00"))
    end

    test "tous les membres ont payé la même somme : aucun créditeur" do
      %{creator: creator, bob: bob, wallet: wallet} = setup_wallet_with_members()

      {:ok, _e1} =
        Expenses.create_expense(creator, wallet, %{title: "Billet train A", amount: "50.00"})

      {:ok, _e2} =
        Expenses.create_expense(bob, wallet, %{title: "Billet train B", amount: "50.00"})

      # Total = 100€, 2 membres -> part = 50€ chacun -> soldes = 0€
      assert Expenses.calculate_creditors(wallet) == []
    end

    test "calcul avec division non entière et arrondi à 2 décimales" do
      creator = create_user(%{name: "Alice"})
      bob = create_user(%{name: "Bob"})
      charlie = create_user(%{name: "Charlie"})

      {:ok, wallet} =
        Wallets.create_wallet(creator, %{name: "Trio", currency: "EUR"}, [
          %{name: "Bob", email: bob.email, user_id: bob.id},
          %{name: "Charlie", email: charlie.email, user_id: charlie.id}
        ])

      # 100€ payés par Alice, part = 100 / 3 = 33.33€
      # Alice doit recevoir 100 - 33.33 = 66.67€
      {:ok, _exp} =
        Expenses.create_expense(creator, wallet, %{title: "Dîner", amount: "100.00"})

      assert [creditor] = Expenses.calculate_creditors(wallet)
      assert creditor.name == "Alice"
      assert Decimal.equal?(creditor.amount_to_receive, Decimal.new("66.67"))
      assert Decimal.equal?(creditor.fair_share, Decimal.new("33.33"))
    end

    test "fonctionne avec %Wallet{}, id entier ou id sous forme de chaîne et via Wallets" do
      %{creator: creator, wallet: wallet} = setup_wallet_with_members()

      {:ok, _exp} =
        Expenses.create_expense(creator, wallet, %{title: "Cadeau", amount: "60.00"})

      by_struct = Expenses.calculate_creditors(wallet)
      by_id = Expenses.calculate_creditors(wallet.id)
      by_string_id = Expenses.calculate_creditors("#{wallet.id}")
      via_wallets = Wallets.calculate_creditors(wallet)
      via_wallets_list = Wallets.list_creditors(wallet.id)
      via_wallets_alias = Wallets.calculate_creditor_accounts(wallet.id)

      assert length(by_struct) == 1
      assert by_struct == by_id
      assert by_struct == by_string_id
      assert by_struct == via_wallets
      assert by_struct == via_wallets_list
      assert by_struct == via_wallets_alias
    end

    test "identifiant invalide, inexistant ou nil retourne une liste vide" do
      assert Expenses.calculate_creditors(999_999) == []
      assert Expenses.calculate_creditors("inexistant") == []
      assert Expenses.calculate_creditors(nil) == []
      assert Expenses.calculate_balances(999_999) == []
      assert Expenses.calculate_balances("inexistant") == []
      assert Expenses.calculate_balances(nil) == []
    end

    test "recalcul dynamique après suppression d'une dépense" do
      %{creator: creator, wallet: wallet} = setup_wallet_with_members()

      {:ok, expense} =
        Expenses.create_expense(creator, wallet, %{title: "Spectacle", amount: "100.00"})

      assert [creditor] = Expenses.calculate_creditors(wallet)
      assert Decimal.equal?(creditor.amount_to_receive, Decimal.new("50.00"))

      {:ok, _deleted} = Expenses.delete_expense(creator, expense)

      assert Expenses.calculate_creditors(wallet) == []
    end
  end

  describe "get_balance_data/1 et fetch_balance_data/1 (Récupération des données pour le calcul des soldes)" do
    test "porte-monnaie avec dépenses et participants : agrège fidèlement toutes les données nécessaires" do
      creator = create_user(%{name: "Alice"})
      bob = create_user(%{name: "Bob"})
      charlie = create_user(%{name: "Charlie"})

      {:ok, wallet} =
        Wallets.create_wallet(creator, %{name: "Voyage Madrid", currency: "EUR"}, [
          %{name: "Bob", email: bob.email, user_id: bob.id},
          %{name: "Charlie", email: charlie.email, user_id: charlie.id}
        ])

      alice_member = Enum.find(wallet.members, &(&1.name == "Alice"))
      bob_member = Enum.find(wallet.members, &(&1.name == "Bob"))
      charlie_member = Enum.find(wallet.members, &(&1.name == "Charlie"))

      {:ok, _e1} =
        Expenses.create_expense(creator, wallet, %{title: "Train A", amount: "60.00"})

      {:ok, _e2} =
        Expenses.create_expense(creator, wallet, %{title: "Train B", amount: "40.00"})

      {:ok, _e3} =
        Expenses.create_expense(bob, wallet, %{title: "Hôtel", amount: "50.00"})

      # Données récupérées
      data = Expenses.get_balance_data(wallet)

      assert is_map(data)
      assert data.wallet_id == wallet.id
      assert data.currency == "EUR"
      assert data.members_count == 3
      assert length(data.members) == 3
      assert data.expenses_count == 3
      assert Expenses.count_expenses_for_wallet(wallet.id) == 3
      assert Decimal.equal?(data.total_expenses, Decimal.new("150.00"))

      # Vérification des cumuls par participant
      assert Decimal.equal?(
               Map.get(data.expenses_by_member, alice_member.id),
               Decimal.new("100.00")
             )

      assert Decimal.equal?(Map.get(data.expenses_by_member, bob_member.id), Decimal.new("50.00"))
      assert Map.get(data.expenses_by_member, charlie_member.id) == nil

      # fetch_balance_data/1 retourne {:ok, data}
      assert {:ok, fetch_data} = Expenses.fetch_balance_data(wallet)
      assert fetch_data == data
    end

    test "porte-monnaie sans dépenses : structure initiale cohérente" do
      %{wallet: wallet} = setup_wallet_with_members()

      data = Expenses.get_balance_data(wallet)

      assert is_map(data)
      assert data.wallet_id == wallet.id
      assert data.currency == "EUR"
      assert data.members_count == 2
      assert length(data.members) == 2
      assert data.expenses_count == 0
      assert Expenses.count_expenses_for_wallet(wallet.id) == 0
      assert Decimal.equal?(data.total_expenses, Decimal.new("0.00"))
      assert data.expenses_by_member == %{}

      assert {:ok, _} = Expenses.fetch_balance_data(wallet)
    end

    test "support polymorphique des paramètres (%Wallet{}, id entier, string) et délégations Wallets" do
      %{creator: creator, wallet: wallet} = setup_wallet_with_members()

      {:ok, _exp} =
        Expenses.create_expense(creator, wallet, %{title: "Restaurant", amount: "45.00"})

      by_struct = Expenses.get_balance_data(wallet)
      by_id = Expenses.get_balance_data(wallet.id)
      by_string_id = Expenses.get_balance_data("#{wallet.id}")
      via_wallets = Wallets.get_balance_data(wallet.id)
      via_wallets_fetch = Wallets.fetch_balance_data(wallet.id)

      assert is_map(by_struct)
      assert by_id == by_string_id
      assert by_id == via_wallets
      assert {:ok, by_id} == via_wallets_fetch

      assert by_struct.wallet_id == by_id.wallet_id
      assert by_struct.currency == by_id.currency
      assert by_struct.members_count == by_id.members_count
      assert by_struct.expenses_count == by_id.expenses_count
      assert Decimal.equal?(by_struct.total_expenses, by_id.total_expenses)
      assert by_struct.expenses_by_member == by_id.expenses_by_member
    end

    test "identifiant invalide, inexistant ou nil" do
      assert Expenses.get_balance_data(999_999) == nil
      assert Expenses.get_balance_data("inexistant") == nil
      assert Expenses.get_balance_data(nil) == nil

      assert Expenses.fetch_balance_data(999_999) == {:error, :not_found}
      assert Expenses.fetch_balance_data("inexistant") == {:error, :not_found}
      assert Expenses.fetch_balance_data(nil) == {:error, :not_found}

      assert Wallets.get_balance_data(999_999) == nil
      assert Wallets.fetch_balance_data(999_999) == {:error, :not_found}
    end

    test "calculate_balances/1 peut directement consommer les données pré-récupérées" do
      %{creator: creator, wallet: wallet} = setup_wallet_with_members()

      {:ok, _exp} =
        Expenses.create_expense(creator, wallet, %{title: "Cinéma", amount: "30.00"})

      data = Expenses.get_balance_data(wallet)
      balances_from_data = Expenses.calculate_balances(data)
      balances_from_wallet = Expenses.calculate_balances(wallet)

      assert length(balances_from_data) == 2
      assert balances_from_data == balances_from_wallet
    end
  end
end
