# Les bons comptes — Infrastructures & Frameworks (Master MIAGE)

> A modern, collaborative expense management and shared wallet web application built with **Elixir**, **Phoenix LiveView**, and **PostgreSQL**, containerized with **Docker**.

---

## 1. Project Context & Overview

**« Les bons comptes »** (*"Good accounts make good friends"*) is a collaborative financial management platform designed for groups (housemates, travel groups, event organizers, families). It allows users to create shared wallets, declare group expenses, track balances in real time, and automatically calculate the minimum number of bank transfers needed to settle all debts.

### Functional Scope & Core Features

| Feature | Description | Implementation Details |
| :--- | :--- | :--- |
| **User Account Creation** | User sign-up and authentication with password hashing | `Accounts.create_user/1`, `Bcrypt`, session cookies, ephemeral login tokens |
| **Common Shared Wallet** | Create multi-currency wallets (`EUR`, `USD`, `GBP`, `CHF`, `CAD`) | `Wallets.create_wallet/3`, automatic creator assignment as `owner` |
| **Member Invitations** | Invite members via auto-suggested registered users or custom email | `Wallets.create_invitation/3`, real-time notification bell and dropdown badge |
| **Accept / Decline Invitations** | Invited users can accept or decline invitations in one click | `Wallets.accept_invitation/2`, `Wallets.decline_invitation/2` |
| **Wallet Listing & Filtering** | View wallets separated into tabs: **Invited**, **Open**, and **Closed** | `Wallets.list_wallets_for_user/2`, `list_invited_wallets_for_user/2` with status filter bars |
| **Expense Declaration & Payer Assignment** | Log expenses with title, amount, date, description, and assigned spending account | `Expenses.create_expense/3`, allows attributing expense to any member |
| **Expense Listing & Total Sum** | Chronological list of group expenses with running total and fair share | `Expenses.list_expenses_for_wallet/1`, `Expenses.get_balance_data/1` |
| **Fine-grained Deletion & Editing** | Deletable and editable **only** by the payer account or the wallet owner | `Expenses.can_delete_expense?/2`, `Expenses.can_edit_expense?/2` |
| **3-Step Lifecycle & Closure** | Controlled progression: *1. Declarations* → *2. Transfers* → *3. Closed* | `Wallets.validate_wallet/2`, `Wallets.close_wallet/2` |
| **Creditors List ("Who should receive")** | Clear breakdown of members who overpaid and exact amounts to receive | `Expenses.calculate_creditors/1`, visual `creditor_item/1` badge |
| **Debtors List ("Who owes money")** | Clear breakdown of members who underpaid and exact amounts to settle | `Expenses.calculate_debtors/1`, visual `debtor_item/1` badge |
| **Optimized Debt Simplification (Bonus)** | Minimizes the total number of bank transfers between members | Greedy reconciliation algorithm in `Expenses.calculate_settlements/1` |
| **Mock Settlements & REST API** | Trigger mock payments in UI or via JSON API; auto-closes wallet once settled | `Expenses.settle_transfer/5`, `POST /api/wallets/:id/settlements/mock` |

---

## 2. Wallet Lifecycle & Debt Settlement Algorithm

```
  +---------------------------------------------------------------------------------+
  | STEP 1 : OPEN (Déclarations en cours)                                          |
  | - Add / edit / delete expenses                                                  |
  | - Send invitations / accept members                                            |
  | - Balances, debtors, creditors & proposed settlements calculated in real-time   |
  +---------------------------------------------------------------------------------+
                                         |
                       [Wallet Owner clicks "Valider le porte-monnaie"]
                                         v
  +---------------------------------------------------------------------------------+
  | STEP 2 : AWAITING TRANSFERS (Attente des virements)                             |
  | - Expense additions and deletions are locked                                    |
  | - Invitations are frozen                                                        |
  | - Debtors see "Marquer comme réglé" button for their own transfers             |
  | - Reopening is permitted ONLY IF no transfer has occurred yet                   |
  +---------------------------------------------------------------------------------+
                                         |
                   [All proposed settlements are marked as settled]
                                         v
  +---------------------------------------------------------------------------------+
  | STEP 3 : CLOSED (Clos - Irréversible)                                           |
  | - Fully balanced & reconciled                                                   |
  | - Archived; all pending invitations permanently discarded                       |
  +---------------------------------------------------------------------------------+
```

### The Debt Simplification Algorithm (`Expenses.calculate_settlements/1`)
When multiple people pay for different expenses, a naive settlement could require $N \times (N-1)$ transactions. Our algorithm reduces this to at most $N-1$ transfers:
1. **Compute Net Balance**: For each member $i$, $\text{Balance}_i = \text{TotalPaid}_i - \text{FairShare}$.
2. **Partition**: Split members into **Creditors** ($\text{Balance} > 0$) and **Debtors** ($\text{Balance} < 0$), sorted in descending order of magnitude.
3. **Greedy Matching**: Match the largest debtor with the largest creditor:
   - Transfer amount $T = \min(|\text{DebtorBalance}|, \text{CreditorBalance}|)$.
   - Deduct $T$ from both balances.
   - Advance to the next debtor or creditor once their balance reaches $0.00$.

---

## 3. Think HUGE: High Volume & Scalability Architecture

The application was designed to handle high loads: **thousands of user accounts, concurrent wallets, heavy invitation flows, and extensive expense histories**.

### Key Architectural Choices for Scale:

1. **BEAM Process Isolation & Lightweight Concurrency:**
   - Every active user connection runs in an isolated Erlang BEAM process (~few kilobytes of RAM).
   - Real-time updates use **Phoenix Channels and WebSocket connections**, avoiding aggressive database polling.
   - LiveView transmits **minimal binary diffs** across the wire rather than re-rendering whole HTML documents.

2. **Database Performance & Composite Indexing:**
   - Foreign keys and frequent filter paths are indexed in PostgreSQL:
     - `expenses (wallet_id, date DESC)`
     - `expenses (payer_id)`
     - `wallet_members (wallet_id, user_id)`
     - `wallet_invitations (wallet_id, status)` and `wallet_invitations (email, status)`
     - `wallets (creator_id, status)`
   - Avoids full-table scans when querying wallets, expenses, and invitations for high-traffic users.

3. **In-Database Aggregations & Query Optimization:**
   - Aggregations (`total_expenses`, `expenses_by_member`) use SQL `SUM` and `GROUP BY` via Ecto instead of loading thousands of structs into memory.
   - Preloads are batched to avoid $N+1$ query bottlenecks.

4. **Arbitrary-Precision Arithmetic (`Decimal`):**
   - Monetary values strictly use `Decimal` throughout schemas, changesets, algorithms, and templates.
   - Eliminates floating-point drift (e.g. `0.1 + 0.2 != 0.3`) across large sums and division across uneven member counts.

5. **Atomic Transactions (`Ecto.Multi`):**
   - Wallet creation with initial members, settlement validation, and automatic closure operations are wrapped in database transactions to guarantee ACID consistency even under heavy concurrency.

---

## 4. Prerequisites

* [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed and running on the host machine.
* `git` to clone and version control the repository.

*(No local installation of Elixir, Erlang, Node.js, or PostgreSQL is required on the host system: everything executes inside Docker).*

---

## 5. Docker Architecture

The environment relies on two containers orchestrated by Docker Compose:
* **`db`**: PostgreSQL 16 (Alpine) database server (`port 5433 -> 5432`).
* **`web`**: Phoenix application server (Elixir 1.17 Alpine) with volume bind-mounts preserving live code reloading (`port 4000`).

---

## 6. Installation and Launch

### Step 1: Clone the repository
```bash
git clone <GIT_REPOSITORY_URL>
cd les_bons_comptes
```

### Step 2: Build the Docker image
```bash
docker compose up --build -d
```

### Step 3: Start the containers
```bash
docker compose up -d
```

### Step 4: Initialize the database
Run initial migrations inside the `web` container:
```bash
docker compose exec web mix ecto.setup
```
*(If `ecto.setup` is not defined in `mix.exs`, execute:)*
```bash
docker compose exec web mix ecto.create
docker compose exec web mix ecto.migrate
```

---

## 7. Interface Access & Default Test Accounts

| Interface | Local URL | Description |
| :--- | :--- | :--- |
| **Web Application** | [http://localhost:4000](http://localhost:4000) | Main dashboard |
| **Sign-up page** | [http://localhost:4000/sign-up](http://localhost:4000/sign-up) | User account registration |
| **Sign-in page** | [http://localhost:4000/sign-in](http://localhost:4000/sign-in) | Authentication |
| **Invited Wallets** | [http://localhost:4000/wallets/invited](http://localhost:4000/wallets/invited) | Invitations received by current user |
| **Open Wallets** | [http://localhost:4000/wallets/open](http://localhost:4000/wallets/open) | Wallets in declaration phase |
| **Closed Wallets** | [http://localhost:4000/wallets/closed](http://localhost:4000/wallets/closed) | Archived / reconciled wallets |
| **Phoenix LiveDashboard** | [http://localhost:4000/dev/dashboard](http://localhost:4000/dev/dashboard) | Real-time VM metrics and process monitoring |
| **Mailbox Preview (Swoosh)** | [http://localhost:4000/dev/mailbox](http://localhost:4000/dev/mailbox) | Inspection of invitation emails sent in dev |

### Preconfigured Seed Accounts

A default admin account is included in `priv/repo/seeds.exs`:

* **Email**: `admin@exemple.com`
* **Password**: `admin123`
* **Name**: `Admin`

To run the seed script:
```bash
docker compose exec web mix run priv/repo/seeds.exs
```

---

## 8. REST API Reference

The application exposes REST endpoints for headless integrations and mock settlements:

### 1. Retrieve settlements and balances
```http
GET /api/wallets/:id/settlements
```
**Response (200 OK):**
```json
{
  "wallet_id": 42,
  "wallet_name": "Summer Vacation",
  "currency": "EUR",
  "status": "open",
  "total_expenses": "120.00",
  "fair_share": "40.00",
  "settlements_count": 2,
  "settlements": [
    {
      "from_id": 102,
      "from_name": "Bob",
      "to_id": 101,
      "to_name": "Alice",
      "amount": "40.00",
      "currency": "EUR",
      "status": "pending",
      "settled": false
    }
  ],
  "creditors": [
    {
      "member_id": 101,
      "name": "Alice",
      "total_paid": "120.00",
      "fair_share": "40.00",
      "amount_to_receive": "80.00"
    }
  ],
  "debtors": [
    {
      "member_id": 102,
      "name": "Bob",
      "total_paid": "0.00",
      "fair_share": "40.00",
      "amount_to_pay": "40.00"
    }
  ]
}
```

### 2. Settle a transfer (Mock Payment)
```http
POST /api/wallets/:id/settlements/mock
Content-Type: application/json

{
  "from_id": 102,
  "to_id": 101,
  "amount": "40.00"
}
```
*When called without parameters (`{}`), all pending settlements are automatically simulated and the wallet transitions directly to `closed`.*

---

## 9. Useful Commands

### Viewing Logs
```bash
# View live web server logs
docker compose logs -f web

# View database logs
docker compose logs -f db
```

### Running Test Suite
Execute the entire test suite (183 tests):
```bash
docker compose exec web mix test
```

### Interactive Console (IEx)
```bash
docker compose exec web iex -S mix
```

---

## 10. Teardown & Environment Cleanup

* **Stop containers (database and application data preserved):**
  ```bash
  docker compose stop
  ```
* **Stop and remove containers:**
  ```bash
  docker compose down
  ```
* **Complete reset (remove containers AND delete database volume):**
  ```bash
  docker compose down -v
  ```

---

## 11. Troubleshooting

### `Error: connection refused - :econnrefused (port 5432)`
1. Check that the database container is healthy:
   ```bash
   docker compose ps
   ```
2. Verify that `config/dev.exs` uses `DATABASE_HOST`:
   ```elixir
   hostname: System.get_env("DATABASE_HOST") || "localhost"
   ```

### Page unreachable on `http://localhost:4000`
Ensure that the Phoenix endpoint is configured to listen on all network interfaces (`0.0.0.0`) in `config/dev.exs`:
```elixir
config :les_bons_comptes, LesBonsComptesWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4000]
```