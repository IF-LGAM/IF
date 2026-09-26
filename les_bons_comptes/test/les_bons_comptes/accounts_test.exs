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

    test "create_user/1 with valid data creates user and hashes password" do
      assert {:ok, %User{} = user} = Accounts.create_user(@valid_attrs)
      assert user.name == "Alice Dupont"
      assert user.email == "alice@example.com"
      assert user.hashed_password != nil
      assert User.valid_password?(user, "password123")
      refute User.valid_password?(user, "wrong-password")
    end

    test "create_user/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Accounts.create_user(@invalid_attrs)
    end

    test "create_user/1 enforces email uniqueness" do
      assert {:ok, _user} = Accounts.create_user(@valid_attrs)
      assert {:error, changeset} = Accounts.create_user(%{@valid_attrs | name: "Other Name"})
      assert %{email: ["un compte existe déjà"]} = errors_on(changeset)
    end

    test "authenticate_user/2 returns user on valid credentials and error on invalid" do
      {:ok, user} = Accounts.create_user(@valid_attrs)

      assert {:ok, authenticated_user} =
               Accounts.authenticate_user("alice@example.com", "password123")

      assert authenticated_user.id == user.id

      assert {:error, :unauthorized} =
               Accounts.authenticate_user("alice@example.com", "mauvais_mdp")

      assert {:error, :unauthorized} =
               Accounts.authenticate_user("inconnu@example.com", "password123")
    end

    test "get_user/1 and get_user_by_email/1 return correct user" do
      {:ok, user} = Accounts.create_user(@valid_attrs)
      assert Accounts.get_user(user.id).id == user.id
      assert Accounts.get_user_by_email("alice@example.com").id == user.id
      assert is_nil(Accounts.get_user(-1))
      assert is_nil(Accounts.get_user_by_email("unknown@example.com"))
    end
  end
end
