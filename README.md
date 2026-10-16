# IF — Infrastructures & Frameworks (Master MIAGE)

Project repository for the **Infrastructures & Frameworks** course.

---

## Project: « Les bons comptes »

**Les bons comptes** is a scalable, real-time collaborative expense management and shared wallet web application built with **Elixir**, **Phoenix LiveView**, **Ecto**, and **PostgreSQL**, fully containerized using **Docker**.

### Core Capabilities & Expected Scope

- 👤 **Account Management**: User sign-up, secure authentication, session management, and auto-login tokens.
- 💼 **Common Shared Wallets**: Create multi-currency wallets (`EUR`, `USD`, `GBP`, `CHF`, `CAD`) with automatic owner assignment.
- ✉️ **Member Invitations**: Invite members via suggestions from registered users or by email, with notification alerts.
- ✅ **Accept & Decline Invitations**: Interactive invitation management with real-time membership updates.
- 🗂️ **Categorized Wallet Listings**: Instant filtering across **Invited**, **Open**, and **Closed** wallets with live counters.
- 🧾 **Expense Declaration & Payer Assignment**: Record expenditures attributed to any group member's spending account.
- 📊 **Expense Aggregations**: Chronological expense histories, group totals, and automatic fair share calculations.
- 🔒 **Fine-grained Authorization**: Expenses are deletable and editable only by the payer or the wallet creator.
- 🔄 **3-Step Lifecycle Management**:
  1. *Open* (declarations & invitations)
  2. *Pending Settlements* (reconciliation and bank transfer verification)
  3. *Closed* (definitive, immutable closure once all transfers are settled)
- 💰 **Debtors & Creditors**: Transparent breakdowns of who owes money and who should receive money.
- ⚡ **Optimized Debt Simplification Algorithm**: Minimizes total bank transfers needed using a greedy debt simplification algorithm ($O(N \log N)$).
- 💳 **Mock Settlements & REST API**: Simulate bank transfers via the UI or headless endpoints (`GET /api/wallets/:id/settlements` & `POST /api/wallets/:id/settlements/mock`).
- 🚀 **Think HUGE (Scalability)**: Built on the Erlang BEAM runtime for high concurrency, lightweight WebSocket connections, arbitrary-precision `Decimal` calculations, composite PostgreSQL indexing, and atomic `Ecto.Multi` transactions.

---

## Quick Start & Full Documentation

The complete Phoenix application is located in the [`les_bons_comptes/`](les_bons_comptes/) directory.

👉 **Refer to [`les_bons_comptes/README.md`](les_bons_comptes/README.md)** for comprehensive instructions:
- Docker prerequisites and architecture
- Step-by-step setup and launch commands
- Large-scale realistic dataset generator (`mix data.seed`, IF-10) with 54+ users and 42+ wallets
- Complete REST API documentation
- Running the test suite (183 tests, 0 failures)
- Troubleshooting guide