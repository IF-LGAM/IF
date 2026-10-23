## Solutions

## 3.3
```Elixir
list_expenses_for_wallet(_wallet_id)
|> LesBonsComptes.Pagination.paginate(_page, _page_size)
```

## 3.4 
```Elixir
    cond do
       expense.wallet && expense.wallet.status != "open" ->
         {:error, :wallet_closed}

       can_delete_expense?(_user, expense) ->
         Repo.delete(expense)

       true ->
         {:error, :unauthorized}
     end
```


## Plan d'action pour l'enseignant / encadrant

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
- [ ] Noter l'adresse IP locale du serveur PostgreSQL (ex: `localhost` ou `127.0.0.1`) pour la projeter au tableau.

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
