defmodule LesBonsComptes.DataSeeder do
  @moduledoc """
  Generates a large-scale, realistic dataset for demonstration, testing, and performance evaluation (Jira Epic IF-10).

  Creates:
  - 60 realistic registered users (including `admin@exemple.com` / `admin123`).
  - 120+ shared wallets spanning all 3 lifecycle stages:
    * `open` (declarations in progress, various currencies: EUR, USD, GBP, CHF, CAD)
    * `pending_settlement` (awaiting transfers, partial settlements, debtor actions)
    * `closed` (fully reconciled and archived, 100% progress)
  - 500+ realistic expenses with varied dates, amounts, and assigned spending accounts.
  - Active, pending, accepted, declined, and cancelled invitations.
  - Direct settlements and mock transfers.
  """

  alias LesBonsComptes.Repo
  alias LesBonsComptes.Accounts.User
  alias LesBonsComptes.Wallets.{Wallet, WalletMember, WalletInvitation}
  alias LesBonsComptes.Expenses.{Expense, Settlement}

  import Ecto.Query

  @doc """
  Runs the full dataset generation.
  Options:
  - `reset: true` (default) clears existing data before seeding.
  """
  def run(opts \\ []) do
    reset = Keyword.get(opts, :reset, true)

    IO.puts("\n🚀 [IF-10] Starting Large-Scale Dataset Generation for « Les bons comptes »...")

    if reset do
      clear_database()
    end

    # 1. Users
    users_map = seed_users()
    IO.puts("  ✓ #{map_size(users_map)} Users created / verified")

    # 2. Wallets, Members, Expenses, Settlements & Invitations
    seed_all_wallets(users_map)

    print_summary()
  end

  # ---------------------------------------------------------------------------
  # Cleanup
  # ---------------------------------------------------------------------------

  defp clear_database do
    IO.puts("  🧹 Cleaning existing database records...")
    Repo.delete_all(Settlement)
    Repo.delete_all(Expense)
    Repo.delete_all(WalletInvitation)
    Repo.delete_all(WalletMember)
    Repo.delete_all(Wallet)
    Repo.delete_all(User)
    IO.puts("  ✓ Database cleared.")
  end

  # ---------------------------------------------------------------------------
  # Users Seeding
  # ---------------------------------------------------------------------------

  defp seed_users do
    IO.puts("  👤 Seeding 60 registered user accounts...")

    # Precompute hashes once for blazing fast execution (<0.5s for 60 users)
    admin_hash = Bcrypt.hash_pwd_salt("admin123")
    default_hash = Bcrypt.hash_pwd_salt("password123")
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    user_specs = [
      # Primary Admin Demo Account
      {"Admin Démo", "admin@exemple.com", admin_hash},

      # Main Characters
      {"Alice Martin", "alice@exemple.com", default_hash},
      {"Bob Dupont", "bob@exemple.com", default_hash},
      {"Charlie Bernard", "charlie@exemple.com", default_hash},
      {"Diane Leroy", "diane@exemple.com", default_hash},
      {"Emma Petit", "emma@exemple.com", default_hash},
      {"Lucas Moreau", "lucas@exemple.com", default_hash},
      {"Sophie Garcia", "sophie@exemple.com", default_hash},
      {"Thomas Roux", "thomas@exemple.com", default_hash},
      {"Camille Fournier", "camille@exemple.com", default_hash},
      {"Hugo Girard", "hugo@exemple.com", default_hash},
      {"Léa Bonnet", "lea@exemple.com", default_hash},
      {"Antoine Mercier", "antoine@exemple.com", default_hash},
      {"Julie Blanc", "julie@exemple.com", default_hash},
      {"Maxime Guerin", "maxime@exemple.com", default_hash},
      {"Chloé Faure", "chloe@exemple.com", default_hash},

      # Extended Population (Think HUGE)
      {"Alexandre David", "alexandre@exemple.com", default_hash},
      {"Béatrice Bertrand", "beatrice@exemple.com", default_hash},
      {"Clément Roux", "clement@exemple.com", default_hash},
      {"Delphine Vincent", "delphine@exemple.com", default_hash},
      {"Éric Fournier", "eric@exemple.com", default_hash},
      {"Fanny Morel", "fanny@exemple.com", default_hash},
      {"Gabriel Girard", "gabriel@exemple.com", default_hash},
      {"Hélène Andre", "helene@exemple.com", default_hash},
      {"Julien Lefebvre", "julien@exemple.com", default_hash},
      {"Karine Mercier", "karine@exemple.com", default_hash},
      {"Laurent Dupont", "laurent@exemple.com", default_hash},
      {"Manon Lambert", "manon@exemple.com", default_hash},
      {"Nicolas Bonnet", "nicolas@exemple.com", default_hash},
      {"Olivia François", "olivia@exemple.com", default_hash},
      {"Pierre Martinez", "pierre@exemple.com", default_hash},
      {"Quentin Legrand", "quentin@exemple.com", default_hash},
      {"Rachel Garnier", "rachel@exemple.com", default_hash},
      {"Sébastien Faure", "sebastien@exemple.com", default_hash},
      {"Théo Rousseau", "theo@exemple.com", default_hash},
      {"Valérie Blanc", "valerie@exemple.com", default_hash},
      {"William Guerin", "william@exemple.com", default_hash},
      {"Xavier Muller", "xavier@exemple.com", default_hash},
      {"Yasmine Henry", "yasmine@exemple.com", default_hash},
      {"Zoé Roussel", "zoe@exemple.com", default_hash},
      {"Arthur Nicolas", "arthur@exemple.com", default_hash},
      {"Inès Renaud", "ines@exemple.com", default_hash},
      {"Romain Caron", "romain@exemple.com", default_hash},
      {"Lucie Perrot", "lucie@exemple.com", default_hash},
      {"Mathieu Collet", "mathieu@exemple.com", default_hash},
      {"Clara Brun", "clara@exemple.com", default_hash},
      {"Vincent Aubry", "vincent@exemple.com", default_hash},
      {"Sarah Mallet", "sarah@exemple.com", default_hash},
      {"Benjamin Rolland", "benjamin@exemple.com", default_hash},
      {"Élodie Pascal", "elodie@exemple.com", default_hash},
      {"Damien Guyot", "damien@exemple.com", default_hash},
      {"Justine Tanguy", "justine@exemple.com", default_hash},
      {"Pauline Coste", "pauline@exemple.com", default_hash},
      {"Florian Bouvier", "florian@exemple.com", default_hash},
      {"Adrien Marchand", "adrien@exemple.com", default_hash},
      {"Marion Dumas", "marion@exemple.com", default_hash},
      {"Bastien Colin", "bastien@exemple.com", default_hash},
      {"Clotilde Barbier", "clotilde@exemple.com", default_hash},
      {"Thibault Fleury", "thibault@exemple.com", default_hash},
      {"Nadège Roy", "nadege@exemple.com", default_hash}
    ]

    Enum.reduce(user_specs, %{}, fn {name, email, hash}, acc ->
      user =
        case Repo.get_by(User, email: email) do
          nil ->
            Repo.insert!(%User{
              name: name,
              email: email,
              hashed_password: hash,
              inserted_at: now,
              updated_at: now
            })

          existing ->
            existing
        end

      Map.put(acc, email, user)
    end)
  end

  # ---------------------------------------------------------------------------
  # Wallets & Data Seeding
  # ---------------------------------------------------------------------------

  defp seed_all_wallets(users) do
    IO.puts("  💼 Seeding 120+ shared wallets across all lifecycle stages...")

    admin = users["admin@exemple.com"]
    alice = users["alice@exemple.com"]
    bob = users["bob@exemple.com"]
    charlie = users["charlie@exemple.com"]
    diane = users["diane@exemple.com"]
    emma = users["emma@exemple.com"]
    lucas = users["lucas@exemple.com"]
    sophie = users["sophie@exemple.com"]
    thomas = users["thomas@exemple.com"]
    camille = users["camille@exemple.com"]
    hugo = users["hugo@exemple.com"]
    lea = users["lea@exemple.com"]
    antoine = users["antoine@exemple.com"]
    julie = users["julie@exemple.com"]
    maxime = users["maxime@exemple.com"]
    chloe = users["chloe@exemple.com"]
    alexandre = users["alexandre@exemple.com"]
    theo = users["theo@exemple.com"]

    # =========================================================================
    # A. CORE DEMO SCENARIOS FOR ADMIN (OWNER)
    # =========================================================================

    # 1. Vacances en Grèce - Cyclades (EUR, Open, 5 members, 12 expenses)
    {w1, m1} =
      create_wallet_with_members(
        admin,
        "Vacances en Grèce - Cyclades",
        "Voyage d'été entre amis dans les îles grecques (Santorin, Paros, Naxos)",
        "EUR",
        "open",
        [alice, bob, charlie, diane]
      )

    add_expense(w1, m1[admin.id], admin, "Villa d'Oia avec piscine", "1250.00", -25, "AirBnB vue sur la Caldeira")
    add_expense(w1, m1[alice.id], alice, "Billets Ferries Blue Star", "360.00", -23, "Trajets Le Pirée - Paros - Santorin")
    add_expense(w1, m1[bob.id], bob, "Location Quads & Scooters", "240.00", -20, "Location 4 jours chez MotoParos")
    add_expense(w1, m1[admin.id], admin, "Dîner Taverne To Ouzeri", "185.50", -19, "Poissons grillés et mezze")
    add_expense(w1, m1[charlie.id], charlie, "Excursion catamaran volcan & sources", "260.00", -18, "Journée navigation")
    add_expense(w1, m1[diane.id], diane, "Courses supermarché Carrefour", "118.40", -16, "Petit-déjeuners et apéritifs")
    add_expense(w1, m1[alice.id], alice, "Cocktails coucher de soleil", "95.00", -14, "Bar Franco's Thira")
    add_expense(w1, m1[bob.id], bob, "Dîner poissons à Naoussa", "225.00", -12, "Restaurant sur le port de Paros")
    add_expense(w1, m1[admin.id], admin, "Visite musée archéologique Akrotiri", "60.00", -10, "Guide francophone inclus")
    add_expense(w1, m1[admin.id], admin, "Transats & parasols Perissa", "80.00", -8, "Plage de sable noir")
    add_expense(w1, m1[charlie.id], charlie, "Location de planches de windsurf", "130.00", -6, "Golden Beach Paros")
    add_expense(w1, m1[diane.id], diane, "Glaces artisanales & cafés frappés", "45.00", -4, "Chora de Naxos")

    # 2. Roadtrip Côte Ouest USA (USD, Open, 4 members, 10 expenses)
    {w2, m2} =
      create_wallet_with_members(
        admin,
        "Roadtrip Côte Ouest USA",
        "De San Francisco à Las Vegas en passant par Yosemite et le Grand Canyon",
        "USD",
        "open",
        [sophie, thomas, lucas]
      )

    add_expense(w2, m2[admin.id], admin, "Location SUV Grand Cherokee Hertz", "890.00", -40, "Prise en charge à SFO", "USD")
    add_expense(w2, m2[sophie.id], sophie, "Pass Parcs Nationaux America the Beautiful", "80.00", -38, "Accès illimité parcs", "USD")
    add_expense(w2, m2[thomas.id], thomas, "Motel 6 Flagstaff Route 66", "145.00", -35, "2 chambres pour 1 nuit", "USD")
    add_expense(w2, m2[lucas.id], lucas, "Plein d'essence Chevron Death Valley", "78.50", -33, "Station Furnace Creek", "USD")
    add_expense(w2, m2[admin.id], admin, "Dîner In-N-Out Burger LA", "64.00", -31, "Burgers & Milkshakes", "USD")
    add_expense(w2, m2[sophie.id], sophie, "Survol hélicoptère Grand Canyon", "720.00", -28, "Papillon Helicopters", "USD")
    add_expense(w2, m2[admin.id], admin, "Spectacle Cirque du Soleil Vegas", "380.00", -25, "O au Bellagio", "USD")
    add_expense(w2, m2[thomas.id], thomas, "Courses Trader Joe's", "112.30", -22, "Pique-niques randonnées", "USD")
    add_expense(w2, m2[lucas.id], lucas, "Péages Golden Gate Bridge & ponts", "36.00", -20, "FasTrak Bay Area", "USD")
    add_expense(w2, m2[admin.id], admin, "Dîner buffet Wynn Las Vegas", "240.00", -18, "Buffet gastronomique", "USD")

    # 3. Weekend Ski aux 2 Alpes (EUR, Pending Settlement, 4 members, partial settlement progress)
    {w3, m3} =
      create_wallet_with_members(
        admin,
        "Weekend Ski aux 2 Alpes",
        "Séjour glisse entre amis, raclette et bonne ambiance en altitude",
        "EUR",
        "pending_settlement",
        [bob, diane, antoine]
      )

    add_expense(w3, m3[admin.id], admin, "Location Chalet Pied des Pistes", "980.00", -15, "Chalet 8 personnes 3 nuits")
    add_expense(w3, m3[admin.id], admin, "Forfaits de ski 3 jours", "540.00", -14, "Domaine skiable complet")
    add_expense(w3, m3[diane.id], diane, "Soirée Raclette & Vin de Savoie", "130.00", -13, "Fromage fermier et charcuterie")
    add_expense(w3, m3[bob.id], bob, "Location skis & snowboards", "210.00", -13, "Intersport Station")

    # Bob settled his transfer to Admin -> 33% progress bar!
    record_settlement(w3, m3[bob.id], m3[admin.id], "255.00", -2)

    # 4. Trek Tour du Mont-Blanc (CHF, Closed, 4 members, all settled)
    {w4, m4} =
      create_wallet_with_members(
        admin,
        "Trek Tour du Mont-Blanc",
        "Grande randonnée alpine à travers la France, l'Italie et la Suisse",
        "CHF",
        "closed",
        [thomas, lea, maxime]
      )

    add_expense(w4, m4[admin.id], admin, "Refuge des Mottets demi-pension", "320.00", -60, "Nuitée et dîner campagnard", "CHF")
    add_expense(w4, m4[thomas.id], thomas, "Refuge Bonatti demi-pension", "340.00", -58, "Vue imprenable sur le Mont-Blanc", "CHF")
    add_expense(w4, m4[lea.id], lea, "Pique-niques & barres de céréales", "120.00", -56, "Ravitaillement Champex", "CHF")
    add_expense(w4, m4[maxime.id], maxime, "Téléphérique Skyway Monte Bianco", "160.00", -54, "Traversée des glaciers", "CHF")

    # 100% progress
    record_settlement(w4, m4[lea.id], m4[thomas.id], "105.00", -45)
    record_settlement(w4, m4[maxime.id], m4[admin.id], "75.00", -44)

    # 5. Colocation Voltaire 2026 (EUR, Open, 4 members, 8 expenses)
    {w5, m5} =
      create_wallet_with_members(
        admin,
        "Colocation Voltaire 2026",
        "Dépenses partagées du quotidien pour l'appartement du 11ème arrondissement",
        "EUR",
        "open",
        [emma, camille, hugo]
      )

    add_expense(w5, m5[admin.id], admin, "Abonnement Fibre Orange", "49.99", -10, "Internet & TV mars")
    add_expense(w5, m5[emma.id], emma, "Courses collectives Biocoop", "165.40", -7, "Alimentation et base cuisine")
    add_expense(w5, m5[camille.id], camille, "Canapé d'angle convertible Ikea", "599.00", -30, "Salon commun")
    add_expense(w5, m5[admin.id], admin, "Facture EDF électricité", "185.00", -5, "Régularisation hiver")
    add_expense(w5, m5[hugo.id], hugo, "Produits d'entretien & ménage", "42.80", -3, "Lessive, éponges, sacs poubelle")
    add_expense(w5, m5[emma.id], emma, "Table basse & coussins", "145.00", -2, "Déco salon")
    add_expense(w5, m5[admin.id], admin, "Robot aspirateur laveur Roborock", "320.00", -20, "Achat commun équipement")
    add_expense(w5, m5[camille.id], camille, "Soirée crémaillère apéritif dînatoire", "110.00", -15, "Boissons et snacks")

    # 6. Nouveau Projet Hackathon IA (EUR, Open, 2 members, 0 expenses - Clean empty state)
    create_wallet_with_members(
      admin,
      "Nouveau Projet Hackathon IA",
      "Frais d'inscription et serveurs cloud pour le hackathon tech de ce weekend",
      "EUR",
      "open",
      [hugo]
    )

    # 7. Dîner Bistrot des Amis (EUR, Open, 2 members, balanced state)
    {w7, m7} =
      create_wallet_with_members(
        admin,
        "Dîner Bistrot des Amis",
        "Soirée gastronomique et retrouvailles au restaurant Le Châteaubriand",
        "EUR",
        "open",
        [bob]
      )

    add_expense(w7, m7[admin.id], admin, "Entrées & Plats dégustation", "55.00", -1, "Menu saison")
    add_expense(w7, m7[bob.id], bob, "Vins, Desserts & Cafés", "55.00", -1, "Accords mets & vins")

    # 8. Festival d'Avignon 2026 (EUR, Open, 4 members, Owner ready to validate)
    {w8, m8} =
      create_wallet_with_members(
        admin,
        "Festival d'Avignon 2026",
        "Spectacles du Festival In, hébergement intramuros et terrasses d'été",
        "EUR",
        "open",
        [alice, charlie, julie]
      )

    add_expense(w8, m8[admin.id], admin, "Logement Vieille Ville Avignon", "720.00", -14, "Appartement climatisé 4 nuits")
    add_expense(w8, m8[alice.id], alice, "Billets Cour d'Honneur du Palais", "240.00", -12, "Grande pièce d'ouverture")
    add_expense(w8, m8[charlie.id], charlie, "Dîners Place de l'Horloge", "190.00", -11, "Terrasses festives")
    add_expense(w8, m8[julie.id], julie, "Spectacles Off Avignon", "130.00", -10, "Pass Off pour 4 personnes")

    # 9. Séjour Londres & Tech (GBP, Open, 3 members)
    {w9, m9} =
      create_wallet_with_members(
        admin,
        "Séjour Londres & Tech",
        "Conférence tech à Shoreditch et découvertes culturelles",
        "GBP",
        "open",
        [lucas, sophie]
      )

    add_expense(w9, m9[admin.id], admin, "Billets Eurostar AR", "420.00", -8, "Paris Gare du Nord -> St Pancras", "GBP")
    add_expense(w9, m9[lucas.id], lucas, "Hôtel CitizenM Shoreditch", "650.00", -7, "3 nuits design", "GBP")
    add_expense(w9, m9[sophie.id], sophie, "Dîner Dishoom Shoreditch", "135.00", -6, "Cuisine indienne Bombay", "GBP")

    # 10. Voyage Montréal & Québec (CAD, Open, 4 members)
    {w10, m10} =
      create_wallet_with_members(
        admin,
        "Voyage Montréal & Québec",
        "Roadtrip automnal au Québec pour l'été indien",
        "CAD",
        "open",
        [antoine, lea, maxime]
      )

    add_expense(w10, m10[admin.id], admin, "Chalet en Mauricie bord de lac", "850.00", -18, "Chalet en bois rond", "CAD")
    add_expense(w10, m10[antoine.id], antoine, "Location Minivan Dodge Caravan", "480.00", -17, "Enterprise Rent-A-Car", "CAD")
    add_expense(w10, m10[lea.id], lea, "Repas cabane à sucre & tire d'érable", "160.00", -15, "Repas traditionnel québécois", "CAD")
    add_expense(w10, m10[maxime.id], maxime, "Hydravion au-dessus des forêts", "520.00", -14, "Survol des couleurs de l'automne", "CAD")

    # 11. Trek Dolomites Alta Via 1 (EUR, Pending Settlement, 3 members)
    {w11, m11} =
      create_wallet_with_members(
        admin,
        "Trek Dolomites Alta Via 1",
        "Randonnée spectaculaire au cœur des Dolomites italiennes",
        "EUR",
        "pending_settlement",
        [charlie, diane]
      )

    add_expense(w11, m11[admin.id], admin, "Refuge Lagazuoi demi-pension", "330.00", -22, "Nuit au sommet avec sauna")
    add_expense(w11, m11[charlie.id], charlie, "Refuge Nuvolau & Fanes", "290.00", -20, "Dîners tyroliens")
    add_expense(w11, m11[diane.id], diane, "Navettes Cortina Express", "90.00", -19, "Transferts gare et départs sentiers")

    record_settlement(w11, m11[diane.id], m11[admin.id], "80.00", -5)

    # 12. Weekend Découverte Amsterdam 2025 (EUR, Closed, 3 members)
    {w12, m12} =
      create_wallet_with_members(
        admin,
        "Weekend Découverte Amsterdam 2025",
        "Canaux, musées et balades à vélo au printemps",
        "EUR",
        "closed",
        [bob, emma]
      )

    add_expense(w12, m12[admin.id], admin, "Péniche hôtel Keizersgracht", "510.00", -95, "Logement sur l'eau")
    add_expense(w12, m12[bob.id], bob, "Location vélos 3 jours", "75.00", -94, "MacBike Amsterdam")
    add_expense(w12, m12[emma.id], emma, "Musée Rijksmuseum & Van Gogh", "120.00", -93, "Billets coupe-file")

    record_settlement(w12, m12[bob.id], m12[admin.id], "125.00", -80)
    record_settlement(w12, m12[emma.id], m12[admin.id], "110.00", -80)

    # 13. Weekend Canoë Gorges de l'Ardèche (EUR, Open, 4 members)
    {w13, m13} =
      create_wallet_with_members(
        admin,
        "Weekend Canoë Gorges de l'Ardèche",
        "Descente de 32 km avec bivouac sous les étoiles",
        "EUR",
        "open",
        [thomas, sophie, lucas]
      )

    add_expense(w13, m13[admin.id], admin, "Descente 2 jours & matériel étanche", "260.00", -7, "Location chez Viking Bateaux")
    add_expense(w13, m13[thomas.id], thomas, "Pass bivouac Gaud & Gournier", "90.00", -6, "Réservation réserve naturelle")
    add_expense(w13, m13[sophie.id], sophie, "Grillades & Barbecue bivouac", "110.00", -5, "Viandes locales et charbon")
    add_expense(w13, m13[lucas.id], lucas, "Pique-niques Vallon Pont d'Arc", "65.00", -4, "Boulangerie et fruits frais")

    # 14. Festival Rock en Seine 2026 (EUR, Open, 3 members)
    {w14, m14} =
      create_wallet_with_members(
        admin,
        "Festival Rock en Seine 2026",
        "Pass 3 jours pour les concerts au Domaine National de Saint-Cloud",
        "EUR",
        "open",
        [chloe, maxime]
      )

    add_expense(w14, m14[admin.id], admin, "Pass 3 Jours x3", "570.00", -11, "Billetterie officielle")
    add_expense(w14, m14[chloe.id], chloe, "Crédits Cashless boissons", "150.00", -10, "Bières et softs")
    add_expense(w14, m14[maxime.id], maxime, "Burgers & Food trucks", "110.00", -9, "Restauration sur place")

    # 15. Soirée Anniversaire Démo 30 Ans (EUR, Open, 5 members)
    {w15, m15} =
      create_wallet_with_members(
        admin,
        "Soirée Anniversaire Démo 30 Ans",
        "Grande fête d'anniversaire dans un loft parisien",
        "EUR",
        "open",
        [alice, bob, charlie, diane]
      )

    add_expense(w15, m15[admin.id], admin, "Location Loft Bastille", "450.00", -3, "Soirée privée")
    add_expense(w15, m15[alice.id], alice, "Traiteur buffet dînatoire", "280.00", -2, "Planches mixtes et mignardises")
    add_expense(w15, m15[bob.id], bob, "Bar & Cocktails personnalisés", "190.00", -2, "Spiritueux et jus artisanaux")
    add_expense(w15, m15[charlie.id], charlie, "Gâteau d'anniversaire chiffre 30", "120.00", -1, "Number cake fruits rouges")
    add_expense(w15, m15[diane.id], diane, "Décoration ballons & lumières LED", "75.00", -1, "Ambiance festive")

    # =========================================================================
    # B. DEMO SCENARIOS WHERE ADMIN IS A PARTICIPATING MEMBER (NOT OWNER)
    # =========================================================================

    # 16. City Break à Londres (GBP, Pending Settlement, 4 members, Admin is debtor!)
    {w16, m16} =
      create_wallet_with_members(
        lucas,
        "City Break à Londres",
        "Weekend shopping, comédie musicale et visites à Soho et Shoreditch",
        "GBP",
        "pending_settlement",
        [admin, sophie, charlie]
      )

    add_expense(w16, m16[lucas.id], lucas, "Appartement Covent Garden", "680.00", -12, "Appartement 3 nuits", "GBP")
    add_expense(w16, m16[sophie.id], sophie, "Billets Warner Bros Harry Potter Studios", "190.00", -11, "Tour guidé", "GBP")
    add_expense(w16, m16[admin.id], admin, "Dîner Pub The Crown & Shuttle", "145.00", -10, "Burgers & Pintes", "GBP")
    add_expense(w16, m16[charlie.id], charlie, "Afternoon Tea chez Sketch", "220.00", -9, "Tea room experience", "GBP")

    # 17. Festival Solidays 2025 (EUR, Closed, 4 members, all settled)
    {w17, m17} =
      create_wallet_with_members(
        alice,
        "Festival Solidays 2025",
        "3 jours de concerts et camping à l'hippodrome de Longchamp",
        "EUR",
        "closed",
        [admin, bob, chloe]
      )

    add_expense(w17, m17[alice.id], alice, "Pass 3 Jours & Camping x4", "440.00", -120, "Early bird tickets")
    add_expense(w17, m17[admin.id], admin, "Recharge Cashless boisson", "180.00", -119, "Consommations bar")
    add_expense(w17, m17[bob.id], bob, "Food trucks & déjeuners", "160.00", -118, "Burgers et crêpes")
    add_expense(w17, m17[chloe.id], chloe, "Tentes 3 secondes & duvets", "140.00", -122, "Matériel Decathlon")

    record_settlement(w17, m17[chloe.id], m17[alice.id], "90.00", -110)
    record_settlement(w17, m17[bob.id], m17[alice.id], "70.00", -110)
    record_settlement(w17, m17[admin.id], m17[alice.id], "50.00", -110)

    # 18. Anniversaire Surprise de Sophie (EUR, Open, 4 members)
    {w18, m18} =
      create_wallet_with_members(
        thomas,
        "Anniversaire Surprise de Sophie",
        "Cadeau commun et fête surprise pour les 25 ans de Sophie",
        "EUR",
        "open",
        [admin, camille, julie]
      )

    add_expense(w18, m18[thomas.id], thomas, "Location salle des fêtes", "350.00", -6, "Acompte réservation")
    add_expense(w18, m18[camille.id], camille, "Traiteur & Buffet salé", "240.00", -4, "Petits fours et mignardises")
    add_expense(w18, m18[admin.id], admin, "Gâteau pâtissier sur-mesure", "95.00", -3, "Fraisier chez Yann Couvreur")
    add_expense(w18, m18[julie.id], julie, "Champagne & Boissons", "180.00", -2, "6 bouteilles")

    # 19. Weekend Rando Gorges du Verdon (EUR, Pending Settlement, 3 members, Admin is debtor)
    {w19, m19} =
      create_wallet_with_members(
        emma,
        "Weekend Rando Gorges du Verdon",
        "Sentier Blanc-Martel et baignade au lac de Sainte-Croix",
        "EUR",
        "pending_settlement",
        [admin, hugo]
      )

    add_expense(w19, m19[emma.id], emma, "Gîte rural à La Palud-sur-Verdon", "360.00", -16, "2 nuits avec petit-déjeuner")
    add_expense(w19, m19[hugo.id], hugo, "Location pédalos & paddles", "95.00", -15, "Après-midi sur le lac")
    add_expense(w19, m19[admin.id], admin, "Dîner auberge provençale", "120.00", -14, "Spécialités de Haute-Provence")

    # 20. Escape Game & Soirée Pizza (EUR, Open, 4 members)
    {w20, m20} =
      create_wallet_with_members(
        lucas,
        "Escape Game & Soirée Pizza",
        "Mission cambriolage chez HintHunt et pizzas napolitaines",
        "EUR",
        "open",
        [admin, bob, diane]
      )

    add_expense(w20, m20[lucas.id], lucas, "Session Escape Game 4 joueurs", "144.00", -4, "Salle Le Trésor des Pirates")
    add_expense(w20, m20[admin.id], admin, "Pizzas chez Popolare & desserts", "96.00", -4, "Pizzas au feu de bois")

    # 21. Voyage en Islande - Aurores Boréales (EUR, Closed, 4 members)
    {w21, m21} =
      create_wallet_with_members(
        diane,
        "Voyage en Islande - Aurores Boréales",
        "Cercle d'Or, cascades glaciaires et bains thermaux Blue Lagoon",
        "EUR",
        "closed",
        [admin, charlie, emma]
      )

    add_expense(w21, m21[diane.id], diane, "Location 4x4 Dacia Duster", "620.00", -150, "Équipé pneus neige")
    add_expense(w21, m21[admin.id], admin, "Chalets en bois Reykjavik & Vik", "780.00", -149, "Hébergements isolés")
    add_expense(w21, m21[charlie.id], charlie, "Entrées Blue Lagoon geothermal spa", "380.00", -148, "Formule confort")
    add_expense(w21, m21[emma.id], emma, "Courses Bonus supermarché", "210.00", -147, "Repas en chalet")

    record_settlement(w21, m21[emma.id], m21[admin.id], "145.00", -140)
    record_settlement(w21, m21[charlie.id], m21[admin.id], "35.00", -140)
    record_settlement(w21, m21[diane.id], m21[admin.id], "20.00", -140)

    # 22. Tournoi Foot à 7 MIAGE (EUR, Open, 4 members)
    {w22, m22} =
      create_wallet_with_members(
        antoine,
        "Tournoi Foot à 7 MIAGE",
        "Frais de terrain et maillots floqués pour le championnat universitaire",
        "EUR",
        "open",
        [admin, maxime, hugo]
      )

    add_expense(w22, m22[antoine.id], antoine, "Location terrain synthétique UrbanSoccer", "240.00", -8, "Session 10 semaines")
    add_expense(w22, m22[admin.id], admin, "Jeux de maillots floqués personnalisés", "160.00", -7, "Flocage nom + numéro")
    add_expense(w22, m22[maxime.id], maxime, "Ballons de match & chasubles", "65.00", -6, "Matériel Kipsta")

    # =========================================================================
    # C. INVITATIONS FOR ADMIN (ALL STATUSES FOR COMPREHENSIVE FILTERING)
    # =========================================================================

    # 23. Escapade à Rome (Pending invitation for Admin)
    {w23, _} =
      create_wallet_with_members(
        alice,
        "Escapade à Rome",
        "Visite du Colisée, fontaine de Trevi et pizzas au Trastevere",
        "EUR",
        "open",
        [charlie]
      )

    create_invitation(w23, alice, admin, "pending")

    # 24. Crémaillère Léa & Maxime (Pending invitation for Admin)
    {w24, _} =
      create_wallet_with_members(
        lea,
        "Crémaillère Léa & Maxime",
        "Cadeau commun pour leur nouvel appartement avec jardin",
        "EUR",
        "open",
        [maxime, antoine]
      )

    create_invitation(w24, lea, admin, "pending")

    # 25. Voyage au Japon Printemps 2027 (Pending invitation for Admin)
    {w25, _} =
      create_wallet_with_members(
        antoine,
        "Voyage au Japon Printemps 2027",
        "Tokyo, Kyoto, Osaka pendant la floraison des cerisiers",
        "EUR",
        "open",
        [lucas, sophie]
      )

    create_invitation(w25, antoine, admin, "pending")

    # 26. Weekend Cabane dans les Arbres (Pending invitation for Admin)
    {w26, _} =
      create_wallet_with_members(
        sophie,
        "Weekend Cabane dans les Arbres",
        "Nuit insolite en pleine forêt dans le Perche avec paniers gourmands",
        "EUR",
        "open",
        [thomas]
      )

    create_invitation(w26, sophie, admin, "pending")

    # 27. Tournoi de Padel Inter-Entreprises (Pending invitation for Admin)
    {w27, _} =
      create_wallet_with_members(
        maxime,
        "Tournoi de Padel Inter-Entreprises",
        "Inscription et location de pistes de padel indoor",
        "EUR",
        "open",
        [julie]
      )

    create_invitation(w27, maxime, admin, "pending")

    # 28. Sortie Escalade Fontainebleau (Declined invitation for Admin)
    {w28, _} =
      create_wallet_with_members(
        charlie,
        "Sortie Escalade Fontainebleau",
        "Location crash-pads et covoiturage en forêt de Fontainebleau",
        "EUR",
        "open",
        [bob, diane]
      )

    create_invitation(w28, charlie, admin, "declined")

    # 29. Soirée Jeux de Plateau (Accepted invitation for Admin)
    {w29, _} =
      create_wallet_with_members(
        emma,
        "Soirée Jeux de Plateau",
        "Achat de nouveaux jeux (Catan, Wingspan, 7 Wonders) et pizzas",
        "EUR",
        "open",
        [camille, admin]
      )

    create_invitation(w29, emma, admin, "accepted")

    # 30. Atelier Cuisine Italienne (Cancelled invitation for Admin)
    {w30, _} =
      create_wallet_with_members(
        camille,
        "Atelier Cuisine Italienne",
        "Cours de fabrication de pâtes fraîches et tiramisu",
        "EUR",
        "open",
        [julie]
      )

    create_invitation(w30, camille, admin, "cancelled")

    # =========================================================================
    # D. COMMUNITY & SCALABILITY WALLETS (THINK HUGE: 95+ REALISTIC WALLETS)
    # =========================================================================

    background_wallets = [
      # 31. Vacances au Portugal - Faro
      {"Vacances au Portugal - Faro", "EUR", "open", alice, [bob, charlie, diane, emma], [
        {"AirBnB Villa Algarve", "1100.00", -15},
        {"Location voitures Sixt", "420.00", -14},
        {"Dîner fruits de mer Olhão", "210.00", -12},
        {"Plein d'essence Repsol", "85.00", -10},
        {"Bar de plage Praia da Rocha", "135.00", -8},
        {"Cours de surf Arrifana", "190.00", -7},
        {"Courses Pingo Doce", "115.00", -5}
      ]},

      # 32. Séjour Surf à Biarritz
      {"Séjour Surf à Biarritz", "EUR", "open", lucas, [antoine, maxime, users["theo@exemple.com"]], [
        {"Appartement vue mer", "750.00", -20},
        {"Location planches de surf & combis", "260.00", -18},
        {"Courses Halles de Biarritz", "145.00", -17},
        {"Pintxos à Saint-Sébastien", "180.00", -15},
        {"Plein d'essence Total", "72.00", -12}
      ]},

      # 33. Voyage à New York Automne
      {"Voyage à New York Automne", "USD", "open", sophie, [thomas, julie, camille], [
        {"Hôtel Manhattan Times Square", "1650.00", -35},
        {"Pass Attractions New York Explorer", "480.00", -33},
        {"Croisière Statue de la Liberté", "120.00", -30},
        {"Dîners & Brunch Brooklyn", "310.00", -28},
        {"Métro card MTA 7 jours", "136.00", -27}
      ]},

      # 34. Roadtrip en Écosse & Highlands
      {"Roadtrip en Écosse & Highlands", "GBP", "open", charlie, [bob, diane, lea], [
        {"Location Van aménagé Campervan", "790.00", -18},
        {"Visite distillerie Talisker Skye", "110.00", -16},
        {"Courses Tesco Inverness", "165.00", -15},
        {"Ferry Île de Skye Mallaig", "85.00", -14},
        {"Pubs & Fish & Chips", "140.00", -12}
      ]},

      # 35. Séjour à Rome & Vatican
      {"Séjour à Rome & Vatican", "EUR", "open", emma, [camille, hugo, alexandre], [
        {"AirBnB quartier Monti", "620.00", -8},
        {"Billets coupe-file Vatican & Colisée", "180.00", -7},
        {"Pizzas & Trattorias romaines", "195.00", -6},
        {"Glaces Giolitti & cafés", "45.00", -5}
      ]},

      # 36. Voyage en Islande - Cascades & Geysers
      {"Voyage en Islande - Cascades & Geysers", "EUR", "open", diane, [alice, charlie, julie], [
        {"Location 4x4 Suzuki Jimny", "580.00", -25},
        {"Hébergements guesthouses Sud", "710.00", -24},
        {"Courses Kronan supermarché", "140.00", -22},
        {"Entrées Secret Lagoon Fludir", "95.00", -20}
      ]},

      # 37. Séjour à Barcelone & Sagrada Familia
      {"Séjour à Barcelone & Sagrada Familia", "EUR", "open", hugo, [lea, antoine, maxime], [
        {"Appartement quartier Gràcia", "520.00", -12},
        {"Billets Sagrada Família & Parc Güell", "140.00", -11},
        {"Tapas au Marché de la Boqueria", "115.00", -10},
        {"Soirée rooftop & paella Barceloneta", "160.00", -9}
      ]},

      # 38. Weekend à Berlin & Kreuzberg
      {"Weekend à Berlin & Kreuzberg", "EUR", "open", maxime, [chloe, theo, users["clara@exemple.com"]], [
        {"Loft moderne Friedrichshain", "480.00", -14},
        {"Location vélos Berlin", "60.00", -13},
        {"Currywurst & Street food Markthalle", "85.00", -12},
        {"Musée de Pergame & Bunker tour", "105.00", -10}
      ]},

      # 39. Voyage à Montréal & Mont-Tremblant
      {"Voyage à Montréal & Mont-Tremblant", "CAD", "open", antoine, [lea, users["valerie@exemple.com"], users["william@exemple.com"]], [
        {"Chalet Tremblant avec spa", "920.00", -22},
        {"Location SUV AWD", "410.00", -20},
        {"Poutineries & Microbrasseries", "175.00", -18},
        {"Activités tyroliennes géantes", "260.00", -16}
      ]},

      # 40. Vacances en Corse du Sud
      {"Vacances en Corse du Sud", "EUR", "open", julie, [camille, sophie, users["yasmine@exemple.com"]], [
        {"Maison vue mer Porto-Vecchio", "1350.00", -30},
        {"Ferry Corsica Ferries Toulon-Ajaccio", "380.00", -29},
        {"Bateau pour les Îles Lavezzi", "140.00", -27},
        {"Paillote plage Santa Giulia", "210.00", -25},
        {"Charcuterie & Fromages fermiers", "115.00", -23}
      ]},

      # 41. Séjour aux Îles Lofoten
      {"Séjour aux Îles Lofoten", "EUR", "open", users["gabriel@exemple.com"], [users["helene@exemple.com"], users["julien@exemple.com"]], [
        {"Hébergements Rorbu Lofoten", "1120.00", -13},
        {"Ferries Hurtigruten", "230.00", -12},
        {"Courses Kiwi supermarché", "185.00", -10}
      ]},

      # 42. Weekend Découverte Amsterdam
      {"Weekend Découverte Amsterdam", "EUR", "open", users["fanny@exemple.com"], [users["alexandre@exemple.com"], users["beatrice@exemple.com"]], [
        {"Péniche sur les canaux", "540.00", -9},
        {"Location vélos 3 jours", "75.00", -8},
        {"Musée Van Gogh & Rijksmuseum", "110.00", -7},
        {"Brunch & cafés de Jordaan", "95.00", -6}
      ]},

      # 43. Voyage en Suisse - Interlaken
      {"Voyage en Suisse - Interlaken", "CHF", "open", users["delphine@exemple.com"], [users["eric@exemple.com"], users["karine@exemple.com"]], [
        {"Chalet avec vue Eiger", "790.00", -16},
        {"Train Jungfraujoch Top of Europe", "460.00", -15},
        {"Parapente biplace tandem", "340.00", -14},
        {"Fondue moitié-moitié", "145.00", -12}
      ]},

      # 44. Colocation Lyon Bellecour
      {"Colocation Lyon Bellecour", "EUR", "open", users["manon@exemple.com"], [users["nicolas@exemple.com"], users["pierre@exemple.com"]], [
        {"Box internet SFR Fibre", "34.99", -20},
        {"Courses Grand Frais", "185.20", -18},
        {"Meuble TV & étagères", "140.00", -35},
        {"Bouchon lyonnais", "125.00", -10}
      ]},

      # 45. Colocation Bordeaux Victoire
      {"Colocation Bordeaux Victoire", "EUR", "open", users["quentin@exemple.com"], [users["rachel@exemple.com"], users["sebastien@exemple.com"]], [
        {"Loyer box & charges communes", "65.00", -15},
        {"Courses Leclerc drive", "195.40", -12},
        {"Cafetière expresso Delonghi", "120.00", -25},
        {"Soirée tapas & vin de Bordeaux", "85.00", -8}
      ]},

      # 46. Colocation Strasbourg Krutenau
      {"Colocation Strasbourg Krutenau", "EUR", "open", users["theo@exemple.com"], [users["valerie@exemple.com"], users["william@exemple.com"]], [
        {"Abonnement gaz & électricité", "140.00", -18},
        {"Courses bio marché", "110.00", -14},
        {"Produits vaisselle et ménage", "35.50", -10},
        {"Tarte flambée d'accueil", "60.00", -22}
      ]},

      # 47. Colocation Lille Vauban
      {"Colocation Lille Vauban", "EUR", "open", users["xavier@exemple.com"], [users["yasmine@exemple.com"], users["zoe@exemple.com"]], [
        {"Internet fibre Bouygues", "32.99", -21},
        {"Courses supermarché Match", "175.00", -17},
        {"Ustensiles de cuisine Tefal", "85.00", -30},
        {"Welsh et bières du Nord", "70.00", -11}
      ]},

      # 48. Colocation Toulouse Capitole
      {"Colocation Toulouse Capitole", "EUR", "open", users["arthur@exemple.com"], [users["ines@exemple.com"], users["romain@exemple.com"]], [
        {"Box fibre Freebox Delta", "39.99", -19},
        {"Courses épicerie & marché Victor Hugo", "160.00", -14},
        {"Canapé salon convertible", "280.00", -45},
        {"Cassoulet fait maison", "55.00", -7}
      ]},

      # 49. Colocation Nantes Bouffay
      {"Colocation Nantes Bouffay", "EUR", "open", users["lucie@exemple.com"], [users["mathieu@exemple.com"], users["clara@exemple.com"]], [
        {"Box Orange Livebox", "41.99", -12},
        {"Courses drive Carrefour", "180.00", -9},
        {"Four micro-ondes combiné", "110.00", -40},
        {"Crêperie de bienvenue", "65.00", -5}
      ]},

      # 50. Colocation Marseille Vieux-Port
      {"Colocation Marseille Vieux-Port", "EUR", "open", users["vincent@exemple.com"], [users["sarah@exemple.com"], users["benjamin@exemple.com"]], [
        {"Électricité EDF", "125.00", -22},
        {"Courses Noailles & bio", "150.00", -16},
        {"Aspirateur balai sans fil", "160.00", -35},
        {"Poissonnerie pour bouillabaisse", "90.00", -10}
      ]},

      # 51. Colocation Rennes Sainte-Anne
      {"Colocation Rennes Sainte-Anne", "EUR", "open", users["elodie@exemple.com"], [users["damien@exemple.com"], users["justine@exemple.com"]], [
        {"Abonnement internet Sosh", "25.99", -15},
        {"Courses Biocoop Rennes", "145.00", -11},
        {"Galettes & cidre artisanal", "55.00", -8}
      ]},

      # 52. Colocation Grenoble Berriat
      {"Colocation Grenoble Berriat", "EUR", "open", users["pauline@exemple.com"], [users["florian@exemple.com"], users["adrien@exemple.com"]], [
        {"Facture chauffage urbain", "160.00", -28},
        {"Courses supermarché", "170.00", -20},
        {"Raclette de rentrée", "80.00", -15}
      ]},

      # 53. Colocation Montpellier Antigone
      {"Colocation Montpellier Antigone", "EUR", "open", users["marion@exemple.com"], [users["bastien@exemple.com"], users["clotilde@exemple.com"]], [
        {"Internet fibre Red SFR", "29.99", -16},
        {"Courses bio marché des Arceaux", "135.00", -12},
        {"Ventilateurs de salon", "70.00", -40}
      ]},

      # 54. Roadtrip Andalousie & Séville
      {"Roadtrip Andalousie & Séville", "EUR", "open", users["yasmine@exemple.com"], [users["zoe@exemple.com"], users["arthur@exemple.com"], users["ines@exemple.com"]], [
        {"Appartement Santa Cruz Séville", "560.00", -11},
        {"Visite Alhambra Grenade", "120.00", -10},
        {"Spectacle Flamenco & tapas", "165.00", -9},
        {"Location Seat Leon", "280.00", -8}
      ]},

      # 55. Séjour Randonnée Madère
      {"Séjour Randonnée Madère", "EUR", "open", users["damien@exemple.com"], [users["justine@exemple.com"], users["pauline@exemple.com"], users["florian@exemple.com"]], [
        {"Quinta traditionnelle Funchal", "640.00", -7},
        {"Location voiture", "230.00", -6},
        {"Téléphérique Monte & traîneaux", "110.00", -5},
        {"Espada & bananes restaurant", "140.00", -4}
      ]},

      # 56. Vacances Martinique & Anses d'Arlet
      {"Vacances Martinique & Anses d'Arlet", "EUR", "open", users["adrien@exemple.com"], [users["marion@exemple.com"], users["bastien@exemple.com"]], [
        {"Villa créole avec piscine", "1150.00", -22},
        {"Location Dacia Sandero", "340.00", -21},
        {"Sortie dauphins en mer", "180.00", -18},
        {"Bokits & accras de morue", "65.00", -16}
      ]},

      # 57. Roadtrip Irlande - Wild Atlantic Way
      {"Roadtrip Irlande - Wild Atlantic Way", "EUR", "open", users["clotilde@exemple.com"], [users["thibault@exemple.com"], users["nadege@exemple.com"]], [
        {"B&B Galway et Connemara", "580.00", -15},
        {"Location voiture conduite à gauche", "320.00", -14},
        {"Pubs & musique traditionnelle", "160.00", -12},
        {"Falaises de Moher entrées", "48.00", -10}
      ]},

      # 58. Séjour Ski Tignes & Val d'Isère
      {"Séjour Ski Tignes & Val d'Isère", "EUR", "open", users["thibault@exemple.com"], [users["nadege@exemple.com"], users["vincent@exemple.com"], users["sarah@exemple.com"]], [
        {"Appartement Tignes Val Claret", "1200.00", -28},
        {"Forfaits ski Espace Killy", "880.00", -27},
        {"Location matériel ski", "360.00", -26},
        {"Courses Sherpa station", "240.00", -25}
      ]},

      # 59. Voyage en Croatie - Split & Hvar
      {"Voyage en Croatie - Split & Hvar", "EUR", "open", users["benjamin@exemple.com"], [users["elodie@exemple.com"], users["alexandre@exemple.com"]], [
        {"Appartement vue mer Split", "510.00", -19},
        {"Ferry Jadrolinija Split-Hvar", "95.00", -18},
        {"Location scooter sur Hvar", "80.00", -16},
        {"Dîners konoba & poissons grillés", "190.00", -14}
      ]},

      # 60. Séjour Plongée Guadeloupe
      {"Séjour Plongée Guadeloupe", "EUR", "open", users["beatrice@exemple.com"], [users["clement@exemple.com"], users["delphine@exemple.com"]], [
        {"Bungalow Deshaies", "690.00", -17},
        {"Forfait plongée Réserve Cousteau", "450.00", -16},
        {"Location voiture", "260.00", -15},
        {"Repas colombo & rhum arrangé", "130.00", -13}
      ]},

      # 61. Weekend Budapest & Bains Széchenyi
      {"Weekend Budapest & Bains Széchenyi", "EUR", "open", users["eric@exemple.com"], [users["fanny@exemple.com"], users["gabriel@exemple.com"]], [
        {"Appartement centre Pest", "290.00", -12},
        {"Entrées Bains thermaux Széchenyi", "85.00", -11},
        {"Ruin bars de l'ancien quartier juif", "110.00", -10},
        {"Dîner croisière Danube", "95.00", -9}
      ]},

      # 62. Séjour Québec & Vieux-Port
      {"Séjour Québec & Vieux-Port", "CAD", "open", users["helene@exemple.com"], [users["julien@exemple.com"], users["karine@exemple.com"]], [
        {"Hôtel historique Vieux-Québec", "720.00", -16},
        {"Ferry Québec-Lévis", "25.00", -15},
        {"Chutes Montmorency & téléphérique", "65.00", -14},
        {"Dîner bistrot québécois", "180.00", -12}
      ]},

      # 63. Roadtrip Californie - Highway 1
      {"Roadtrip Californie - Highway 1", "USD", "open", users["laurent@exemple.com"], [users["manon@exemple.com"], users["nicolas@exemple.com"]], [
        {"Motels Big Sur et Monterey", "680.00", -25},
        {"Aquarium de Monterey", "160.00", -24},
        {"Essence stations côtières", "120.00", -22},
        {"Fruits de mer Morro Bay", "150.00", -20}
      ]},

      # 64. Séjour Édimbourg & Loch Ness
      {"Séjour Édimbourg & Loch Ness", "GBP", "open", users["olivia@exemple.com"], [users["pierre@exemple.com"], users["quentin@exemple.com"]], [
        {"Appartement Royal Mile", "540.00", -14},
        {"Château d'Édimbourg billets", "65.00", -13},
        {"Excursion guidée Loch Ness", "180.00", -12},
        {"Dîner pub & dégustation haggis", "115.00", -10}
      ]},

      # 65. Trek dans les Dolomites
      {"Trek dans les Dolomites", "EUR", "open", users["rachel@exemple.com"], [users["sebastien@exemple.com"], users["theo@exemple.com"]], [
        {"Refuges alpins 3 nuits", "480.00", -11},
        {"Location kits via ferrata", "90.00", -10},
        {"Ravitaillement pique-niques", "75.00", -9}
      ]},

      # 66. Weekend à Copenhague
      {"Weekend à Copenhague", "EUR", "open", users["valerie@exemple.com"], [users["william@exemple.com"], users["xavier@exemple.com"]], [
        {"Hôtel design Nyhavn", "620.00", -10},
        {"Location vélos danois", "70.00", -9},
        {"Jardins de Tivoli entrées & manèges", "130.00", -8},
        {"Smørrebrød gastronomiques", "110.00", -7}
      ]},

      # 67. Séjour Randonnée Réunion - Piton des Neiges
      {"Séjour Randonnée Réunion - Piton des Neiges", "EUR", "open", users["yasmine@exemple.com"], [users["zoe@exemple.com"], users["arthur@exemple.com"]], [
        {"Gîte de la Caverne Dufour", "260.00", -24},
        {"Location Dacia Duster", "310.00", -23},
        {"Ravitaillement randonnée Cilaos", "85.00", -22},
        {"Cari poulet & rougail saucisse", "75.00", -20}
      ]},

      # 68. Voyage à Chicago & Lac Michigan
      {"Voyage à Chicago & Lac Michigan", "USD", "open", users["ines@exemple.com"], [users["romain@exemple.com"], users["lucie@exemple.com"]], [
        {"Hôtel The Loop Chicago", "950.00", -30},
        {"Croisière d'architecture First Lady", "165.00", -28},
        {"Deep dish pizza chez Lou Malnati's", "85.00", -27},
        {"Pass musées Art Institute & Willis Tower", "210.00", -25}
      ]},

      # 69. Séjour Ski La Plagne
      {"Séjour Ski La Plagne", "EUR", "open", users["mathieu@exemple.com"], [users["clara@exemple.com"], users["vincent@exemple.com"]], [
        {"Chalet Plagne Centre", "890.00", -15},
        {"Forfaits ski Paradiski", "590.00", -14},
        {"Location matériel ski & snowboard", "240.00", -13},
        {"Courses station & fondue", "180.00", -12}
      ]},

      # 70. Weekend Découverte Vienne & Palais Hofburg
      {"Weekend Découverte Vienne & Palais Hofburg", "EUR", "open", users["sarah@exemple.com"], [users["benjamin@exemple.com"], users["elodie@exemple.com"]], [
        {"Appartement Spittelberg", "440.00", -8},
        {"Billets Château de Schönbrunn", "80.00", -7},
        {"Cafés viennois & Sachertorte", "55.00", -6},
        {"Concert classique église Saint-Charles", "120.00", -5}
      ]},

      # 71. Vacances Côte d'Azur - Hyères & Porquerolles
      {"Vacances Côte d'Azur - Hyères & Porquerolles", "EUR", "open", users["damien@exemple.com"], [users["justine@exemple.com"], users["pauline@exemple.com"]], [
        {"Appartement Giens vue mer", "750.00", -18},
        {"Navette bateau pour Porquerolles", "75.00", -17},
        {"Location VTT sur l'île", "90.00", -16},
        {"Poissons grillés port de Hyères", "160.00", -15}
      ]},

      # 72. Mariage de Nicolas & Sophie
      {"Mariage de Nicolas & Sophie", "EUR", "open", users["nicolas@exemple.com"], [users["sophie@exemple.com"], users["pierre@exemple.com"], users["quentin@exemple.com"]], [
        {"Location domaine de réception", "2500.00", -60},
        {"Acompte traiteur 100 personnes", "1800.00", -50},
        {"DJ & Sonorisation soirée", "850.00", -40},
        {"Fleuriste & centres de table", "450.00", -30}
      ]},

      # 73. Anniversaire Surprise 30 Ans Julien
      {"Anniversaire Surprise 30 Ans Julien", "EUR", "open", users["julien@exemple.com"], [users["laurent@exemple.com"], users["karine@exemple.com"], users["manon@exemple.com"]], [
        {"Salle des fêtes privatisée", "320.00", -5},
        {"Buffet dînatoire & mignardises", "210.00", -4},
        {"Cadeau commun montre connectée", "280.00", -3},
        {"Champagne & vins", "160.00", -2}
      ]},

      # 74. Gala Miage 2026 Promo Dauphine
      {"Gala Miage 2026 Promo Dauphine", "EUR", "open", users["theo@exemple.com"], [users["valerie@exemple.com"], users["william@exemple.com"], users["xavier@exemple.com"]], [
        {"Acompte péniche sur la Seine", "1500.00", -45},
        {"Traiteur cocktail dînatoire", "1200.00", -35},
        {"Photobooth & tirages illimités", "400.00", -25},
        {"Sécurité & vestiaire", "350.00", -15}
      ]},

      # 75. Festival Hellfest Clisson 2026
      {"Festival Hellfest Clisson 2026", "EUR", "open", users["arthur@exemple.com"], [users["ines@exemple.com"], users["romain@exemple.com"], users["lucie@exemple.com"]], [
        {"Pass 4 jours x4", "1360.00", -55},
        {"Tentes de camping Easy Camp", "220.00", -50},
        {"Recharges Cashless Hellfest", "400.00", -48},
        {"Barbecues & ravitaillement Leclerc", "180.00", -45}
      ]},

      # 76. Crémaillère Bastien & Marion
      {"Crémaillère Bastien & Marion", "EUR", "open", users["bastien@exemple.com"], [users["marion@exemple.com"], users["clotilde@exemple.com"], users["thibault@exemple.com"]], [
        {"Apéritif dînatoire & pizzas maison", "140.00", -4},
        {"Bières artisanales & vins bio", "95.00", -3},
        {"Cadeau commun plante d'intérieur géante", "110.00", -2}
      ]},

      # 77. BDE MIAGE - Soirée Intégration
      {"BDE MIAGE - Soirée Intégration", "EUR", "open", users["clotilde@exemple.com"], [users["thibault@exemple.com"], users["nadege@exemple.com"], users["vincent@exemple.com"]], [
        {"Privatisation club étudiant", "650.00", -12},
        {"Fûts de bière & softs", "380.00", -10},
        {"Bracelets fluo & gobelets réutilisables", "75.00", -8},
        {"Pizzas pour l'équipe orga", "90.00", -7}
      ]},

      # 78. Fête des Voisins Résidence Saint-Louis
      {"Fête des Voisins Résidence Saint-Louis", "EUR", "open", users["sarah@exemple.com"], [users["benjamin@exemple.com"], users["elodie@exemple.com"], users["damien@exemple.com"]], [
        {"Barnums & tables pliantes", "160.00", -6},
        {"Barbecue collectif & saucisses", "130.00", -5},
        {"Boissons & jus de fruits", "70.00", -4}
      ]},

      # 79. Projet Startup SaaS AI Agent
      {"Projet Startup SaaS AI Agent", "EUR", "open", users["justine@exemple.com"], [users["pauline@exemple.com"], users["florian@exemple.com"]], [
        {"Abonnement serveurs Cloud Hetzner", "89.00", -14},
        {"Crédits API LLM OpenAI / Anthropic", "250.00", -12},
        {"Nom de domaine .io & DNS", "45.00", -10}
      ]},

      # 80. Tournoi de Tennis Club Rive Gauche
      {"Tournoi de Tennis Club Rive Gauche", "EUR", "open", users["adrien@exemple.com"], [users["marion@exemple.com"], users["bastien@exemple.com"]], [
        {"Location courts terre battue", "180.00", -8},
        {"Cartons de balles Babolat Roland Garros", "65.00", -7},
        {"Coupes & médailles vainqueurs", "85.00", -6},
        {"Apéro de remise des prix", "95.00", -5}
      ]},

      # 81. Session Karting 500cc Racing
      {"Session Karting 500cc Racing", "EUR", "open", users["alexandre@exemple.com"], [users["beatrice@exemple.com"], users["clement@exemple.com"], users["delphine@exemple.com"]], [
        {"Grand Prix 30 min chrono x4", "240.00", -9},
        {"Location cagoules & casques", "24.00", -9},
        {"Pizzas d'après-course", "70.00", -9}
      ]},

      # 82. Stage de Voile Les Glénans
      {"Stage de Voile Les Glénans", "EUR", "open", users["eric@exemple.com"], [users["fanny@exemple.com"], users["gabriel@exemple.com"]], [
        {"Stage catamaran 5 jours", "850.00", -25},
        {"Location cirés étanches", "90.00", -24},
        {"Courses collectives Concarneau", "160.00", -23}
      ]},

      # 83. LAN Party Counter-Strike & Valorant
      {"LAN Party Counter-Strike & Valorant", "EUR", "open", users["julien@exemple.com"], [users["karine@exemple.com"], users["laurent@exemple.com"], users["manon@exemple.com"]], [
        {"Switch réseau gigabit 24 ports", "65.00", -7},
        {"Commande géante Dominos Pizza", "110.00", -6},
        {"Boissons énergisantes & snacks", "45.00", -6}
      ]},

      # 84. Escape Game & Pizzeria Napolitaine
      {"Escape Game & Pizzeria Napolitaine", "EUR", "open", users["pierre@exemple.com"], [users["quentin@exemple.com"], users["rachel@exemple.com"], users["sebastien@exemple.com"]], [
        {"Session escape room Enigma", "136.00", -5},
        {"Dîner pizzeria napolitaine", "105.00", -5}
      ]},

      # 85. Association Maraude Étudiante
      {"Association Maraude Étudiante", "EUR", "open", users["valerie@exemple.com"], [users["william@exemple.com"], users["xavier@exemple.com"]], [
        {"Thermos géants 5 litres x2", "60.00", -15},
        {"Café, thé & chocolat en poudre", "45.00", -14},
        {"Gobelets en carton & serviettes", "25.00", -12},
        {"Sandwiches & soupes chaudes", "80.00", -10}
      ]},

      # 86. Club Œnologie & Dégustation Vins
      {"Club Œnologie & Dégustation Vins", "EUR", "open", users["zoe@exemple.com"], [users["arthur@exemple.com"], users["ines@exemple.com"]], [
        {"Sélection 6 crus de Bourgogne & Bordeaux", "240.00", -11},
        {"Fromages affinés & charcuterie corse", "95.00", -10},
        {"Pains artisanaux au levain", "22.00", -10}
      ]},

      # 87. Atelier Photographie de Nuit
      {"Atelier Photographie de Nuit", "EUR", "open", users["romain@exemple.com"], [users["lucie@exemple.com"], users["mathieu@exemple.com"]], [
        {"Location objectifs f/1.4 plein format", "120.00", -8},
        {"Trépieds carbone de voyage", "80.00", -7},
        {"Cafés chauds nocturnes", "20.00", -6}
      ]},

      # 88. Barbecue & Tournoi de Pétanque
      {"Barbecue & Tournoi de Pétanque", "EUR", "open", users["clara@exemple.com"], [users["vincent@exemple.com"], users["sarah@exemple.com"], users["benjamin@exemple.com"]], [
        {"Côtes de bœuf & saucisses", "115.00", -6},
        {"Triplettes Obut de compétition", "70.00", -5},
        {"Pastis artisanal & rosé de Provence", "55.00", -4}
      ]},

      # =======================================================================
      # PENDING SETTLEMENT WALLETS (Background)
      # =======================================================================

      # 89. Séjour Plongée Mer Rouge
      {"Séjour Plongée Mer Rouge", "EUR", "pending_settlement", users["sebastien@exemple.com"], [users["valerie@exemple.com"], users["william@exemple.com"]], [
        {"Hôtel plongée El Gouna", "890.00", -17},
        {"Forfait 10 plongées PADI", "650.00", -16},
        {"Location équipement complet", "210.00", -15}
      ]},

      # 90. Séjour Évasion à Kyoto
      {"Séjour Évasion à Kyoto", "USD", "pending_settlement", users["alexandre@exemple.com"], [users["julien@exemple.com"], users["laurent@exemple.com"]], [
        {"Machiya traditionnelle Gion", "950.00", -21},
        {"Cérémonie du thé & kimonos", "180.00", -20},
        {"Repas kaiseki gastronomique", "320.00", -19}
      ]},

      # 91. Weekend à Porto & Vallée du Douro
      {"Weekend à Porto & Vallée du Douro", "EUR", "pending_settlement", users["clement@exemple.com"], [users["delphine@exemple.com"], users["eric@exemple.com"]], [
        {"AirBnB Ribeira vue fleuve", "460.00", -14},
        {"Croisière sur le Douro", "90.00", -13},
        {"Dégustation caves de Porto Caves Cálem", "75.00", -12},
        {"Francesinhas & bières Super Bock", "65.00", -11}
      ]},

      # 92. Séjour Ski Val Thorens
      {"Séjour Ski Val Thorens", "EUR", "pending_settlement", users["fanny@exemple.com"], [users["gabriel@exemple.com"], users["helene@exemple.com"]], [
        {"Appartement plein sud Val Thorens", "1100.00", -22},
        {"Forfaits 3 Vallées", "740.00", -21},
        {"Location skis haut de gamme", "280.00", -20}
      ]},

      # 93. Roadtrip Floride & Key West
      {"Roadtrip Floride & Key West", "USD", "pending_settlement", users["karine@exemple.com"], [users["laurent@exemple.com"], users["manon@exemple.com"]], [
        {"Location Ford Mustang Cabriolet", "690.00", -30},
        {"Hôtels Miami Beach & Key West", "1250.00", -29},
        {"Excursion airboat Everglades", "140.00", -27}
      ]},

      # 94. Séjour Randonnée Açores
      {"Séjour Randonnée Açores", "EUR", "pending_settlement", users["nicolas@exemple.com"], [users["olivia@exemple.com"], users["pierre@exemple.com"]], [
        {"Maison São Miguel avec jardin", "580.00", -16},
        {"Location 4x4", "260.00", -15},
        {"Cozido das Furnas géothermique", "95.00", -14}
      ]},

      # 95. Weekend Découverte Séville
      {"Weekend Découverte Séville", "EUR", "pending_settlement", users["quentin@exemple.com"], [users["rachel@exemple.com"], users["sebastien@exemple.com"]], [
        {"Appartement quartier Triana", "410.00", -11},
        {"Spectacle flamenco traditionnel", "85.00", -10},
        {"Tapas & Sangria bar El Rinconcillo", "120.00", -9}
      ]},

      # 96. Séjour Londres Shopping & Musées
      {"Séjour Londres Shopping & Musées", "GBP", "pending_settlement", users["theo@exemple.com"], [users["valerie@exemple.com"], users["william@exemple.com"]], [
        {"Hôtel Bloomsbury", "720.00", -18},
        {"Billets Tower of London & The Shard", "140.00", -17},
        {"Dîner pub & burgers", "110.00", -16}
      ]},

      # 97. Voyage Canada Ouest - Rocheuses
      {"Voyage Canada Ouest - Rocheuses", "CAD", "pending_settlement", users["xavier@exemple.com"], [users["yasmine@exemple.com"], users["zoe@exemple.com"]], [
        {"Cabines Banff et Jasper", "1400.00", -35},
        {"Pass Parcs Canada découverte", "150.00", -34},
        {"Location VUS 4x4", "550.00", -33}
      ]},

      # 98. Weekend Ski Serre Chevalier
      {"Weekend Ski Serre Chevalier", "EUR", "pending_settlement", users["arthur@exemple.com"], [users["ines@exemple.com"], users["romain@exemple.com"]], [
        {"Chalet Briançon", "680.00", -20},
        {"Forfaits ski 3 jours", "420.00", -19},
        {"Repas montagnard fondue", "110.00", -18}
      ]},

      # 99. Séjour Corse du Nord - Calvi & Balagne
      {"Séjour Corse du Nord - Calvi & Balagne", "EUR", "pending_settlement", users["lucie@exemple.com"], [users["mathieu@exemple.com"], users["clara@exemple.com"]], [
        {"Résidence pieds dans l'eau Calvi", "820.00", -25},
        {"Ferry Bastia AR", "290.00", -24},
        {"Location bateau pour Scandola", "220.00", -22}
      ]},

      # 100. Weekend Genève & Lac Léman
      {"Weekend Genève & Lac Léman", "CHF", "pending_settlement", users["vincent@exemple.com"], [users["sarah@exemple.com"], users["benjamin@exemple.com"]], [
        {"Hôtel vue lac Genève", "640.00", -12},
        {"Croisière sur le Léman", "90.00", -11},
        {"Fondue Les Armures vieille ville", "155.00", -10}
      ]},

      # 101. Séjour Surf Lacanau & Médoc
      {"Séjour Surf Lacanau & Médoc", "EUR", "pending_settlement", users["elodie@exemple.com"], [users["damien@exemple.com"], users["justine@exemple.com"]], [
        {"Maison sous les pins Lacanau Océan", "550.00", -15},
        {"Location surfs & cours débutants", "180.00", -14},
        {"Dégustation châteaux du Médoc", "95.00", -13}
      ]},

      # 102. EVJF à Marrakech
      {"EVJF à Marrakech", "EUR", "pending_settlement", users["pauline@exemple.com"], [users["florian@exemple.com"], users["adrien@exemple.com"]], [
        {"Riad privatisé dans la Médina", "980.00", -20},
        {"Journée spa & hammam traditionnel", "240.00", -19},
        {"Dîner spectacle dans le désert d'Agafay", "310.00", -18}
      ]},

      # 103. EVG à Budapest
      {"EVG à Budapest", "EUR", "pending_settlement", users["marion@exemple.com"], [users["bastien@exemple.com"], users["clotilde@exemple.com"]], [
        {"Appartement géant centre-ville", "610.00", -17},
        {"Location beer-bike 2 heures", "160.00", -16},
        {"Bains thermaux de nuit Sparty", "180.00", -15}
      ]},

      # 104. Tournoi de Football inter-promos
      {"Tournoi de Football inter-promos", "EUR", "pending_settlement", users["thibault@exemple.com"], [users["nadege@exemple.com"], users["vincent@exemple.com"]], [
        {"Arbitres officiels & terrains", "310.00", -10},
        {"Coupes & médailles", "95.00", -9},
        {"Buffet de clôture", "140.00", -8}
      ]},

      # 105. Soirée Halloween Manoir Hanté
      {"Soirée Halloween Manoir Hanté", "EUR", "pending_settlement", users["sarah@exemple.com"], [users["benjamin@exemple.com"], users["elodie@exemple.com"]], [
        {"Privatisation manoir désaffecté", "490.00", -14},
        {"Déguisements & maquillage SFX", "160.00", -13},
        {"Traiteur buffet thème horreur", "190.00", -12}
      ]},

      # 106. Séminaire Startup Tech & Product
      {"Séminaire Startup Tech & Product", "EUR", "pending_settlement", users["damien@exemple.com"], [users["justine@exemple.com"], users["pauline@exemple.com"]], [
        {"Chalet séminaire Annecy", "1450.00", -28},
        {"Activités team building parapente", "480.00", -27},
        {"Dîners gastronomiques", "520.00", -26}
      ]},

      # 107. Hackathon GreenTech Climat
      {"Hackathon GreenTech Climat", "EUR", "pending_settlement", users["florian@exemple.com"], [users["adrien@exemple.com"], users["marion@exemple.com"]], [
        {"Hébergement & serveurs AWS", "210.00", -9},
        {"Pizzas, sushis & café pour 48h", "280.00", -8},
        {"Lots gagnants & goodies écologiques", "150.00", -7}
      ]},

      # 108. Colocation Rouen Saint-Marc
      {"Colocation Rouen Saint-Marc", "EUR", "pending_settlement", users["bastien@exemple.com"], [users["clotilde@exemple.com"], users["thibault@exemple.com"]], [
        {"Régularisation charges annuelles eau", "210.00", -18},
        {"Peinture & rafraîchissement salon", "140.00", -16},
        {"Réparation lave-linge", "95.00", -14}
      ]},

      # =======================================================================
      # CLOSED WALLETS (Background: Fully reconciled & archived)
      # =======================================================================

      # 109. Weekend Prague & Vltava
      {"Weekend Prague & Vltava", "EUR", "closed", users["olivia@exemple.com"], [users["quentin@exemple.com"], users["rachel@exemple.com"]], [
        {"Appartement Vieille Ville", "310.00", -85},
        {"Dîner croisière Vltava", "120.00", -84},
        {"Brasserie U Fleku", "75.00", -83}
      ]},

      # 110. Weekend Canoë Gorges du Tarn
      {"Weekend Canoë Gorges du Tarn", "EUR", "closed", users["clara@exemple.com"], [users["sarah@exemple.com"], users["elodie@exemple.com"]], [
        {"Camping bord de rivière", "140.00", -100},
        {"Descente canoë 20km", "95.00", -99},
        {"Barbecue & grillades", "65.00", -98}
      ]},

      # 111. Roadtrip Norvège - Fjords & Geiranger
      {"Roadtrip Norvège - Fjords & Geiranger", "EUR", "closed", users["alexandre@exemple.com"], [users["beatrice@exemple.com"], users["clement@exemple.com"]], [
        {"Location voiture hybride Bergen", "710.00", -110},
        {"Hytter chalets traditionnels", "890.00", -108},
        {"Ferry Geirangerfjord", "140.00", -107}
      ]},

      # 112. Vacances Sardaigne & Costa Smeralda
      {"Vacances Sardaigne & Costa Smeralda", "EUR", "closed", users["delphine@exemple.com"], [users["eric@exemple.com"], users["fanny@exemple.com"]], [
        {"Villa avec terrasse Olbia", "940.00", -125},
        {"Location bateau pour La Maddalena", "280.00", -124},
        {"Restaurants de poissons", "210.00", -123}
      ]},

      # 113. Weekend Ski Méribel 2025
      {"Weekend Ski Méribel 2025", "EUR", "closed", users["gabriel@exemple.com"], [users["helene@exemple.com"], users["julien@exemple.com"]], [
        {"Résidence Les Allues", "850.00", -140},
        {"Forfaits ski 3 jours", "510.00", -139},
        {"Soirée raclette restaurant", "140.00", -138}
      ]},

      # 114. Séjour à Malte & Gozo
      {"Séjour à Malte & Gozo", "EUR", "closed", users["karine@exemple.com"], [users["laurent@exemple.com"], users["manon@exemple.com"]], [
        {"Hôtel vue baie La Valette", "620.00", -130},
        {"Ferry pour Gozo & Blue Lagoon", "85.00", -129},
        {"Dîner Saint-Julian's", "145.00", -128}
      ]},

      # 115. Voyage Toronto & Chutes du Niagara
      {"Voyage Toronto & Chutes du Niagara", "CAD", "closed", users["nicolas@exemple.com"], [users["olivia@exemple.com"], users["pierre@exemple.com"]], [
        {"Hôtel Downtown Toronto", "890.00", -150},
        {"Croisière Maid of the Mist Niagara", "120.00", -149},
        {"Tour CN Tower billets", "110.00", -148}
      ]},

      # 116. Weekend à Dublin & Temple Bar
      {"Weekend à Dublin & Temple Bar", "EUR", "closed", users["quentin@exemple.com"], [users["rachel@exemple.com"], users["sebastien@exemple.com"]], [
        {"Appartement Georgian Quarter", "490.00", -105},
        {"Guinness Storehouse entrées & pintes", "80.00", -104},
        {"Pubs & musique irlandaise", "150.00", -103}
      ]},

      # 117. Séjour Surf Hossegor
      {"Séjour Surf Hossegor", "EUR", "closed", users["theo@exemple.com"], [users["valerie@exemple.com"], users["william@exemple.com"]], [
        {"Maison sous les pins", "650.00", -115},
        {"Location combis & planches", "190.00", -114},
        {"Dîners cabane d'huîtres lac d'Hossegor", "130.00", -113}
      ]},

      # 118. Vacances Baléares - Minorque
      {"Vacances Baléares - Minorque", "EUR", "closed", users["xavier@exemple.com"], [users["yasmine@exemple.com"], users["zoe@exemple.com"]], [
        {"Finca rurale Ciutadella", "880.00", -135},
        {"Location Fiat 500", "220.00", -134},
        {"Tapas & caldereta de langosta", "195.00", -133}
      ]},

      # 119. Weekend Découverte Stockholm
      {"Weekend Découverte Stockholm", "EUR", "closed", users["arthur@exemple.com"], [users["ines@exemple.com"], users["romain@exemple.com"]], [
        {"Hôtel Gamla Stan", "590.00", -120},
        {"Musée Vasa & Musée ABBA", "95.00", -119},
        {"Ferry archipel de Stockholm", "60.00", -118}
      ]},

      # 120. Séjour Randonnée Vanoise
      {"Séjour Randonnée Vanoise", "EUR", "closed", users["lucie@exemple.com"], [users["mathieu@exemple.com"], users["clara@exemple.com"]], [
        {"Refuges du Parc de la Vanoise", "410.00", -145},
        {"Pique-niques et ravitaillement Pralognan", "90.00", -144},
        {"Cartes IGN & topos", "35.00", -143}
      ]},

      # 121. Séjour Ski Alpe d'Huez 2025
      {"Séjour Ski Alpe d'Huez 2025", "EUR", "closed", users["vincent@exemple.com"], [users["sarah@exemple.com"], users["benjamin@exemple.com"]], [
        {"Chalet Bergers", "980.00", -160},
        {"Forfaits ski La Sarenne", "580.00", -159},
        {"Courses d'altitude", "190.00", -158}
      ]},

      # 122. Weekend Londres Musées 2025
      {"Weekend Londres Musées 2025", "GBP", "closed", users["elodie@exemple.com"], [users["damien@exemple.com"], users["justine@exemple.com"]], [
        {"Hôtel Kensington", "510.00", -170},
        {"Tea time anglais", "90.00", -169},
        {"Comédie musicale West End", "180.00", -168}
      ]},

      # 123. Soirée Casino & Cocktails
      {"Soirée Casino & Cocktails", "EUR", "closed", users["pauline@exemple.com"], [users["florian@exemple.com"], users["adrien@exemple.com"]], [
        {"Tenues de soirée & jetons", "200.00", -80},
        {"Dîner au restaurant du casino", "160.00", -80},
        {"Cocktails au bar lounge", "85.00", -80}
      ]},

      # 124. Mariage de Clément & Karine 2025
      {"Mariage de Clément & Karine 2025", "EUR", "closed", users["clement@exemple.com"], [users["karine@exemple.com"], users["alexandre@exemple.com"]], [
        {"Cadeau commun voyage de noces", "1200.00", -190},
        {"Album photo souvenir personnalisé", "150.00", -189},
        {"Brunch du lendemain", "350.00", -188}
      ]},

      # 125. Festival Garorock Marmande 2025
      {"Festival Garorock Marmande 2025", "EUR", "closed", users["marion@exemple.com"], [users["bastien@exemple.com"], users["clotilde@exemple.com"]], [
        {"Pass 4 jours Garorock", "720.00", -175},
        {"Camping tente tipi", "180.00", -174},
        {"Restauration & boissons", "240.00", -173}
      ]},

      # 126. BDE MIAGE - Weekend d'Intégration 2025
      {"BDE MIAGE - Weekend d'Intégration 2025", "EUR", "closed", users["thibault@exemple.com"], [users["nadege@exemple.com"], users["vincent@exemple.com"]], [
        {"Camping privatisé bord de lac", "1800.00", -210},
        {"Repas collectifs & petits-déjeuners", "950.00", -209},
        {"Sono & animations jeux gonflables", "600.00", -208}
      ]},

      # 127. Soirée Noël Entreprise Promo 2025
      {"Soirée Noël Entreprise Promo 2025", "EUR", "closed", users["sarah@exemple.com"], [users["benjamin@exemple.com"], users["elodie@exemple.com"]], [
        {"Secret Santa cadeaux décalés", "120.00", -110},
        {"Bûche pâtissière & chocolats", "85.00", -110},
        {"Traiteur cocktail de Noël", "290.00", -110}
      ]},

      # 128. Tournoi Padel Printemps 2025
      {"Tournoi Padel Printemps 2025", "EUR", "closed", users["damien@exemple.com"], [users["justine@exemple.com"], users["pauline@exemple.com"]], [
        {"Location terrains Casa Padel", "160.00", -130},
        {"Balles & raquettes test", "50.00", -130},
        {"Tapas après-match", "75.00", -130}
      ]},

      # 129. Gala des Diplômés 2025
      {"Gala des Diplômés 2025", "EUR", "closed", users["florian@exemple.com"], [users["adrien@exemple.com"], users["marion@exemple.com"]], [
        {"Location salle des fêtes de l'Hôtel de Ville", "950.00", -240},
        {"Photographe professionnel de soirée", "450.00", -239},
        {"Buffet de mignardises & champagne", "800.00", -238}
      ]},

      # 130. Colocation Nice Promenade
      {"Colocation Nice Promenade", "EUR", "closed", users["bastien@exemple.com"], [users["clotilde@exemple.com"], users["thibault@exemple.com"]], [
        {"Climatiseur réversible d'occasion", "220.00", -90},
        {"Peinture terrasse extérieure", "75.00", -89},
        {"Dîner de clôture de bail", "110.00", -88}
      ]}
    ]

    for {name, currency, status, creator, members, expenses} <- background_wallets do
      # If status is closed, create as pending_settlement first, add expenses, then auto-settle to closed
      initial_status = if status == "closed", do: "pending_settlement", else: status

      {w, m_map} =
        create_wallet_with_members(
          creator,
          name,
          "Porte-monnaie partagé créé pour #{name}",
          currency,
          initial_status,
          members
        )

      all_members = [creator | members]

      # Add expenses distributed among members
      expenses
      |> Enum.with_index()
      |> Enum.each(fn {{exp_name, amount, days_ago}, idx} ->
        payer = Enum.at(all_members, rem(idx, length(all_members)))
        add_expense(w, m_map[payer.id], creator, exp_name, amount, days_ago, nil, currency)
      end)

      # If closed, auto-settle all transfers using official domain logic
      if status == "closed" do
        LesBonsComptes.Expenses.mock_settle_all(w)
      end
    end

    # Add extra background invitations between regular users to enrich invitations view
    create_invitation(w1, admin, users["lucie@exemple.com"], "pending")
    create_invitation(w2, admin, users["mathieu@exemple.com"], "pending")
    create_invitation(w5, admin, users["clara@exemple.com"], "declined")
    create_invitation(w8, admin, users["vincent@exemple.com"], "pending")
    create_invitation(w10, admin, users["sarah@exemple.com"], "pending")
    create_invitation(w13, admin, users["benjamin@exemple.com"], "pending")
    create_invitation(w14, admin, users["elodie@exemple.com"], "accepted")
    create_invitation(w15, admin, users["damien@exemple.com"], "pending")
    create_invitation(w18, thomas, users["justine@exemple.com"], "pending")
    create_invitation(w20, lucas, users["pauline@exemple.com"], "pending")
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_wallet_with_members(creator, name, description, currency, status, other_users) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    # Insert wallet
    wallet =
      Repo.insert!(%Wallet{
        name: name,
        description: description,
        currency: currency,
        status: status,
        creator_id: creator.id,
        inserted_at: now,
        updated_at: now
      })

    # Owner member
    owner_member =
      Repo.insert!(%WalletMember{
        wallet_id: wallet.id,
        user_id: creator.id,
        name: creator.name,
        email: creator.email,
        role: "owner",
        inserted_at: now,
        updated_at: now
      })

    # Initial members map: user_id => WalletMember
    members_map =
      Enum.reduce(other_users, %{creator.id => owner_member}, fn user, acc ->
        member =
          Repo.insert!(%WalletMember{
            wallet_id: wallet.id,
            user_id: user.id,
            name: user.name,
            email: user.email,
            role: "member",
            inserted_at: now,
            updated_at: now
          })

        Map.put(acc, user.id, member)
      end)

    {wallet, members_map}
  end

  defp add_expense(wallet, payer_member, created_by, title, amount, days_ago, description, currency \\ nil) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    expense_date = Date.add(Date.utc_today(), days_ago)

    Repo.insert!(%Expense{
      wallet_id: wallet.id,
      payer_id: payer_member.id,
      created_by_id: created_by.id,
      title: title,
      amount: Decimal.new(amount),
      date: expense_date,
      description: description,
      currency: currency || wallet.currency,
      inserted_at: now,
      updated_at: now
    })
  end

  defp record_settlement(wallet, from_member, to_member, amount, days_ago) do
    now =
      DateTime.utc_now()
      |> DateTime.add(days_ago * 86400, :second)
      |> DateTime.truncate(:second)

    Repo.insert!(%Settlement{
      wallet_id: wallet.id,
      from_id: from_member.id,
      to_id: to_member.id,
      amount: Decimal.new(amount),
      currency: wallet.currency,
      settled_at: now,
      inserted_at: now,
      updated_at: now
    })
  end

  defp create_invitation(wallet, inviter, invitee, status) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(%WalletInvitation{
      wallet_id: wallet.id,
      inviter_id: inviter.id,
      invitee_id: invitee.id,
      email: invitee.email,
      status: status,
      inserted_at: now,
      updated_at: now
    })
  end

  defp print_summary do
    user_count = Repo.aggregate(User, :count)
    wallet_count = Repo.aggregate(Wallet, :count)
    expense_count = Repo.aggregate(Expense, :count)
    member_count = Repo.aggregate(WalletMember, :count)
    invitation_count = Repo.aggregate(WalletInvitation, :count)
    settlement_count = Repo.aggregate(Settlement, :count)

    open_count = Repo.one(from w in Wallet, where: w.status == "open", select: count())
    pending_count = Repo.one(from w in Wallet, where: w.status == "pending_settlement", select: count())
    closed_count = Repo.one(from w in Wallet, where: w.status == "closed", select: count())

    IO.puts("""

  =============================================================================
  ✨ [IF-10] LARGE-SCALE DATASET SUCCESSFULLY CREATED
  =============================================================================
  👤 Registered Users:      #{user_count}
  💼 Shared Wallets:         #{wallet_count}
     - 🟢 Open:             #{open_count}
     - 🟡 Pending transfers:#{pending_count}
     - ⚫ Closed:           #{closed_count}
  👥 Wallet Memberships:     #{member_count}
  🧾 Total Expenses:         #{expense_count}
  ✉️  Wallet Invitations:    #{invitation_count}
  💳 Recorded Settlements:   #{settlement_count}

  🎯 Demo Account Credentials:
     Email:    admin@exemple.com
     Password: admin123
     (All other 59 accounts use password: password123)
  =============================================================================
  """)
  end
end
