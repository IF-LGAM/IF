defmodule LesBonsComptes.Repo do
  use Ecto.Repo,
    otp_app: :les_bons_comptes,
    adapter: Ecto.Adapters.Postgres
end
