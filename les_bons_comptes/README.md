# Les bons comptes — Infrastructures & Frameworks (Master MIAGE)

Application web de gestion collaborative de dépenses et porte-monnaies partagés, réalisée avec **Elixir & Phoenix Framework**[cite: 1] et conteneurisée via **Docker**.

---

## 1. Prérequis

* [Docker Desktop](https://www.docker.com/products/docker-desktop/) installé et démarré sur la machine hôte.
* `git` pour cloner et versionner le projet.

*(Aucune installation locale d'Elixir, Erlang ou PostgreSQL n'est nécessaire sur la machine : tout s'exécute dans des conteneurs isolés).*

---

## 2. Architecture Docker

L'environnement repose sur deux conteneurs orchestrés par Docker Compose :
* **`db`** : Base de données PostgreSQL 16 (Alpine).
* **`web`** : Serveur d'application Phoenix (Elixir 1.17 Alpine) avec montage de volumes locaux pour conserver le rechargement à chaud (*live reloading*).

---

## 3. Installation et Lancement

### Étape 1 : Cloner le dépôt
```bash
git clone <URL_DU_DEPOT_GIT>
cd les_bons_comptes
```

### Étape 2 : Construire l'image Docker de l'application
```bash
docker compose up --build -d
```

### Étape 3 : Démarrer les conteneurs
```bash
docker compose up -d
```

### Étape 4 : Initialiser la base de données
Exécuter la création de la base et les migrations initiales dans le conteneur `web` :
```bash
docker compose exec web mix ecto.setup
```
*(Si `ecto.setup` n'est pas défini dans `mix.exs`, exécuter :)*
```bash
docker compose exec web mix ecto.create
docker compose exec web mix ecto.migrate
```

---

## 4. Accès aux Interfaces

| Interface | URL locale |
| :--- | :--- |
| **Application Web** | [http://localhost:4000](http://localhost:4000) |
| **Page d'inscription** | [http://localhost:4000/sign-up](http://localhost:4000/sign-up) |
| **Page de connexion** | [http://localhost:4000/sign-in](http://localhost:4000/sign-in) |
| **LiveDashboard Phoenix** | [http://localhost:4000/dev/dashboard](http://localhost:4000/dev/dashboard) |
| **Boîte mail de test (Swoosh)** | [http://localhost:4000/dev/mailbox](http://localhost:4000/dev/mailbox) |

### Compte Administrateur / Test par Défaut

Un compte de test est préconfiguré dans le script de seed (`priv/repo/seeds.exs`) pour se connecter immédiatement :

* **Identifiant (Email)** : `admin@exemple.com`
* **Mot de passe** : `admin123`
* **Nom** : `Admin`

Pour injecter ou réinjecter ce compte dans la base PostgreSQL :
```bash
docker compose exec web mix run priv/repo/seeds.exs
```

---

## 5. Commandes Utiles

### Suivi des logs
```bash
# Afficher les logs du serveur web en direct
docker compose logs -f web

# Quitter l'affichage des logs : Ctrl + C (les conteneurs continuent de tourner)
```

### Exécution des commandes Mix

Toutes les commandes Phoenix / Ecto s'exécutent au sein du conteneur `web` :

* **Générer le module d'authentification utilisateur[cite: 1] :**
  ```bash
  docker compose exec web mix phx.gen.auth Accounts User users
  ```
* **Appliquer les nouvelles migrations Ecto :**
  ```bash
  docker compose exec web mix ecto.migrate
  ```
* **Consulter la table des routes :**
  ```bash
  docker compose exec web mix phx.routes
  ```
* **Lancer les tests :**
  ```bash
  docker compose exec web mix test
  ```
* **Ouvrir une console interactive IEx :**
  ```bash
  docker compose exec web iex -S mix
  ```

---

## 6. Arrêt et Nettoyage

* **Stopper les conteneurs (données conservées) :**
  ```bash
  docker compose stop
  ```
* **Arrêter et supprimer les conteneurs :**
  ```bash
  docker compose down
  ```
* **Réinitialisation complète (suppression des conteneurs ET du volume de base de données) :**
  ```bash
  docker compose down -v
  ```

---

## 7. Résolution des Problèmes Courants (Dépannage)

### Erreur `Regex.CompileError: invalid_option at position E`
Vérifier les fichiers `config/dev.exs` et `config/runtime.exs`. Supprimer tout caractère parasite situé après les délimiteurs de fermeture de regex (par exemple remplacer `~r"..."E` par `~r"..."`).

### Erreur `connection refused - :econnrefused` (port 5432)
1. Vérifier que le conteneur de base de données est bien actif :
   ```bash
   docker compose ps
   ```
2. Dans `config/dev.exs`, vérifier que le champ `hostname` du `Repo` utilise la variable d'environnement Docker :
   ```elixir
   hostname: System.get_env("DATABASE_HOST") || "localhost"
   ```

### Page inaccessible sur `http://localhost:4000`
Dans `config/dev.exs`, s'assurer que le serveur écoute bien sur toutes les interfaces (`0.0.0.0`) :
```elixir
config :les_bons_comptes, LesBonsComptesWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  ...
```