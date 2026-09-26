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
end
