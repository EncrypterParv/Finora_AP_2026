# Finora Database Normalization: UNF to 3NF / BCNF

## 1. Overview

Finora stores user identities and preferences alongside users’ bank accounts and imported financial transactions. Transactions reference categories and merchants and retain source, balance, tax, and metadata details. Users define budgets with per-category allocations and savings goals with dated milestones. The app also stores machine-learning spending profiles and their computed metrics. This analysis follows the eight supplied SQLAlchemy model files and the ten mapped tables.

## 2. Unnormalized form (UNF)

A single wide **user finance record** would contain nested, repeating collections for accounts, transactions (including category and merchant details), budgets (including category allocations), goals (including milestones), and ML profiles. The following illustrative data uses abbreviated values; each cell marked `{…}` is a repeating group, not a scalar SQL value.

| user_id | email | preferences | accounts {account_id, institution, balance, transactions {transaction_id, date, amount, currency, category, merchant}} | budgets {budget_id, name, limit, allocations {category, amount, threshold}} | goals {goal_id, title, target, milestones {title, amount, date}} | ml_profiles {profile_id, metrics} |
|---|---|---|---|---|---|---|
| U1 | a@example.test | `{theme: dark}` | `{A1, Bank A, 5000, [T1: 2026-11-01, -250, INR, Food, Cafe X]; T2: 2026-11-02, -80, INR, Travel, Metro}` | `{B1, Monthly, 20000, [Food: 5000/80%, Travel: 2000/80%]}` | `{G1, Emergency, 50000, [First 10000: 2026-12-01]}` | `{P1, score 75}` |
| U2 | b@example.test | `{theme: light}` | `{A2, Bank B, 9000, [T3: 2026-11-03, -120, INR, Food, Cafe X]}` | `{B2, Weekly, 6000, [Food: 1500/75%]}` | `{G2, Travel, 30000, [First 5000: 2027-01-01; Halfway 15000: 2027-06-01]}` | `{P2, score 81}` |

This representation duplicates user, account, category, merchant, budget, and goal facts across nested groups. It is difficult to update one fact without editing a large record and does not support relational atomic values.

## 3. First normal form (1NF)

The repeating entity groups are represented as separate relations with primary keys and foreign keys. Every ordinary column holds one scalar value per row. The model’s JSON document columns are the explicit exception/qualification discussed below.

Relations after decomposition (column names follow the models):

- `users(id, email, hashed_password, full_name, currency, preferences, created_at, updated_at)`
- `bank_accounts(id, user_id, institution_name, account_number_masked, account_type, current_balance, currency, adapter_type, last_synced_at, created_at, updated_at)`
- `categories(id, name, slug, icon, color_hex, is_system, parent_id)`
- `merchants(id, clean_name, raw_patterns, default_category_id, logo_url, created_at)`
- `transactions(id, user_id, account_id, category_id, merchant_id, occurred_at, amount, currency, transaction_type, raw_description, balance_before, balance_after, reference_id, source, dedup_hash, tax_info, metadata, created_at)`
- `budgets(id, user_id, name, period, total_limit, start_date, end_date, created_at)`
- `budget_categories(id, budget_id, category_id, allocated_amount, alert_threshold_percentage)`
- `financial_goals(id, user_id, title, goal_type, target_amount, current_saved, monthly_contribution, target_date, expected_annual_return_pct, status, created_at, updated_at)`
- `goal_milestones(id, goal_id, title, target_amount, target_date, is_achieved, achieved_at)`
- `ml_profiles(id, user_id, behavioural_score, impulse_spending_index, average_monthly_burn, predicted_savings_rate, category_spending_distribution, weekend_vs_weekday_ratio, feature_weights, last_computed_at)`

**JSON values:** `merchants.raw_patterns` is explicitly a list. Strict 1NF would require one pattern per row, using a relation such as `merchant_patterns(merchant_id, pattern)` with a composite key. **RECOMMENDED CHANGE (optional):** adopt that decomposition if patterns need independent querying, updating, or constraints. The current model keeps the list as a JSON document because the app uses it as a whole for matching; as stored, that column is not strictly atomic under the classical 1NF definition. `users.preferences`, `transactions.tax_info`, `transactions.metadata`, and the three `ml_profiles` JSON columns (`category_spending_distribution`, `weekend_vs_weekday_ratio`, `feature_weights`) are treated as single document values by this design. If internal keys become independently queried or constrained, they too should be decomposed.

### Functional dependencies at 1NF

At this stage the key-based dependencies are (descriptive attributes omitted only where indicated):

- `users`: `id → email, hashed_password, full_name, currency, preferences, created_at, updated_at`; also `email → id, hashed_password, full_name, currency, preferences, created_at, updated_at` because `email` is unique.
- `bank_accounts`: `id → user_id, institution_name, account_number_masked, account_type, current_balance, currency, adapter_type, last_synced_at, created_at, updated_at`.
- `categories`: `id → name, slug, icon, color_hex, is_system, parent_id`; `name → id, slug, icon, color_hex, is_system, parent_id`; `slug → id, name, icon, color_hex, is_system, parent_id`.
- `merchants`: `id → clean_name, raw_patterns, default_category_id, logo_url, created_at`; `clean_name → id, raw_patterns, default_category_id, logo_url, created_at`.
- `transactions`: `id → all other transaction columns`; `dedup_hash → id, all other transaction columns` (unique).
- `budgets`: `id → user_id, name, period, total_limit, start_date, end_date, created_at`.
- `budget_categories`: `id → budget_id, category_id, allocated_amount, alert_threshold_percentage`; under the intended one-allocation-per-category-per-budget rule, `(budget_id, category_id) → allocated_amount, alert_threshold_percentage`.
- `financial_goals`: `id → all other goal columns`.
- `goal_milestones`: `id → all other milestone columns`.
- `ml_profiles`: `id → user_id, all profile metrics/documents, last_computed_at`.

These FDs reflect declared keys and the stated allocation rule, not accidental equality of sample values.

## 4. Second normal form (2NF)

2NF removes dependencies of a non-key attribute on only part of a composite candidate key. The models’ primary keys are single-column UUID strings, so their non-key columns cannot depend on a proper subset of those primary keys; those relations are automatically in 2NF with respect to the declared primary key.

`budget_categories` is the key case. Its natural key is `(budget_id, category_id)`: `allocated_amount` and `alert_threshold_percentage` describe the allocation for that particular category in that particular budget and depend on the whole pair. Neither column should be determined by `budget_id` alone or `category_id` alone. The model currently gives each row a surrogate `id`, however, and does not declare the pair unique. **RECOMMENDED CHANGE:** add `UNIQUE (budget_id, category_id)` so the intended natural key is enforced and duplicate allocations cannot make the natural-key FD false. Its FK columns are already non-null.

If merchant patterns are decomposed, `(merchant_id, pattern)` can be a composite key; it has no non-key attribute and thus no partial dependency. The 2NF statement for JSON documents follows the document-value design decision in §3.

## 5. Third normal form / BCNF

FDs below use the shorthand `key → remaining non-key columns`. A candidate key is a determinant that is a superkey; BCNF requires every non-trivial determinant to be a superkey. Declared unique keys are included. Foreign-key references do not, by themselves, imply an FD in the referencing table.

| Relation | Functional dependencies and normal-form notes |
|---|---|
| `users` | `id → email, hashed_password, full_name, currency, preferences, created_at, updated_at`; `email → id, hashed_password, full_name, currency, preferences, created_at, updated_at`. Candidate keys: `id`, `email`. Both determinants are keys, so BCNF under declared constraints. |
| `bank_accounts` | `id → user_id, institution_name, account_number_masked, account_type, current_balance, currency, adapter_type, last_synced_at, created_at, updated_at`. No other declared unique key. BCNF under stated FDs. |
| `categories` | `id → name, slug, icon, color_hex, is_system, parent_id`; `name → id, slug, icon, color_hex, is_system, parent_id`; `slug → id, name, icon, color_hex, is_system, parent_id`. Candidate keys are `id`, `name`, `slug`; each determinant is a key, so BCNF. |
| `merchants` | `id → clean_name, raw_patterns, default_category_id, logo_url, created_at`; `clean_name → id, raw_patterns, default_category_id, logo_url, created_at`. Candidate keys `id`, `clean_name`; BCNF under declared constraints. `raw_patterns` retains the 1NF qualification above. |
| `transactions` | `id → all other columns`; `dedup_hash → id, all other columns`. Both are candidate keys by declared uniqueness. In addition, the tuple `(account_id, user_id)` must reference `(bank_accounts.id, bank_accounts.user_id)`, and on valid data `account_id → user_id` follows from the referenced account row. Thus in the transaction relation `account_id → user_id` is a transitive dependency (via key `id`) and `user_id` is redundant with the account. **Decision:** keep `user_id` for per-user query access. **RECOMMENDED CHANGE:** enforce the pair with `UNIQUE (bank_accounts.id, bank_accounts.user_id)` (or rely on `id` being unique while declaring a matching composite unique constraint) and composite FK `(transactions.account_id, transactions.user_id) → bank_accounts(id, user_id)`. PostgreSQL requires an exact unique referenced column set for this composite FK. This enforces consistency while retaining the access path; it is a documented controlled denormalization, so the resulting transaction relation is not strict 3NF/BCNF with this FD. |
| `budgets` | `id → user_id, name, period, total_limit, start_date, end_date, created_at`. No declared alternate key. BCNF under stated FDs. |
| `budget_categories` | `id → budget_id, category_id, allocated_amount, alert_threshold_percentage`; recommended `(budget_id, category_id) → allocated_amount, alert_threshold_percentage`. With the recommended unique pair, both `id` and the pair are candidate keys and each determinant is a superkey: BCNF. |
| `financial_goals` | `id → user_id, title, goal_type, target_amount, current_saved, monthly_contribution, target_date, expected_annual_return_pct, status, created_at, updated_at`. BCNF under stated FDs. |
| `goal_milestones` | `id → goal_id, title, target_amount, target_date, is_achieved, achieved_at`. BCNF under stated FDs. |
| `ml_profiles` | `id → user_id, behavioural_score, impulse_spending_index, average_monthly_burn, predicted_savings_rate, category_spending_distribution, weekend_vs_weekday_ratio, feature_weights, last_computed_at`. `user_id` is not unique in the model. The relationship is one user to many profiles, so multiple rows / snapshots per user are permitted. Search of `backend/app` found model registration and relationship declarations but no profile write path establishing whether rows are updated or appended; no `user_id → profile attributes` FD is asserted. BCNF by the declared key FD. |

### Transitive and derived data decisions

- `transactions.user_id` is transitively determined by `account_id` through `bank_accounts.user_id`. It is retained for per-user queries, with the recommended composite FK above to ensure that the direct user and account owner agree.
- `bank_accounts.current_balance` can be recomputed from that account’s transaction history only if the history is complete and amount/type semantics, opening balance, reversals, pending items, and currency handling are fully specified. The model does not establish those conditions. **Keep** it as an operational balance snapshot/cache.
- `transactions.balance_before` and `balance_after` are recorded transaction-time facts and useful reconciliation/audit evidence; they are not safely derivable from current transaction rows after imports, corrections, or incomplete history. **Keep** them.
- `financial_goals.current_saved` may be a progress total but there is no contribution/ledger relation in these models from which to derive it. **Keep** as the stored current progress value.
- All `ml_profiles` scalar metrics and JSON distributions/weights are computed profile outputs based on transaction data. **Keep** as a time-stamped materialized snapshot (`last_computed_at`), since the model supports multiple profiles per user and snapshots preserve prior computed results. They are not independent base facts, and the model has no uniqueness constraint on `user_id`.
- `currency` in `users`, `bank_accounts`, and `transactions` has distinct scopes: user default/display preference, the account’s denomination, and the transaction’s currency (which can represent a transaction-specific/imported currency). Do not treat these as redundant copies; retain all three.

Under the recommended allocation constraint, the relations meet 3NF and generally BCNF for the declared FDs. The deliberate `transactions.user_id` duplication is the identified exception to strict 3NF/BCNF. The JSON list in `merchants.raw_patterns` is the identified strict-1NF exception unless it is decomposed.

## 6. Final 3NF tables

The list below is the model-aligned target for `dbms/03_schema.sql`. `PK`, `FK`, uniqueness, and non-nullability follow the model, with the two clearly marked recommended schema changes. SQLAlchemy’s `nullable=False` and primary key declarations determine `NOT NULL`; nullable columns are labeled optional. Model defaults are not repeated here because they are not key constraints. `ON DELETE` reflects each `ForeignKey` declaration.

| Table | PK | FKs (delete action) | UNIQUE | Key / other NOT NULL columns |
|---|---|---|---|---|
| `users` | `id` | — | `email` | `id`, `email`, `hashed_password`, `full_name`, `currency`, `preferences`, `created_at`, `updated_at` |
| `bank_accounts` | `id` | `user_id → users.id (CASCADE)` | — | `id`, `user_id`, `institution_name`, `account_number_masked`, `account_type`, `current_balance`, `currency`, `adapter_type`, `created_at`, `updated_at`; `last_synced_at` optional |
| `categories` | `id` | `parent_id → categories.id (SET NULL)` | `name`, `slug` | `id`, `name`, `slug`, `icon`, `color_hex`, `is_system`; `parent_id` optional |
| `merchants` | `id` | `default_category_id → categories.id (SET NULL)` | `clean_name` | `id`, `clean_name`, `raw_patterns`, `created_at`; `default_category_id`, `logo_url` optional |
| `transactions` | `id` | `user_id → users.id (CASCADE)`; `account_id → bank_accounts.id (CASCADE)`; `category_id → categories.id (SET NULL)`; `merchant_id → merchants.id (SET NULL)`; recommended composite `(account_id, user_id) → bank_accounts(id, user_id)` | `dedup_hash` | `id`, `user_id`, `account_id`, `occurred_at`, `amount`, `currency`, `transaction_type`, `raw_description`, `reference_id`, `source`, `dedup_hash`, `metadata`, `created_at`; `category_id`, `merchant_id`, `balance_before`, `balance_after`, `tax_info` optional |
| `budgets` | `id` | `user_id → users.id (CASCADE)` | — | `id`, `user_id`, `name`, `period`, `total_limit`, `start_date`, `end_date`, `created_at` |
| `budget_categories` | `id` | `budget_id → budgets.id (CASCADE)`; `category_id → categories.id (CASCADE)` | recommended `(budget_id, category_id)` | `id`, `budget_id`, `category_id`, `allocated_amount`, `alert_threshold_percentage` |
| `financial_goals` | `id` | `user_id → users.id (CASCADE)` | — | `id`, `user_id`, `title`, `goal_type`, `target_amount`, `current_saved`, `monthly_contribution`, `target_date`, `expected_annual_return_pct`, `status`, `created_at`, `updated_at` |
| `goal_milestones` | `id` | `goal_id → financial_goals.id (CASCADE)` | — | `id`, `goal_id`, `title`, `target_amount`, `target_date`, `is_achieved`; `achieved_at` optional |
| `ml_profiles` | `id` | `user_id → users.id (CASCADE)` | — (`user_id` intentionally not unique) | `id`, `user_id`, `behavioural_score`, `impulse_spending_index`, `average_monthly_burn`, `predicted_savings_rate`, `category_spending_distribution`, `weekend_vs_weekday_ratio`, `feature_weights`, `last_computed_at` |

**Schema implementation notes:** the models’ physical transaction column is named `metadata` (`metadata_` is the Python attribute); use `metadata` in SQL. For the recommended composite transaction FK, also declare a unique constraint over `bank_accounts(id, user_id)` so PostgreSQL accepts the referenced pair. That is logically redundant with the PK `id`, but enables the exact composite reference. The independent single-column transaction FKs should remain as modeled unless intentionally replaced. Keep the ordinary single-column PKs and all model nullability shown above.

## 7. Assumptions

- **A1.** The eight files under `backend/app/db/models/` are the authoritative model definition for this analysis; actual database migrations or external schema changes were not supplied.
- **A2.** Key FDs follow declared primary keys and uniqueness constraints. No undocumented business key, such as account number uniqueness per institution, is assumed.
- **A3.** `email`, category `name` and `slug`, merchant `clean_name`, and transaction `dedup_hash` are unique as declared in the models.
- **A4.** One budget should have at most one allocation row per category. The models do not currently enforce this; adding the unique pair is a **RECOMMENDED CHANGE**.
- **A5.** A transaction’s account must belong to the same user as its `user_id`. The models declare separate FKs but do not enforce ownership agreement; the composite FK is a **RECOMMENDED CHANGE**.
- **A6.** The JSON document columns are intentionally handled as whole values by the current app design; except for the known `raw_patterns` list, they count as one document value for this practical normalization analysis.
- **A7.** `ml_profiles` can contain multiple profiles per user because `user_id` lacks a unique constraint and the ORM relationship is one-to-many. Whether the app will append snapshots or update a current row cannot be established from the searched `backend/app` code.
- **A8.** Balance and ML values are operational snapshots or derived outputs with their own capture/computation time and are retained for the uses described in §5.
- **A9.** Currency fields represent different scopes (user default, account denomination, transaction denomination) and may legitimately differ.
