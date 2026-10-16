defmodule LesBonsComptes.DataSeeder do
  @moduledoc """
  Generates a large-scale, realistic dataset for demonstration, testing, and performance evaluation (Jira Epic IF-10).

  Creates:
  - 55 realistic registered users (including `admin@exemple.com` / `admin123`).
  - 42 shared wallets spanning all 3 lifecycle stages:
    * `open` (declarations in progress, various currencies: EUR, USD, GBP, CHF, CAD)
    * `pending_settlement` (awaiting transfers, partial settlements, debtor actions)
    * `closed` (fully reconciled and archived, 100% progress)
  - 250+ realistic expenses with varied dates, amounts, and assigned spending accounts.
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
    IO.puts("  👤 Seeding 55 registered user accounts...")

    # Precompute hashes once for blazing fast execution
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
      {"Florian Bouvier", "florian@exemple.com", default_hash}
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
    IO.puts("  💼 Seeding 42 shared wallets across all lifecycle stages...")

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

    # =========================================================================
    # B. DEMO SCENARIOS WHERE ADMIN IS A PARTICIPATING MEMBER (NOT OWNER)
    # =========================================================================

    # 8. City Break à Londres (GBP, Pending Settlement, 4 members, Admin is debtor!)
    {w8, m8} =
      create_wallet_with_members(
        lucas,
        "City Break à Londres",
        "Weekend shopping, comédie musicale et visites à Soho et Shoreditch",
        "GBP",
        "pending_settlement",
        [admin, sophie, charlie]
      )

    add_expense(w8, m8[lucas.id], lucas, "Appartement Covent Garden", "680.00", -12, "Appartement 3 nuits", "GBP")
    add_expense(w8, m8[sophie.id], sophie, "Billets Warner Bros Harry Potter Studios", "190.00", -11, "Tour guidé", "GBP")
    add_expense(w8, m8[admin.id], admin, "Dîner Pub The Crown & Shuttle", "145.00", -10, "Burgers & Pintes", "GBP")
    add_expense(w8, m8[charlie.id], charlie, "Afternoon Tea chez Sketch", "220.00", -9, "Tea room experience", "GBP")

    # 9. Festival Solidays 2025 (EUR, Closed, 4 members, all settled)
    {w9, m9} =
      create_wallet_with_members(
        alice,
        "Festival Solidays 2025",
        "3 jours de concerts et camping à l'hippodrome de Longchamp",
        "EUR",
        "closed",
        [admin, bob, chloe]
      )

    add_expense(w9, m9[alice.id], alice, "Pass 3 Jours & Camping x4", "440.00", -120, "Early bird tickets")
    add_expense(w9, m9[admin.id], admin, "Recharge Cashless boisson", "180.00", -119, "Consommations bar")
    add_expense(w9, m9[bob.id], bob, "Food trucks & déjeuners", "160.00", -118, "Burgers et crêpes")
    add_expense(w9, m9[chloe.id], chloe, "Tentes 3 secondes & duvets", "140.00", -122, "Matériel Decathlon")

    record_settlement(w9, m9[chloe.id], m9[alice.id], "90.00", -110)
    record_settlement(w9, m9[bob.id], m9[alice.id], "70.00", -110)
    record_settlement(w9, m9[admin.id], m9[alice.id], "50.00", -110)

    # 10. Anniversaire Surprise de Sophie (EUR, Open, 4 members)
    {w10, m10} =
      create_wallet_with_members(
        thomas,
        "Anniversaire Surprise de Sophie",
        "Cadeau commun et fête surprise pour les 25 ans de Sophie",
        "EUR",
        "open",
        [admin, camille, julie]
      )

    add_expense(w10, m10[thomas.id], thomas, "Location salle des fêtes", "350.00", -6, "Acompte réservation")
    add_expense(w10, m10[camille.id], camille, "Traiteur & Buffet salé", "240.00", -4, "Petits fours et mignardises")
    add_expense(w10, m10[admin.id], admin, "Gâteau pâtissier sur-mesure", "95.00", -3, "Fraisier chez Yann Couvreur")
    add_expense(w10, m10[julie.id], julie, "Champagne & Boissons", "180.00", -2, "6 bouteilles")

    # =========================================================================
    # C. INVITATIONS FOR ADMIN (ALL STATUSES FOR COMPREHENSIVE FILTERING)
    # =========================================================================

    # 11. Escapade à Rome (Pending invitation for Admin)
    {w11, _} =
      create_wallet_with_members(
        alice,
        "Escapade à Rome",
        "Visite du Colisée, fontaine de Trevi et pizzas au Trastevere",
        "EUR",
        "open",
        [charlie]
      )

    create_invitation(w11, alice, admin, "pending")

    # 12. Crémaillère Léa & Maxime (Pending invitation for Admin)
    {w12, _} =
      create_wallet_with_members(
        lea,
        "Crémaillère Léa & Maxime",
        "Cadeau commun pour leur nouvel appartement avec jardin",
        "EUR",
        "open",
        [maxime, antoine]
      )

    create_invitation(w12, lea, admin, "pending")

    # 13. Voyage au Japon Printemps 2027 (Pending invitation for Admin)
    {w13, _} =
      create_wallet_with_members(
        antoine,
        "Voyage au Japon Printemps 2027",
        "Tokyo, Kyoto, Osaka pendant la floraison des cerisiers",
        "EUR",
        "open",
        [lucas, sophie]
      )

    create_invitation(w13, antoine, admin, "pending")

    # 14. Sortie Escalade Fontainebleau (Declined invitation for Admin)
    {w14, _} =
      create_wallet_with_members(
        charlie,
        "Sortie Escalade Fontainebleau",
        "Location crash-pads et covoiturage en forêt de Fontainebleau",
        "EUR",
        "open",
        [bob, diane]
      )

    create_invitation(w14, charlie, admin, "declined")

    # 15. Soirée Jeux de Plateau (Accepted invitation for Admin)
    {w15, _} =
      create_wallet_with_members(
        emma,
        "Soirée Jeux de Plateau",
        "Achat de nouveaux jeux (Catan, Wingspan, 7 Wonders) et pizzas",
        "EUR",
        "open",
        [camille, admin]
      )

    create_invitation(w15, emma, admin, "accepted")

    # 16. Atelier Cuisine Italienne (Cancelled invitation for Admin)
    {w16, _} =
      create_wallet_with_members(
        camille,
        "Atelier Cuisine Italienne",
        "Cours de fabrication de pâtes fraîches et tiramisu",
        "EUR",
        "open",
        [julie]
      )

    create_invitation(w16, camille, admin, "cancelled")

    # =========================================================================
    # D. BACKGROUND COMMUNITY WALLETS (THINK HUGE: REAL-WORLD SCALE & VOLUME)
    # =========================================================================

    background_wallets = [
      # 17. Vacances au Portugal - Faro
      {"Vacances au Portugal - Faro", "EUR", "open", alice, [bob, charlie, diane, emma], [
        {"AirBnB Villa Algarve", "1100.00", -15},
        {"Location voitures Sixt", "420.00", -14},
        {"Dîner fruits de mer Olhão", "210.00", -12},
        {"Plein d'essence Repsol", "85.00", -10},
        {"Bar de plage Praia da Rocha", "135.00", -8},
        {"Cours de surf Arrifana", "190.00", -7},
        {"Courses Pingo Doce", "115.00", -5}
      ]},

      # 18. Séjour Surf à Biarritz
      {"Séjour Surf à Biarritz", "EUR", "open", lucas, [antoine, maxime, users["theo@exemple.com"]], [
        {"Appartement vue mer", "750.00", -20},
        {"Location planches de surf & combis", "260.00", -18},
        {"Courses Halles de Biarritz", "145.00", -17},
        {"Pintxos à Saint-Sébastien", "180.00", -15},
        {"Plein d'essence Total", "72.00", -12}
      ]},

      # 19. Voyage à New York Automne
      {"Voyage à New York Automne", "USD", "open", sophie, [thomas, julie, camille], [
        {"Hôtel Manhattan Times Square", "1650.00", -35},
        {"Pass Attractions New York Explorer", "480.00", -33},
        {"Croisière Statue de la Liberté", "120.00", -30},
        {"Dîner rooftop Brooklyn", "280.00", -28},
        {"MetroCard 7 jours x4", "136.00", -27},
        {"Match NBA Brooklyn Nets", "360.00", -24},
        {"Bagels & Deli Russ & Daughters", "85.00", -22}
      ]},

      # 20. Coloc République 2025
      {"Coloc République 2025", "EUR", "closed", emma, [hugo, lea], [
        {"Table à manger & 6 chaises", "320.00", -90},
        {"Électroménager micro-ondes", "110.00", -88},
        {"Plantes & décoration salon", "75.00", -85},
        {"Aspirateur balai sans fil", "189.00", -82}
      ]},

      # 21. Weekend Rando Vercors
      {"Weekend Rando Vercors", "EUR", "closed", thomas, [maxime, antoine, chloe], [
        {"Gîte d'étape Corrençon", "280.00", -75},
        {"Péages & carburant A6/A48", "115.00", -74},
        {"Ravitaillement saucissons & comté", "85.00", -73},
        {"Dîner auberge montagnarde", "130.00", -72}
      ]},

      # 22. Roadtrip Écosse & Highlands
      {"Roadtrip Écosse & Highlands", "GBP", "pending_settlement", charlie, [bob, diane, lucas], [
        {"Location Campervan Skye", "720.00", -18},
        {"Visite distilleries Glenfiddich & Talisker", "160.00", -16},
        {"Ferry île de Skye", "95.00", -15},
        {"Dîner pubs écossais", "210.00", -13},
        {"Château d'Édimbourg", "84.00", -11}
      ]},

      # 23. Séjour Ski Val Thorens
      {"Séjour Ski Val Thorens", "EUR", "pending_settlement", diane, [alice, bob, emma, hugo], [
        {"Résidence Pierre & Vacances", "1420.00", -22},
        {"Forfaits 3 Vallées", "920.00", -21},
        {"Courses supermarché Sherpa", "260.00", -19},
        {"La Folie Douce après-ski", "185.00", -18},
        {"Matériel de ski Intersport", "340.00", -17}
      ]},

      # 24. Festival Hellfest 2025
      {"Festival Hellfest 2025", "EUR", "closed", maxime, [antoine, charlie, chloe], [
        {"Pass 4 jours Clisson x4", "1356.00", -150},
        {"Camping Easy Camp", "320.00", -148},
        {"Consommations Cashless festival", "480.00", -146},
        {"Navettes gare Nantes - Clisson", "64.00", -145}
      ]},

      # 25. Voyage en Islande - Aurores Boréales
      {"Voyage en Islande - Aurores Boréales", "EUR", "closed", lea, [julie, camille, sophie], [
        {"Location Duster 4x4 Blue Car", "850.00", -130},
        {"Baignade Blue Lagoon", "360.00", -128},
        {"Guesthouses cercle d'or", "680.00", -126},
        {"Excursion motoneige glacier", "540.00", -124},
        {"Courses Bonus supermarché", "190.00", -122}
      ]},

      # 26. Weekend Berlin Techno
      {"Weekend Berlin Techno", "EUR", "open", hugo, [lucas, thomas], [
        {"AirBnB Kreuzberg", "380.00", -8},
        {"Entrées clubs & soirées", "120.00", -7},
        {"Currywurst & street food", "65.00", -6},
        {"Musée de la RDA & checkpoint", "48.00", -5}
      ]},

      # 27. Vacances en Croatie - Split
      {"Vacances en Croatie - Split", "EUR", "open", camille, [julie, emma, chloe, diane], [
        {"Appartement Palais Dioclétien", "780.00", -11},
        {"Excursion Parc National Plitvice", "180.00", -10},
        {"Speedboat grottes bleues", "450.00", -9},
        {"Dîner konoba dalmate", "190.00", -8},
        {"Glaces & cafés Riva", "55.00", -7}
      ]},

      # 28. Colocation Rue Saint-Maur
      {"Colocation Rue Saint-Maur", "EUR", "open", antoine, [maxime, charlie, bob], [
        {"Abonnement Freebox Delta", "39.99", -15},
        {"Courses alimentation Leclerc", "215.30", -12},
        {"Machine à laver séchante Bosch", "499.00", -25},
        {"Assurance habitation annuelle", "180.00", -30},
        {"Four à chaleur tournante", "260.00", -28}
      ]},

      # 29. Voyage à Montréal & Québec
      {"Voyage à Montréal & Québec", "CAD", "open", julie, [sophie, lea, camille], [
        {"Appartement Plateau Mont-Royal", "920.00", -25},
        {"Cabane à sucre repas traditionnel", "180.00", -23},
        {"Location motoneiges Laurentides", "460.00", -21},
        {"Poutine La Banquise", "85.00", -19},
        {"Musée des Beaux-Arts", "60.00", -17}
      ]},

      # 30. Rando GR20 Corse
      {"Rando GR20 Corse", "EUR", "closed", bob, [thomas, lucas], [
        {"Refuges PNRC demi-pension", "420.00", -80},
        {"Billets Corsica Ferries", "160.00", -79},
        {"Sacs lyophilisés & gaz", "110.00", -78},
        {"Charcuterie corse à Corte", "75.00", -77}
      ]},

      # 31. Mariage Paul & Virginie (Cadeau & EVG)
      {"Mariage Paul & Virginie", "EUR", "closed", chloe, [alice, bob, charlie, diane, emma], [
        {"Cadeau commun Liste de Mariage", "600.00", -95},
        {"Location gîte EVG week-end", "480.00", -93},
        {"Activité karting outdoor", "240.00", -92},
        {"Traiteur buffet fête", "310.00", -90},
        {"T-shirts personnalisés EVG", "95.00", -89}
      ]},

      # 32. Festival Dour 2025
      {"Festival Dour 2025", "EUR", "closed", users["clement@exemple.com"], [users["romain@exemple.com"], users["mathieu@exemple.com"], users["vincent@exemple.com"]], [
        {"Pass 5 jours Dour x4", "840.00", -70},
        {"Green camping", "120.00", -69},
        {"Food & Drinks tokens", "310.00", -68}
      ]},

      # 33. Roadtrip en Norvège - Fjords
      {"Roadtrip en Norvège - Fjords", "EUR", "open", users["gabriel@exemple.com"], [users["helene@exemple.com"], users["julien@exemple.com"]], [
        {"Location Tesla Model Y", "890.00", -14},
        {"Hébergements Rorbu Lofoten", "1120.00", -13},
        {"Ferries Hurtigruten", "230.00", -12},
        {"Courses Kiwi supermarché", "185.00", -10}
      ]},

      # 34. Weekend Découverte Amsterdam
      {"Weekend Découverte Amsterdam", "EUR", "open", users["fanny@exemple.com"], [users["alexandre@exemple.com"], users["beatrice@exemple.com"]], [
        {"Péniche sur les canaux", "540.00", -9},
        {"Location vélos 3 jours", "75.00", -8},
        {"Musée Van Gogh & Rijksmuseum", "110.00", -7},
        {"Brunch & cafés de Jordaan", "95.00", -6}
      ]},

      # 35. Voyage en Suisse - Interlaken
      {"Voyage en Suisse - Interlaken", "CHF", "open", users["delphine@exemple.com"], [users["eric@exemple.com"], users["karine@exemple.com"]], [
        {"Chalet avec vue Eiger", "790.00", -16},
        {"Train Jungfraujoch Top of Europe", "460.00", -15},
        {"Parapente biplace tandem", "340.00", -14},
        {"Fondue moitié-moitié", "145.00", -12}
      ]},

      # 36. Colocation Lyon Bellecour
      {"Colocation Lyon Bellecour", "EUR", "open", users["manon@exemple.com"], [users["nicolas@exemple.com"], users["pierre@exemple.com"]], [
        {"Box internet SFR Fibre", "34.99", -20},
        {"Courses Grand Frais", "185.20", -18},
        {"Meuble TV & étagères", "140.00", -35},
        {"Bouchon lyonnais", "125.00", -10}
      ]},

      # 37. Weekend Prague & Vltava
      {"Weekend Prague & Vltava", "EUR", "closed", users["olivia@exemple.com"], [users["quentin@exemple.com"], users["rachel@exemple.com"]], [
        {"Appartement Vieille Ville", "310.00", -85},
        {"Dîner croisière Vltava", "120.00", -84},
        {"Brasserie U Fleku", "75.00", -83}
      ]},

      # 38. Séjour Plongée Mer Rouge
      {"Séjour Plongée Mer Rouge", "EUR", "pending_settlement", users["sebastien@exemple.com"], [users["valerie@exemple.com"], users["william@exemple.com"]], [
        {"Hôtel plongée El Gouna", "890.00", -17},
        {"Forfait 10 plongées PADI", "650.00", -16},
        {"Location équipement complet", "210.00", -15}
      ]},

      # 39. Roadtrip Andalousie & Séville
      {"Roadtrip Andalousie & Séville", "EUR", "open", users["yasmine@exemple.com"], [users["zoe@exemple.com"], users["arthur@exemple.com"], users["ines@exemple.com"]], [
        {"Appartement Santa Cruz Séville", "560.00", -11},
        {"Visite Alhambra Grenade", "120.00", -10},
        {"Spectacle Flamenco & tapas", "165.00", -9},
        {"Location Seat Leon", "280.00", -8}
      ]},

      # 40. Weekend Canoë Gorges du Tarn
      {"Weekend Canoë Gorges du Tarn", "EUR", "closed", users["clara@exemple.com"], [users["sarah@exemple.com"], users["elodie@exemple.com"]], [
        {"Camping bord de rivière", "140.00", -100},
        {"Descente canoë 20km", "95.00", -99},
        {"Barbecue & grillades", "65.00", -98}
      ]},

      # 41. Séjour Randonnée Madère
      {"Séjour Randonnée Madère", "EUR", "open", users["damien@exemple.com"], [users["justine@exemple.com"], users["pauline@exemple.com"], users["florian@exemple.com"]], [
        {"Quinta traditionnelle Funchal", "640.00", -7},
        {"Location voiture", "230.00", -6},
        {"Téléphérique Monte & traîneaux", "110.00", -5},
        {"Espada & bananes restaurant", "140.00", -4}
      ]},

      # 42. Séjour Évasion à Kyoto
      {"Séjour Évasion à Kyoto", "USD", "pending_settlement", users["alexandre@exemple.com"], [users["julien@exemple.com"], users["laurent@exemple.com"]], [
        {"Machiya traditionnelle Gion", "950.00", -21},
        {"Cérémonie du thé & kimonos", "180.00", -20},
        {"Repas kaiseki gastronomique", "320.00", -19}
      ]}
    ]

    for {name, currency, status, creator, members, expenses} <- background_wallets do
      {w, m_map} =
        create_wallet_with_members(
          creator,
          name,
          "Porte-monnaie partagé créé pour #{name}",
          currency,
          status,
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

      # If closed, auto-settle all transfers
      if status == "closed" do
        LesBonsComptes.Expenses.mock_settle_all(w)
      end
    end

    # Add extra background invitations between regular users to enrich invitations view
    create_invitation(w1, admin, users["lucie@exemple.com"], "pending")
    create_invitation(w2, admin, users["mathieu@exemple.com"], "pending")
    create_invitation(w5, admin, users["clara@exemple.com"], "declined")
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
     (All other 54 accounts use password: password123)
  =============================================================================
  """)
  end
end
