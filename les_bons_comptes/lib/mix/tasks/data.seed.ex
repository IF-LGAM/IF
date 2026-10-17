defmodule Mix.Tasks.Data.Seed do
  @moduledoc """
  Seeds the database with a large-scale, realistic dataset for demonstration, testing, and performance benchmarks.

  ## Usage

      mix data.seed
      mix data.seed --no-reset

  ## Inside Docker

      docker compose exec web mix data.seed
  """
  use Mix.Task

  @shortdoc "Generates a large-scale dataset for demonstration and testing (IF-10)"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    reset = "--no-reset" not in args
    LesBonsComptes.DataSeeder.run(reset: reset)
  end
end
