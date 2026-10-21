# TP : Découverte d'Elixir & Phoenix LiveView
## *« Les Bons Comptes » — CRUD des Dépenses & Pagination Interactive*

> **Public visé** : Étudiants (Master MIAGE / École d'ingénieurs) découvrant le paradigme fonctionnel avec **Elixir** et le framework web **Phoenix LiveView**.  
> **Durée estimée** : 2 heures  
> **Méthode** : Approche guidée par les tests (**TDD — Test-Driven Development**).  
> **Particularité de l'infrastructure** : Base de données PostgreSQL **unique et partagée** entre tous les postes de la salle.

---

## Sommaire

1. [Présentation et Objectifs du TP](#1-présentation-et-objectifs-du-tp)
2. [Initialisation et Démarrage du Projet](#2-initialisation-et-démarrage-du-projet)
3. [Infrastructure : La Base de Données Partagée](#3-infrastructure--la-base-de-données-partagée)
4. [Elixir & Phoenix en 5 minutes (Cheat-Sheet Débutant)](#4-elixir--phoenix-en-5-minutes-cheat-sheet-débutant)
5. [Étape 1 : Anatomie d'un Test ExUnit (Démonstration)](#5-étape-1--anatomie-dun-test-exunit-démonstration)
6. [Étape 2 : Écrire votre premier test (TDD - Montant Invalide)](#6-étape-2--écrire-votre-premier-test-tdd---montant-invalide)
7. [Étape 3 : Implémenter le CRUD & Faire passer tous les tests](#7-étape-3--implémenter-le-crud--faire-passer-tous-les-tests)
   - [3.1 — Les Validations du Changeset (`Expense.changeset/2`)](#31--les-validations-du-changeset-expensechangeset2)
   - [3.2 — La Création d'une Dépense](#32--la-création-dune-dépense)
   - [3.3 — La Pagination des Dépenses (`Expenses.list_expenses_for_wallet_paginated/3`)](#33--la-pagination-des-dépenses)
   - [3.4 — La Suppression Sécurisée (`Expenses.delete_expense/2`)](#34--la-suppression-sécurisée)
8. [Étape 4 : Découverte dans le Navigateur (Phoenix LiveView)](#8-étape-4--découverte-dans-le-navigateur-phoenix-liveview)
9. [Plan d'action pour l'enseignant / encadrant](#9-plan-daction-pour-lenseignant--encadrant)

---

## 1. Présentation et Objectifs du TP

### Le Contexte Métier
**« Les bons comptes »** est une application collaborative de gestion de dépenses partagées (dans l'esprit de *Tricount* ou *Splitwise*). Des utilisateurs peuvent créer des porte-monnaies communs (*wallets*), y inviter des amis, déclarer des dépenses de groupe, et calculer automatiquement les remboursements nécessaires pour équilibrer les comptes.

### Les Objectifs Pédagogiques
À la fin de ce TP de 2 heures, vous saurez :
- **Comprendre la syntaxe et la philosophie d'Elixir** : immutabilité, opérateur pipe (`|>`), tuples de statut (`{:ok, result}` / `{:error, reason}`), et pattern matching.
- **Valider des données avec Ecto Changeset** : transformer et valider des structures sans jamais modifier l'état existant en place.
- **Manipuler la base de données avec Ecto** : requêtes filtrées, ordonnées et paginées.
- **Pratiquer le Test-Driven Development (TDD) avec ExUnit** : observer un test rouge, écrire le code minimal pour le rendre vert, et enrichir la suite de tests.
- **Voir la réactivité de Phoenix LiveView** : interagir dans le navigateur avec une pagination dynamique mise à jour en temps réel via WebSockets, sans écrire une seule ligne de JavaScript !

---

## 2. Initialisation et Démarrage du Projet

### 2.1 Prérequis
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) installé et démarré sur votre machine.
- Git configuré.

*(Aucune installation locale d'Elixir, Erlang ou PostgreSQL n'est requise : tout s'exécute dans un conteneur Docker).*

---

### 2.2 Récupérer le code et basculer sur la branche du TP

Ouvrez un terminal et exécutez :

```bash
# 1. Cloner le dépôt (si ce n'est pas déjà fait)
git clone <URL_DU_DEPOT_GIT>
cd les_bons_comptes

# 2. Basculer sur la branche dédiée au TP
git checkout feature/tp-if
```

---

### 2.3 Configuration de la Base de Données

Pendant ce TP, **une seule base de données PostgreSQL centralisée est partagée entre tous les étudiants de la salle**.

Copiez le fichier d'exemple `.env.example` vers `.env` :

```bash
cp .env.example .env
```

Ouvrez le fichier `.env` avec votre éditeur et renseignez l'adresse IP de la base de données partagée fournie par l'enseignant (exemple : `192.168.1.100`) :

```env
DATABASE_HOST=192.168.1.100
DATABASE_PORT=5432
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=les_bons_comptes_dev
POSTGRES_TEST_DB=les_bons_comptes_test
```

> **Note si vous travaillez en autonome chez vous (hors de la salle de TP)** :  
> Laissez simplement `DATABASE_HOST=db`, Docker utilisera le conteneur PostgreSQL local fourni dans `docker-compose.yml`.

---

### 2.4 Démarrer le conteneur applicatif

- **Pendant le TP (connexion à la base de données partagée)** :  
  Démarrez uniquement le service web (sans lancer de base PostgreSQL locale inutile) :
  ```bash
  docker compose up -d web
  ```

- **Si vous travaillez en solo chez vous (hors de la salle de TP)** :  
  Démarrez l'ensemble des services (base locale + application) :
  ```bash
  docker compose up -d
  ```

Pour vérifier que votre conteneur tourne correctement :
```bash
docker compose ps
```

---

### 2.5 Lancer votre première commande de test

Tous les exercices du TP s'appuient sur un fichier de test dédié. Exécutez la commande suivante :

```bash
docker compose exec web mix test test/les_bons_comptes/tp_expenses_test.exs
```

Vous devriez voir :
- **Des tests réussis** (les démonstrations).
- **Des tests en échec** (les fonctionnalités que vous allez implémenter).

---

## 3. Infrastructure : La Base de Données Partagée

### Comment peut-on partager une seule base de données sans se marcher sur les pieds ?

Une question légitime se pose : *si 30 étudiants exécutent des tests en même temps sur la même base de données, ne risque-t-on pas d'écraser les données des autres ?*

La réponse repose sur deux mécanismes élégants d'Elixir et PostgreSQL :

1. **Le bac à sable SQL (`Ecto.Adapters.SQL.Sandbox`)** :
   À chaque fois qu'un test démarre, Ecto ouvre une transaction SQL (`BEGIN`). Toutes les insertions, modifications et suppressions effectuées pendant le test n'existent qu'à l'intérieur de cette transaction. Dès que le test se termine, Ecto émet un `ROLLBACK`. **Aucune donnée de test n'est jamais définitivement enregistrée en base**.
   
2. **L'isolation des identifiants (`System.unique_integer/1`)** :
   Pour éviter les erreurs de verrouillage ou les doublons sur les colonnes uniques (comme les adresses email des utilisateurs), chaque helper de test génère un identifiant unique (ex: `etudiant_48291@tp-if.fr`).

---

## 4. Elixir & Phoenix en 5 minutes (Cheat-Sheet Débutant)

Pas de panique si vous découvrez le langage ! Voici les 5 concepts clés dont vous aurez besoin aujourd'hui :

### 1. L'Opérateur Pipe (`|>`)
Il prend le résultat de l'expression de gauche et le passe comme **premier argument** de la fonction de droite.
```elixir
# En impératif classique :
liste_triee = Enum.sort(String.split(chaine, ","))

# En Elixir avec des pipes :
chaine
|> String.split(",")
|> Enum.sort()
```

### 2. Les Tuples de retour et le Pattern Matching
En Elixir, les fonctions indiquent le succès ou l'échec via des tuples étiquetés avec des **atomes** (`:ok`, `:error`) :
```elixir
case Repo.insert(changeset) do
  {:ok, expense} ->
    # Succès : expense contient la structure enregistrée
    IO.puts("Créé avec succès !")

  {:error, changeset} ->
    # Échec : changeset contient la liste des erreurs de validation
    IO.puts("Erreur de validation")
end
```

### 3. Les Maps et les Mots-clés
```elixir
# Une Map (dictionnaire clé/valeur) :
attrs = %{title: "Courses", amount: "25.50"}

# Accéder à une valeur :
attrs.title        # => "Courses"
attrs[:title]      # => "Courses"
```

### 4. Les Changesets Ecto
Un `Changeset` est un objet qui encapsule des modifications proposées sur une entité, ainsi que toutes les erreurs de validation :
```elixir
%Expense{}
|> cast(attrs, [:title, :amount, :date])
|> validate_required([:title, :amount])
|> validate_number(:amount, greater_than: 0)
```
Si toutes les validations passent, `changeset.valid?` vaut `true`. Sinon, les erreurs sont stockées dans `changeset.errors`.

---

## 5. Étape 1 : Anatomie d'un Test ExUnit (Démonstration)

Ouvrez le fichier [`test/les_bons_comptes/tp_expenses_test.exs`](file:///Users/mateodacosta/Fac/IF/IF/les_bons_comptes/test/les_bons_comptes/tp_expenses_test.exs).

Observez le premier bloc de test :

```elixir
describe "Partie 1 : Découverte d'ExUnit et de la base de données" do
  test "DÉMONSTRATION : structure d'un test, pattern matching et assert" do
    # 1. Setup : création de données de test
    %{alice: _alice, bob: _bob, wallet: wallet} = setup_wallet_with_members()

    # 2. Assertions simples
    assert wallet.name == "Vacances TP"
    assert wallet.currency == "EUR"
    assert length(wallet.members) == 2

    # 3. Pattern Matching dans une assertion
    assert %Wallets.Wallet{id: wallet_id} = wallet
    assert is_integer(wallet_id)

    # 4. Vérification d'appartenance
    member_names = Enum.map(wallet.members, & &1.name)
    assert "Alice" in member_names
    assert "Bob" in member_names
  end
end
```

### Ce qu'il faut retenir :
- `test "description" do ... end` : déclare un cas de test unitaire.
- `assert condition` : vérifie qu'une condition est vraie. Si elle est fausse, le test échoue et affiche un diff clair.
- `refute condition` : l'inverse d'`assert` (vérifie que la condition est fausse ou `nil`).
- `setup_wallet_with_members()` : crée un environnement isolé grâce au bac à sable Ecto.

---

## 6. Étape 2 : Écrire votre premier test (TDD - Montant Invalide)

Dans [`test/les_bons_comptes/tp_expenses_test.exs`](file:///Users/mateodacosta/Fac/IF/IF/les_bons_comptes/test/les_bons_comptes/tp_expenses_test.exs), repérez le test de la **Partie 2** (autour de la ligne 85) :

```elixir
test "EXERCICE : vérifier qu'une dépense avec un montant négatif est invalide" do
  _attrs_invalides = %{
    title: "Test négatif",
    amount: "-15.00",
    date: Date.utc_today(),
    wallet_id: 1,
    payer_id: 1
  }

  flunk("👉 Étape 2 : À vous d'écrire les assertions de ce test...")
end
```

### Votre mission :
1. Supprimez ou commentez la ligne avec `flunk(...)`.
2. Instanciez un changeset pour la dépense avec les attributs invalides :
   ```elixir
   changeset = Expense.changeset(%Expense{}, _attrs_invalides)
   ```
3. Vérifiez avec `refute` que le changeset est invalide :
   ```elixir
   refute changeset.valid?
   ```
4. Récupérez les erreurs avec le helper `errors_on(changeset)` et vérifiez qu'une erreur est présente sur `:amount` :
   ```elixir
   errors = errors_on(changeset)
   assert errors.amount != nil
   ```

Exécutez à nouveau les tests :
```bash
docker compose exec web mix test test/les_bons_comptes/tp_expenses_test.exs
```
*Le test de l'étape 2 doit maintenant être vert ! 🎉*

---

## 7. Étape 3 : Implémenter le CRUD & Faire passer tous les tests

Il vous reste maintenant 3 tests en échec. Nous allons les faire passer un à un selon le cycle TDD : **Rouge ➔ Vert ➔ Refactor**.

---

### 3.1 — Les Validations du Changeset (`Expense.changeset/2`)

Le test `3.1 - Validations du Changeset : titre et montant obligatoires` échoue actuellement.

Ouvrez le fichier [`lib/les_bons_comptes/expenses/expense.ex`](file:///Users/mateodacosta/Fac/IF/IF/les_bons_comptes/lib/les_bons_comptes/expenses/expense.ex) aux alentours de la ligne 30.

Vous trouverez la fonction `changeset/2` :

```elixir
def changeset(expense, attrs) do
  expense
  |> cast(attrs, [
    :title,
    :amount,
    :date,
    :description,
    :currency,
    :payer_id,
    :wallet_id,
    :created_by_id
  ])
  # =========================================================================
  # TODO TP (Étape 3.1) : Définir les validations Ecto pour une dépense
  # =========================================================================
  |> foreign_key_constraint(:wallet_id)
  |> foreign_key_constraint(:payer_id)
  |> foreign_key_constraint(:created_by_id)
end
```

#### Votre mission :
Décommentez et complétez les validations dans le pipe :
1. Rendre obligatoires `:title, :amount, :date, :wallet_id, :payer_id` :
   ```elixir
   |> validate_required([:title, :amount, :date, :wallet_id, :payer_id],
     message: "ce champ est obligatoire"
   )
   ```
2. Valider la longueur du titre (entre 2 et 100 caractères) :
   ```elixir
   |> validate_length(:title, min: 2, max: 100, message: "doit contenir entre 2 et 100 caractères")
   ```
3. Valider que le montant est strictement positif :
   ```elixir
   |> validate_number(:amount, greater_than: 0, message: "doit être supérieur à 0")
   ```
4. Valider la devise et la date :
   ```elixir
   |> validate_inclusion(:currency, Wallet.supported_currencies(), message: "devise non supportée")
   |> validate_not_in_future()
   ```

Relancez les tests : **le test 3.1 et le test 3.2 passent désormais !**

---

### 3.2 — La Création d'une Dépense

Le test `3.2` teste l'insertion en base via le Context métier `Expenses.create_expense(user, wallet, attrs)`.  
Puisque votre changeset est maintenant valide, la fonction de création réussit et le test passe automatiquement.

Prenez 2 minutes pour observer son implémentation dans [`lib/les_bons_comptes/expenses.ex`](file:///Users/mateodacosta/Fac/IF/IF/les_bons_comptes/lib/les_bons_comptes/expenses.ex) (lignes 80-110) :
- Elle vérifie que le portefeuille est ouvert.
- Elle vérifie que le payeur fait bien partie des membres du groupe.
- Elle insère la dépense via `Repo.insert/1`.

---

### 3.3 — La Pagination des Dépenses

Le test `3.3 - Pagination des dépenses (Read paginé)` échoue avec l'erreur suivante :
```
** (RuntimeError) 👉 TODO TP (Étape 3.3) : Implémentez list_expenses_for_wallet_paginated/3
```

Ouvrez [`lib/les_bons_comptes/expenses.ex`](file:///Users/mateodacosta/Fac/IF/IF/les_bons_comptes/lib/les_bons_comptes/expenses.ex) vers la ligne 32.

```elixir
def list_expenses_for_wallet_paginated(_wallet_id, _page, _page_size) do
  # TODO TP (Étape 3.3)
  raise "👉 TODO TP (Étape 3.3) : Implémentez list_expenses_for_wallet_paginated/3..."
end
```

#### Votre mission :
Remplacez le corps de la fonction par :
1. L'appel à la fonction existante `list_expenses_for_wallet(wallet_id)` qui récupère toutes les dépenses du portefeuille triées par date décroissante.
2. Le découpage en pages grâce au module utilitaire [`LesBonsComptes.Pagination.paginate/3`](file:///Users/mateodacosta/Fac/IF/IF/les_bons_comptes/lib/les_bons_comptes/pagination.ex) :

```elixir
def list_expenses_for_wallet_paginated(wallet_id, page \\ 1, page_size \\ 8)
    when is_integer(wallet_id) or is_binary(wallet_id) do
  list_expenses_for_wallet(wallet_id)
  |> LesBonsComptes.Pagination.paginate(page, page_size)
end
```

Relancez les tests : **le test 3.3 est vert !**

---

### 3.4 — La Suppression Sécurisée

Le test `3.4 - Suppression sécurisée d'une dépense (Delete)` échoue :
```
** (RuntimeError) 👉 TODO TP (Étape 3.4) : Implémentez delete_expense/2
```

Ouvrez [`lib/les_bons_comptes/expenses.ex`](file:///Users/mateodacosta/Fac/IF/IF/les_bons_comptes/lib/les_bons_comptes/expenses.ex) vers la ligne 225.

#### Règle métier :
Une dépense ne peut être supprimée que si :
- Le portefeuille est au statut `"open"`.
- L'utilisateur qui demande la suppression est soit la personne qui a avancé l'argent (`payer`), soit le créateur du portefeuille. Le helper `can_delete_expense?(user, expense)` effectue déjà cette vérification.

#### Votre mission :
Remplacez le `raise` par la structure conditionnelle `cond do ... end` :

```elixir
def delete_expense(%User{} = user, %Expense{} = expense) do
  expense = Repo.preload(expense, [:wallet, :payer])

  cond do
    expense.wallet && expense.wallet.status != "open" ->
      {:error, :wallet_closed}

    can_delete_expense?(user, expense) ->
      Repo.delete(expense)

    true ->
      {:error, :unauthorized}
  end
end
```

Relancez vos tests :
```bash
docker compose exec web mix test test/les_bons_comptes/tp_expenses_test.exs
```

Vous devriez obtenir :
```
6 tests, 0 failures
```
**Félicitations ! L'intégralité de la suite de tests est passée au vert ! 🚀**

---

## 8. Étape 4 : Découverte dans le Navigateur (Phoenix LiveView)

Il est temps de contempler votre travail dans une interface utilisateur réelle !

1. Ouvrez votre navigateur sur : [http://localhost:4000](http://localhost:4000).
2. Connectez-vous avec l'un des comptes de test pré-générés :
   - **Email** : `alice@exemple.com` (ou `admin@exemple.com`)
   - **Mot de passe** : `password123` (ou `admin123` pour admin)
3. Rendez-vous sur un porte-monnaie (ex: *« Vacances Barcelone »*).
4. **Testez votre CRUD & la Pagination en direct** :
   - Cliquez sur **« Ajouter une dépense »** : entrez un montant, un titre, sélectionnez le payeur et enregistrez. La dépense s'affiche immédiatement en haut de la liste sans aucun rechargement de page.
   - Ajoutez plus de 8 dépenses (ou réduisez le `page_size`) : observez l'apparition des boutons de pagination (*1, 2, Précédent, Suivant*).
   - Cliquez sur **Page 2** : l'URL devient `/wallets/:id?page=2`, les dépenses de la page 2 se chargent instantanément via WebSocket.
   - Supprimez une dépense en cliquant sur l'icône de corbeille : la liste se recalcule en temps réel !

---

## 9. Plan d'action pour l'enseignant / encadrant

Pour organiser ce TP dans des conditions optimales, suivez cette feuille de route :

### 1. Avant la séance (J-1)
- [ ] **Déployer la base de données PostgreSQL partagée** sur une machine accessible sur le réseau local (ou un serveur dédié).
- [ ] Initialiser le schéma et exécuter les migrations :
  ```bash
  MIX_ENV=dev mix ecto.setup
  MIX_ENV=test mix ecto.create && MIX_ENV=test mix ecto.migrate
  ```
- [ ] Insérer les données de démonstration (seed) :
  ```bash
  mix run priv/repo/seeds.exs
  ```
- [ ] Vérifier que le port `5432` est ouvert et joignable depuis les adresses IP des étudiants (pare-feu / firewall).
- [ ] Noter l'adresse IP locale du serveur PostgreSQL (ex: `192.168.1.100`) pour la projeter au tableau.

### 2. Au début du TP (00h00 - 00h20)
- [ ] **Présentation (10 min)** : Montrer l'application finale en démonstration vidéo ou live. Expliquer le concept de l'opérateur pipe (`|>`), des changesets et de LiveView.
- [ ] **Mise en route (10 min)** :
  - Les étudiants clonent le dépôt et basculent sur `feature/tp-if`.
  - Ils copient `.env.example` en `.env` avec l'adresse IP de la base partagée.
  - Ils lancent `docker compose up -d` et exécutent la première commande de test.

### 3. Déroulé chronologique du TP (00h20 - 01h50)
- **00h20 - 00h40 (20 min)** : Étape 1 & Étape 2. Comprendre le premier test et écrire son propre test sur le montant invalide.
- **00h40 - 01h15 (35 min)** : Étape 3.1 & 3.2. Coder les validations dans `Expense.changeset/2` et faire passer la création.
- **01h15 - 01h35 (20 min)** : Étape 3.3. Coder la pagination `list_expenses_for_wallet_paginated/3`.
- **01h35 - 01h50 (15 min)** : Étape 3.4. Coder la suppression sécurisée `delete_expense/2`.

### 4. Conclusion & Débriefing (01h50 - 02h00)
- [ ] Faire tester le rendu visuel dans le navigateur à toute la classe.
- [ ] Synthèse : résumer pourquoi le modèle d'acteurs de la machine virtuelle BEAM (Erlang) et l'immutabilité rendent Elixir et Phoenix LiveView si adaptés pour des applications temps réel et scalables.
