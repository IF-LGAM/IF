defmodule LesBonsComptesWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use LesBonsComptesWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :current_user, :any,
    default: nil,
    doc: "the current authenticated user"

  attr :show_sign_in, :boolean,
    default: true,
    doc: "whether to show the sign-in / sign-up button in navbar"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a href="/" class="flex-1 flex w-fit items-center gap-2">
          <img src={~p"/images/logo.svg"} width="36" />
          <span class="text-base font-bold text-base-content">Les Bons Comptes</span>
          <span class="badge badge-sm badge-outline">v{Application.spec(:phoenix, :vsn)}</span>
        </a>
      </div>

      <div class="flex-none">
        <ul class="flex flex-column px-1 space-x-3 items-center">
          <li :if={assigns[:current_user]}>
            <.link navigate={~p"/wallets"} class="btn btn-ghost btn-sm gap-1.5">
              <.icon name="hero-wallet" class="size-4 text-primary" />
              <span>Porte-monnaies</span>
            </.link>
          </li>

          <li :if={assigns[:current_user]}>
            <.link navigate={~p"/wallets/new"} class="btn btn-primary btn-sm gap-1">
              <.icon name="hero-plus" class="size-4" />
              <span>Créer</span>
            </.link>
          </li>

          <li :if={assigns[:current_user]}>
            <span class="text-sm font-semibold text-base-content flex items-center gap-1.5 bg-base-200 px-3 py-1.5 rounded-lg">
              <.icon name="hero-user-circle" class="size-5 text-primary" /> {@current_user.name}
            </span>
          </li>

          <li :if={assigns[:current_user]}>
            <.link href={~p"/users/log_out"} method="delete" class="btn btn-outline btn-sm gap-1">
              <.icon name="hero-arrow-right-start-on-rectangle" class="size-4" />
              <span>Déconnexion</span>
            </.link>
          </li>

          <li :if={!assigns[:current_user] && @show_sign_in}>
            <.link navigate={~p"/sign-in"} class="btn btn-ghost btn-sm sm:btn-md">
              Se connecter
            </.link>
          </li>

          <li :if={!assigns[:current_user] && @show_sign_in}>
            <.link navigate={~p"/sign-up"} class="btn btn-primary btn-sm sm:btn-md gap-1">
              <.icon name="hero-user-plus" class="size-4" /> <span>Créer un compte</span>
            </.link>
          </li>

          <li>
            <.theme_toggle />
          </li>
        </ul>
      </div>
    </header>

    <main class="px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-2xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>
    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} /> <.flash kind={:error} flash={@flash} />
      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />
      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
