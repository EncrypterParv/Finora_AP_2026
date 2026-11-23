# AP CP4 Query Timings and Plans

Measurements use psql 18.6 and PostgreSQL 18.6 (Postgres.app) on macOS 26.4.1, Apple Silicon, 10 CPU cores, and 16 GiB RAM. The database was built from `dbms/03_schema.sql` and `dbms/sample_data.sql`. The sample data uses `setseed(0.42)` and SQL `generate_series` inserts.

Each query was run three times with `EXPLAIN (ANALYZE, BUFFERS)`. Writes ran in `BEGIN`/`ROLLBACK` transactions. For insert statements whose literal keys are present in the reproducible fixture, the conflicting fixture row was deleted inside the same transaction before timing the insert; the cleanup and write were both rolled back. Multi-statement write blocks, if present, are timed statement by statement and their execution times summed. Run values and averages below are generated from the `Execution Time` lines in `dbms/plans/*.txt`; averages are arithmetic means of the three runs. Scan type lists the distinct scan nodes from run one.

## Fixture row counts

| Table | Rows |
|---|---:|
| `bank_accounts` | 2,000 |
| `budget_categories` | 9,000 |
| `budgets` | 3,000 |
| `categories` | 20 |
| `financial_goals` | 1,500 |
| `goal_milestones` | 4,500 |
| `merchants` | 300 |
| `ml_profiles` | 1,000 |
| `transactions` | 200,000 |
| `users` | 1,000 |

## READ result counts

| Query | Rows returned |
|---|---:|
| R1 | 1 |
| R2 | 1 |
| R3 | 1 |
| R4 | 1 |
| R5 | 1 |
| R6 | 1 |
| R7 | 50 |
| R8 | 1 |
| R9 | 9 |
| R10 | 1 |
| R11 | 6 |
| R12 | 3 |
| R13 | 200 |
| R14 | 2 |
| R15 | 3 |
| R16 | 3 |
| R17 | 1 |
| R18 | 12 |
| R19 | 1 |
| R20 | 1 |
| R21 | 1 |

## Query timings

| Query | Type | What it does | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) | Scan type |
|---|---|---|---:|---:|---:|---:|---|
| R1 | READ | Retrieve authenticated user profile by ID from JWT token payload | 0.050 | 0.038 | 0.024 | 0.037 | Index Scan (pk_users) |
| R2 | READ | Retrieve default/primary demo user when no auth token is provided | 0.172 | 0.138 | 0.116 | 0.142 | Seq Scan on users |
| R3 | READ | Check if an account already exists with the given email during registration | 0.026 | 0.038 | 0.030 | 0.031 | Index Scan (uq_users_email) |
| R4 | READ | Lookup user by email for password verification during login | 0.021 | 0.024 | 0.022 | 0.022 | Index Scan (uq_users_email) |
| R5 | READ | Fetch user bank account by ID to verify ownership before initiating sync | 0.029 | 0.105 | 0.066 | 0.067 | Index Scan (uq_bank_accounts_id_user_id) |
| R6 | READ | Check if a bank transaction already exists using SHA-256 deduplication hash | 0.040 | 0.085 | 0.034 | 0.053 | Index Scan (uq_transactions_dedup_hash) |
| R7 | READ | List paginated canonical transactions with joined category and merchant details | 9.757 | 9.545 | 8.926 | 9.409 | Parallel Seq Scan on transactions; Seq Scan on categories; Seq Scan on merchants |
| R8 | READ | Retrieve rich transaction detail including linked bank account, merchant, and category | 0.091 | 0.089 | 0.080 | 0.087 | Seq Scan on merchants; Index Scan (pk_transactions); Index Scan (uq_bank_accounts_id_user_id); Seq Scan on categories |
| R9 | READ | Fetch active monthly budget with all allocated categories and limits | 0.150 | 0.164 | 0.234 | 0.183 | Seq Scan on budgets; Index Scan (uq_budget_categories_budget_id_category_id); Index Scan (pk_categories) |
| R10 | READ | Check if user already has an existing active budget before creation | 0.014 | 0.024 | 0.017 | 0.018 | Seq Scan on budgets |
| R11 | READ | List all financial goals for user with milestone completion status | 0.404 | 0.663 | 0.508 | 0.525 | Seq Scan on goal_milestones; Seq Scan on financial_goals |
| R12 | READ | Retrieve specific financial goal details and progress milestones by ID | 0.190 | 0.200 | 0.195 | 0.195 | Index Scan (pk_financial_goals); Seq Scan on goal_milestones |
| R13 | READ | Fetch chronological transactions for ML feature engineering and behaviour analysis | 8.420 | 8.721 | 9.055 | 8.732 | Parallel Seq Scan on transactions; Seq Scan on categories; Seq Scan on merchants |
| R14 | READ | Fetch all user bank accounts to compute total liquid balance across institutions | 0.129 | 0.174 | 0.118 | 0.140 | Seq Scan on bank_accounts |
| R15 | READ | Fetch all active budgets to assess total spending limit and budget risk | 0.115 | 0.156 | 0.118 | 0.130 | Seq Scan on budgets |
| R16 | READ | Aggregate monthly cash inflow and outflow totals for current calendar month | 11.229 | 9.812 | 10.901 | 10.647 | Parallel Seq Scan on transactions |
| R17 | READ | Fetch latest computed ML behavioural profile and impulse index for user | 0.136 | 0.099 | 0.100 | 0.112 | Seq Scan on ml_profiles |
| R18 | READ | Fetch date-range bounded transactions with category and merchant metadata for calendar view | 9.949 | 9.362 | 9.740 | 9.684 | Parallel Seq Scan on transactions; Seq Scan on categories; Seq Scan on merchants |
| R19 | READ | Verify bank account existence and ownership before importing statement file | 0.022 | 0.025 | 0.032 | 0.026 | Index Scan (uq_bank_accounts_id_user_id) |
| R20 | READ | Probe transaction deduplication hash to avoid re-importing statement duplicates | 0.039 | 0.029 | 0.040 | 0.036 | Index Scan (uq_transactions_dedup_hash) |
| R21 | READ | Check if database already contains seeded demo records | 0.015 | 0.018 | 0.020 | 0.018 | Seq Scan on users |
| W1 | WRITE | Register new user account with hashed password and preferences | 0.122 | 0.045 | 0.066 | 0.078 | — |
| W2 | WRITE | Provision default simulated bank account for newly registered user | 0.381 | 0.351 | 0.377 | 0.370 | — |
| W3 | WRITE | Seed canonical spending category with UI icon and hex color | 0.027 | 0.033 | 0.035 | 0.032 | — |
| W4 | WRITE | Register recognized merchant with clean normalized name and default category link | 0.368 | 0.283 | 0.310 | 0.320 | — |
| W5 | WRITE | Insert new normalized bank transaction during automated adapter sync | 0.652 | 0.598 | 0.765 | 0.672 | — |
| W6 | WRITE | Update bank account current balance and last synced timestamp after sync | 0.155 | 0.130 | 0.147 | 0.144 | Index Scan (uq_bank_accounts_id_user_id) |
| W7 | WRITE | Create new monthly budget with start and end dates and total limit | 0.236 | 0.179 | 0.200 | 0.205 | — |
| W8 | WRITE | Insert category allocation amount and alert threshold into budget | 0.310 | 0.300 | 0.430 | 0.347 | — |
| W9 | WRITE | Update existing budget limit, period, or name | 0.150 | 0.226 | 0.139 | 0.172 | Index Scan (pk_budgets) |
| W10 | WRITE | Create new long-term financial goal with target date and planned return | 0.190 | 0.419 | 0.252 | 0.287 | — |
| W11 | WRITE | Insert intermediate target milestone for a financial goal | 0.583 | 0.204 | 0.187 | 0.325 | — |
| W12 | WRITE | Record incremental savings contribution towards financial goal target | 0.186 | 0.181 | 0.141 | 0.169 | Index Scan (pk_financial_goals) |
| W13 | WRITE | Mark milestone achieved when current saved balance reaches target threshold | 0.397 | 0.362 | 0.374 | 0.378 | Seq Scan on goal_milestones |
| W14 | WRITE | Ingest and persist deduplicated canonical transaction from statement file | 0.462 | 0.492 | 0.372 | 0.442 | — |
| W15 | WRITE | Persist computed ML behavioural profile snapshot and feature weights | 0.348 | 0.238 | 0.235 | 0.274 | — |
| W16 | WRITE | Seed initial demo profile and transaction history | 0.050 | 0.043 | 0.041 | 0.045 | — |

## Plan observations

The five highest average execution times were:

- **R16 — 10.647 ms average:** The plan uses a parallel sequential scan of transactions for the user and October date filter, then groups the matches by transaction type.
- **R18 — 9.684 ms average:** The plan uses a parallel sequential scan for the user/date filter, joins category and merchant lookups, then sorts the qualifying rows by occurrence time.
- **R7 — 9.409 ms average:** The plan uses a parallel sequential scan for the user filter and sorts transaction rows by occurrence time before applying the page limit.
- **R13 — 8.732 ms average:** The plan uses a parallel sequential scan for the user filter and sorts the matching transactions chronologically.
- **W5 — 0.672 ms average:** The plan inserts one transaction and spends measurable time checking its user, account, category, merchant, and account-owner foreign keys.

Sequential scans of `transactions` occur in **R7, R13, R16, R18**. The plans show broad scans for user/date filters and, for ordered reads, a separate sort. Consider (as recommendations only) an index on `transactions (user_id, occurred_at)` to support these filters and ordering; an `account_id` index for account-based lookups; and `budgets (user_id)` for user budget lookups. The existing `budget_categories (budget_id, category_id)` unique index is used by R9. No indexes or server settings were changed.

All READs returned rows in the fixture. No query required an empty-result NOTE. All WRITE statements succeeded in the rollback verification; UPDATE statements affected at least one row. The baseline row counts were unchanged after verification and the three timing runs.

Plan files are in `dbms/plans/`, one file per query with three run sections.
