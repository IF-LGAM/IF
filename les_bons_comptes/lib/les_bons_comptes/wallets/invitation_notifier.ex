defmodule LesBonsComptes.Wallets.InvitationNotifier do
  @moduledoc """
  Delivers email notifications for wallet invitations (IF-40).
  """
  import Swoosh.Email

  alias LesBonsComptes.Mailer

  @doc """
  Sends an invitation notification email to the recipient.
  """
  def deliver_invitation(invitation, wallet, inviter) do
    email =
      new()
      |> to(invitation.email)
      |> from({"Les Bons Comptes", "contact@lesbonscomptes.fr"})
      |> subject("Invitation à rejoindre le porte-monnaie « #{wallet.name} »")
      |> html_body("""
      <h1>Invitation sur Les Bons Comptes</h1>
      <p>Bonjour,</p>
      <p><strong>#{inviter.name}</strong> vous a invité(e) à rejoindre le porte-monnaie commun <strong>« #{wallet.name} »</strong>.</p>
      <p>Connectez-vous sur votre espace pour accepter ou refuser cette invitation.</p>
      """)
      |> text_body("""
      Bonjour,

      #{inviter.name} vous a invité(e) à rejoindre le porte-monnaie commun « #{wallet.name} ».
      Connectez-vous sur votre espace pour accepter ou refuser cette invitation.
      """)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end
end
