defmodule LesBonsComptesWeb.PageController do
  use LesBonsComptesWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
