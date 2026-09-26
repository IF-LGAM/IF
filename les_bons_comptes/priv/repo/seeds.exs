# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     LesBonsComptes.Repo.insert!(%LesBonsComptes.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.
alias LesBonsComptes.Accounts

email = "admin@exemple.com"

unless Accounts.get_user_by_email(email) do
  {:ok, user} =
    Accounts.create_user(%{
      name: "Admin",
      email: email,
      password: "admin"
    })

  IO.puts(" Utilisateur seed créé avec succès : #{user.email} (ID #{user.id})")
end
