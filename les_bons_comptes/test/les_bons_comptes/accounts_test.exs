defmodule LesBonsComptes.AccountsTest do
  use LesBonsComptes.DataCase

  alias LesBonsComptes.Accounts
  alias LesBonsComptes.Accounts.User

  describe "accounts" do
    @valid_attrs %{name: "Alice Dupont", email: "alice@example.com", password: "password123"}
    @invalid_attrs %{name: nil, email: "invalid-email", password: "123"}

    test "list_users/0 returns all users" do
      {:ok, user} = Accounts.create_user(@valid_attrs)
      assert Accounts.list_users() |> Enum.map(& &1.id) |> Enum.member?(user.id)
    end

    test "create_user/1 with valid data creates a user in database" do
      assert {:ok, %User{} = user} = Accounts.create_user(@valid_attrs)
      assert user.name == "Alice Dupont"
      assert user.email == "alice@example.com"
      assert user.password == "password123"
    end

    test "create_user/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Accounts.create_user(@invalid_attrs)
    end

    test "create_user/1 enforces email uniqueness" do
      assert {:ok, _user} = Accounts.create_user(@valid_attrs)
      assert {:error, changeset} = Accounts.create_user(%{@valid_attrs | name: "Other Name"})
      assert %{email: ["cette adresse email est déjà enregistrée"]} = errors_on(changeset)
    end
  end
end
