FROM elixir:1.17-alpine

# Installer les dépendances système nécessaires (compilateurs, PostgreSQL client, watcher inotify)
RUN apk add --no-cache build-base inotify-tools postgresql-client git

WORKDIR /app

# Installer Hex et Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copier uniquement la configuration des dépendances pour optimiser le cache Docker
COPY mix.exs mix.lock ./
RUN mix deps.get

# Copier le reste du projet
COPY . .

# Exposer le port par défaut de Phoenix
EXPOSE 4000

# Commande par défaut pour lancer le serveur
CMD ["mix", "phx.server"]