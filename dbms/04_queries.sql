-- ============================================================================
-- Finora Application SQL Query Workload (AP CP3)
-- Database: PostgreSQL 15+
-- Schema: finora
-- Purpose: Exhaustive catalog of all SQL queries utilized across the Finora
--          backend (FastAPI + SQLAlchemy models, API v1 routes, services, seeder).
-- Conventions:
--   - Schema context set to finora
--   - Tagged as -- <ID> READ / WRITE — <plain english description>
--   - Exact source file and line references documented
--   - Explicit JOINs implemented where endpoints load related entities
--   - Realistic parameter literals provided with parameter comments
-- ============================================================================

SET search_path TO finora;

-- ============================================================================
-- SECTION 1: READ QUERIES (R1 – R21)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Feature: Authentication & User Management
-- ----------------------------------------------------------------------------

-- R1  READ  — Retrieve authenticated user profile by ID from JWT token payload
-- Source: backend/app/api/deps.py:48 (get_current_user_optional)
-- Parameter: :user_id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0'
SELECT id, email, hashed_password, full_name, currency, preferences, created_at, updated_at
FROM users
WHERE id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0';

-- R2  READ  — Retrieve default/primary demo user when no auth token is provided
-- Source: backend/app/api/deps.py:29 (get_current_user_optional)
-- Parameter: none (returns the earliest created user for demo/guest exploration)
SELECT id, email, hashed_password, full_name, currency, preferences, created_at, updated_at
FROM users
ORDER BY created_at ASC
LIMIT 1;

-- R3  READ  — Check if an account already exists with the given email during registration
-- Source: backend/app/api/v1/auth.py:26 (register_user)
-- Parameter: :email = 'yash@finora.app'
SELECT id, email
FROM users
WHERE email = 'yash@finora.app';

-- R4  READ  — Lookup user by email for password verification during login
-- Source: backend/app/api/v1/auth.py:65 (login)
-- Parameter: :email = 'demo@financialcall.ai'
SELECT id, email, hashed_password, full_name, currency, preferences, created_at, updated_at
FROM users
WHERE email = 'demo@financialcall.ai';


-- ----------------------------------------------------------------------------
-- Feature: Bank Accounts & Integration
-- ----------------------------------------------------------------------------

-- R5  READ  — Fetch user bank account by ID to verify ownership before initiating sync
-- Source: backend/app/api/v1/bank.py:45 (sync_bank_account)
-- Parameters: :account_id = 'acc_01h7x8a9b2c3d4e5f6g7h8j9k0', :user_id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0'
SELECT id, user_id, institution_name, account_number_masked, account_type,
       current_balance, currency, adapter_type, last_synced_at
FROM bank_accounts
WHERE id = 'acc_01h7x8a9b2c3d4e5f6g7h8j9k0'
  AND user_id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0';

-- R6  READ  — Check if a bank transaction already exists using SHA-256 deduplication hash
-- Source: backend/app/api/v1/bank.py:75 (sync_bank_account)
-- Parameter: :dedup_hash = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
SELECT id, dedup_hash, reference_id
FROM transactions
WHERE dedup_hash = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';


-- ----------------------------------------------------------------------------
-- Feature: Canonical Transactions
-- ----------------------------------------------------------------------------

-- R7  READ  — List paginated canonical transactions with joined category and merchant details
-- Source: backend/app/api/v1/transactions.py:31 (list_transactions)
-- Parameters: :user_id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0', :limit = 50, :offset = 0
-- NOTE: Endpoint maps raw records to schema with resolved merchant_name and category_name.
SELECT t.id, t.user_id, t.account_id, t.occurred_at, t.amount, t.currency,
       t.transaction_type, t.raw_description,
       coalesce(m.clean_name, 'Unknown Merchant') AS merchant_name,
       coalesce(c.name, 'Uncategorized') AS category_name,
       t.balance_before, t.balance_after, t.reference_id, t.source,
       t.dedup_hash, t.tax_info, t.metadata, t.created_at
FROM transactions t
LEFT JOIN categories c ON c.id = t.category_id
LEFT JOIN merchants m  ON m.id = t.merchant_id
WHERE t.user_id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0'
ORDER BY t.occurred_at DESC
OFFSET 0 LIMIT 50;

-- R8  READ  — Retrieve rich transaction detail including linked bank account, merchant, and category
-- Source: backend/app/api/v1/transactions.py:85 (get_transaction_detail)
-- Parameters: :transaction_id = 'tx_01h7x8a9b2c3d4e5f6g7h8j9k0', :user_id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0'
SELECT t.id, t.user_id, t.account_id, b.institution_name, b.account_number_masked,
       t.occurred_at, t.amount, t.currency, t.transaction_type, t.raw_description,
       coalesce(m.clean_name, 'Unknown Merchant') AS merchant_name,
       coalesce(c.name, 'Uncategorized') AS category_name,
       t.balance_before, t.balance_after, t.reference_id, t.source,
       t.dedup_hash, t.tax_info, t.metadata, t.created_at
FROM transactions t
INNER JOIN bank_accounts b ON b.id = t.account_id AND b.user_id = t.user_id
LEFT JOIN categories c     ON c.id = t.category_id
LEFT JOIN merchants m      ON m.id = t.merchant_id
WHERE t.id = 'tx_01h7x8a9b2c3d4e5f6g7h8j9k0'
  AND t.user_id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0';


-- ----------------------------------------------------------------------------
-- Feature: Budgets & Category Allocations
-- ----------------------------------------------------------------------------

-- R9  READ  — Fetch active monthly budget with all allocated categories and limits
-- Source: backend/app/api/v1/budgets.py:26 (get_active_budget)
-- Parameter: :user_id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0'
-- NOTE: Uses explicit JOINs over budget_categories and categories as loaded by BudgetResponse.
SELECT b.id AS budget_id, b.user_id, b.name AS budget_name, b.period, b.total_limit,
       b.start_date, b.end_date, b.created_at,
       bc.id AS allocation_id, bc.category_id,
       c.name AS category_name, c.slug AS category_slug,
       c.icon AS category_icon, c.color_hex AS category_color,
       bc.allocated_amount, bc.alert_threshold_percentage
FROM budgets b
LEFT JOIN budget_categories bc ON bc.budget_id = b.id
LEFT JOIN categories c        ON c.id = bc.category_id
WHERE b.user_id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0'
ORDER BY bc.allocated_amount DESC;

-- R10 READ  — Check if user already has an existing active budget before creation
-- Source: backend/app/api/v1/budgets.py:44 (create_or_update_budget)
-- Parameter: :user_id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0'
SELECT id, user_id, name, period, total_limit, start_date, end_date
FROM budgets
WHERE user_id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0'
LIMIT 1;


-- ----------------------------------------------------------------------------
-- Feature: Financial Goals & Milestones
-- ----------------------------------------------------------------------------

-- R11 READ  — List all financial goals for user with milestone completion status
-- Source: backend/app/api/v1/goals.py:27 (list_goals)
-- Parameter: :user_id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0'
-- NOTE: Endpoint serializes goal milestones with each goal response; joined explicitly.
SELECT g.id AS goal_id, g.user_id, g.title, g.goal_type, g.target_amount,
       g.current_saved, g.monthly_contribution, g.target_date,
       g.expected_annual_return_pct, g.status, g.created_at, g.updated_at,
       gm.id AS milestone_id, gm.title AS milestone_title,
       gm.target_amount AS milestone_target, gm.target_date AS milestone_date,
       gm.is_achieved, gm.achieved_at
FROM financial_goals g
LEFT JOIN goal_milestones gm ON gm.goal_id = g.id
WHERE g.user_id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0'
ORDER BY g.created_at ASC, gm.target_amount ASC;

-- R12 READ  — Retrieve specific financial goal details and progress milestones by ID
-- Source: backend/app/api/v1/goals.py:48 (get_goal_detail)
-- Parameters: :goal_id = 'gol_01h7x8a9b2c3d4e5f6g7h8j9k0', :user_id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0'
SELECT g.id, g.user_id, g.title, g.goal_type, g.target_amount, g.current_saved,
       g.monthly_contribution, g.target_date, g.expected_annual_return_pct,
       g.status, g.created_at, g.updated_at,
       gm.id AS milestone_id, gm.title AS milestone_title,
       gm.target_amount AS milestone_target, gm.target_date AS milestone_date,
       gm.is_achieved, gm.achieved_at
FROM financial_goals g
LEFT JOIN goal_milestones gm ON gm.goal_id = g.id
WHERE g.id = 'gol_01h7x8a9b2c3d4e5f6g7h8j9k0'
  AND g.user_id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0';


-- ----------------------------------------------------------------------------
-- Feature: Analytics & ML Intelligence
-- ----------------------------------------------------------------------------

-- R13 READ  — Fetch chronological transactions for ML feature engineering and behaviour analysis
-- Source: backend/app/api/v1/analytics.py:38 (_get_user_transactions)
-- Parameter: :user_id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0'
SELECT t.id, t.user_id, t.occurred_at, t.amount, t.currency, t.transaction_type,
       t.raw_description,
       coalesce(m.clean_name, 'Unknown Merchant') AS merchant_name,
       coalesce(c.name, 'Uncategorized') AS category_name,
       t.balance_after, t.reference_id, t.source, t.dedup_hash, t.metadata
FROM transactions t
LEFT JOIN categories c ON c.id = t.category_id
LEFT JOIN merchants m  ON m.id = t.merchant_id
WHERE t.user_id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0'
ORDER BY t.occurred_at ASC;

-- R14 READ  — Fetch all user bank accounts to compute total liquid balance across institutions
-- Source: backend/app/api/v1/analytics.py:78 (get_intelligence_overview)
-- Parameter: :user_id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0'
SELECT id, user_id, institution_name, account_number_masked, account_type,
       current_balance, currency
FROM bank_accounts
WHERE user_id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0';

-- R15 READ  — Fetch all active budgets to assess total spending limit and budget risk
-- Source: backend/app/api/v1/analytics.py:83 (get_intelligence_overview)
-- Parameter: :user_id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0'
SELECT id, user_id, name, period, total_limit, start_date, end_date
FROM budgets
WHERE user_id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0';

-- R16 READ  — Aggregate monthly cash inflow and outflow totals for current calendar month
-- Source: backend/app/api/v1/analytics.py:90 (get_intelligence_overview)
-- Parameters: :user_id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0', :start = '2026-10-01', :end = '2026-10-31'
SELECT transaction_type,
       coalesce(sum(amount), 0.00) AS total_amount,
       count(*) AS transaction_count
FROM transactions
WHERE user_id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0'
  AND occurred_at >= '2026-10-01 00:00:00+05:30'
  AND occurred_at <= '2026-10-31 23:59:59+05:30'
GROUP BY transaction_type;

-- R17 READ  — Fetch latest computed ML behavioural profile and impulse index for user
-- Source: backend/app/db/models/ml_profile.py (MLProfile model lookup)
-- Parameter: :user_id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0'
SELECT id, user_id, behavioural_score, impulse_spending_index, average_monthly_burn,
       predicted_savings_rate, category_spending_distribution, weekend_vs_weekday_ratio,
       feature_weights, last_computed_at
FROM ml_profiles
WHERE user_id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0'
ORDER BY last_computed_at DESC
LIMIT 1;


-- ----------------------------------------------------------------------------
-- Feature: Financial Calendar View
-- ----------------------------------------------------------------------------

-- R18 READ  — Fetch date-range bounded transactions with category and merchant metadata for calendar view
-- Source: backend/app/api/v1/calendar.py:51 (get_calendar_view)
-- Parameters: :user_id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0', :start_dt = '2026-10-01', :end_dt = '2026-10-31'
SELECT t.id, t.occurred_at, t.amount, t.currency, t.transaction_type,
       coalesce(m.clean_name, 'Unknown Merchant') AS merchant_name,
       coalesce(c.name, 'Uncategorized') AS category_name
FROM transactions t
LEFT JOIN categories c ON c.id = t.category_id
LEFT JOIN merchants m  ON m.id = t.merchant_id
WHERE t.user_id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0'
  AND t.occurred_at >= '2026-10-01 00:00:00+05:30'
  AND t.occurred_at <= '2026-10-31 23:59:59+05:30'
ORDER BY t.occurred_at ASC;


-- ----------------------------------------------------------------------------
-- Feature: Statement Ingestion & Deduplication
-- ----------------------------------------------------------------------------

-- R19 READ  — Verify bank account existence and ownership before importing statement file
-- Source: backend/app/api/v1/statements.py:34 (upload_statement)
-- Parameters: :account_id = 'acc_01h7x8a9b2c3d4e5f6g7h8j9k0', :user_id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0'
SELECT id, user_id, institution_name, account_number_masked, account_type,
       current_balance, currency, adapter_type
FROM bank_accounts
WHERE id = 'acc_01h7x8a9b2c3d4e5f6g7h8j9k0'
  AND user_id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0';

-- R20 READ  — Probe transaction deduplication hash to avoid re-importing statement duplicates
-- Source: backend/app/api/v1/statements.py:63 (upload_statement)
-- Parameter: :dedup_hash = 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2'
SELECT id, dedup_hash
FROM transactions
WHERE dedup_hash = 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2';


-- ----------------------------------------------------------------------------
-- Feature: Database Seeder Check
-- ----------------------------------------------------------------------------

-- R21 READ  — Check if database already contains seeded demo records
-- Source: backend/app/db/seeder.py:24 (seed_demo_data_if_empty)
-- Parameter: none
SELECT id, email, full_name
FROM users
LIMIT 1;


-- ============================================================================
-- SECTION 2: WRITE QUERIES (W1 – W16)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Feature: Auth & User Onboarding
-- ----------------------------------------------------------------------------

-- W1  WRITE — Register new user account with hashed password and preferences
-- Source: backend/app/api/v1/auth.py:38 (register_user)
INSERT INTO users (
    id, email, hashed_password, full_name, currency, preferences, created_at, updated_at
) VALUES (
    'usr_01h7x8a9b2c3d4e5f6g7h8j9k0',
    'yash@finora.app',
    '$2b$12$e8xL4QJ1...fakebcryptplaceholder...hash',
    'Yash Srivastava',
    'INR',
    '{"theme": "dark", "calendar_view": "month"}'::jsonb,
    now(),
    now()
);

-- W2  WRITE — Provision default simulated bank account for newly registered user
-- Source: backend/app/api/v1/auth.py:52 (register_user)
INSERT INTO bank_accounts (
    id, user_id, institution_name, account_number_masked, account_type,
    current_balance, currency, adapter_type, last_synced_at, created_at, updated_at
) VALUES (
    'acc_01h7x8a9b2c3d4e5f6g7h8j9k0',
    'usr_01h7x8a9b2c3d4e5f6g7h8j9k0',
    'HSBC Demo Bank',
    '•••• 4892',
    'SAVINGS',
    148500.00,
    'INR',
    'HSBC_DEMO',
    now(),
    now(),
    now()
);


-- ----------------------------------------------------------------------------
-- Feature: Master Categories & Merchants Reference Data
-- ----------------------------------------------------------------------------

-- W3  WRITE — Seed canonical spending category with UI icon and hex color
-- Source: backend/app/db/models/category.py (Category creation)
INSERT INTO categories (
    id, name, slug, icon, color_hex, is_system, parent_id
) VALUES (
    'cat_01h7x8a9b2c3d4e5f6g7h8j9k0',
    'Food & Dining',
    'food-and-dining',
    'Utensils',
    '#EF4444',
    TRUE,
    NULL
);

-- W4  WRITE — Register recognized merchant with clean normalized name and default category link
-- Source: backend/app/db/models/category.py (Merchant creation)
INSERT INTO merchants (
    id, clean_name, raw_patterns, default_category_id, logo_url, created_at
) VALUES (
    'mer_01h7x8a9b2c3d4e5f6g7h8j9k0',
    'Swiggy',
    '["swiggy", "swiggy instamart", "swiggy dineout"]'::jsonb,
    'cat_01h7x8a9b2c3d4e5f6g7h8j9k0',
    'https://assets.finora.app/logos/swiggy.png',
    now()
);


-- ----------------------------------------------------------------------------
-- Feature: Bank Sync & Transactions
-- ----------------------------------------------------------------------------

-- W5  WRITE — Insert new normalized bank transaction during automated adapter sync
-- Source: backend/app/api/v1/bank.py:98 (sync_bank_account)
INSERT INTO transactions (
    id, user_id, account_id, category_id, merchant_id, occurred_at,
    amount, currency, transaction_type, raw_description, balance_before,
    balance_after, reference_id, source, dedup_hash, tax_info, metadata, created_at
) VALUES (
    'tx_01h7x8a9b2c3d4e5f6g7h8j9k0',
    'usr_01h7x8a9b2c3d4e5f6g7h8j9k0',
    'acc_01h7x8a9b2c3d4e5f6g7h8j9k0',
    'cat_01h7x8a9b2c3d4e5f6g7h8j9k0',
    'mer_01h7x8a9b2c3d4e5f6g7h8j9k0',
    '2026-10-15 14:32:00+05:30',
    2450.00,
    'INR',
    'DEBIT',
    'SWIGGY BANGALORE IND',
    150950.00,
    148500.00,
    'REF-SYNC-987654',
    'BANK_API',
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    NULL,
    '{"channel": "ONLINE", "mcc": 5812}'::jsonb,
    now()
);

-- W6  WRITE — Update bank account current balance and last synced timestamp after sync
-- Source: backend/app/api/v1/bank.py:103 (sync_bank_account)
UPDATE bank_accounts
SET current_balance = 146050.00,
    last_synced_at = now(),
    updated_at = now()
WHERE id = 'acc_01h7x8a9b2c3d4e5f6g7h8j9k0'
  AND user_id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0';


-- ----------------------------------------------------------------------------
-- Feature: Budgets & Allocations
-- ----------------------------------------------------------------------------

-- W7  WRITE — Create new monthly budget with start and end dates and total limit
-- Source: backend/app/api/v1/budgets.py:78 (create_or_update_budget)
INSERT INTO budgets (
    id, user_id, name, period, total_limit, start_date, end_date, created_at
) VALUES (
    'bgt_01h7x8a9b2c3d4e5f6g7h8j9k0',
    'usr_01h7x8a9b2c3d4e5f6g7h8j9k0',
    'Monthly Discretionary & Core Budget',
    'MONTHLY',
    50000.00,
    '2026-10-01',
    '2026-10-31',
    now()
);

-- W8  WRITE — Insert category allocation amount and alert threshold into budget
-- Source: backend/app/api/v1/budgets.py:72 (create_or_update_budget)
INSERT INTO budget_categories (
    id, budget_id, category_id, allocated_amount, alert_threshold_percentage
) VALUES (
    'bca_01h7x8a9b2c3d4e5f6g7h8j9k0',
    'bgt_01h7x8a9b2c3d4e5f6g7h8j9k0',
    'cat_01h7x8a9b2c3d4e5f6g7h8j9k0',
    15000.00,
    80.00
);

-- W9  WRITE — Update existing budget limit, period, or name
-- Source: backend/app/api/v1/budgets.py:56 (create_or_update_budget)
UPDATE budgets
SET name = 'Q4 Scaled Discretionary Budget',
    total_limit = 65000.00
WHERE id = 'bgt_01h7x8a9b2c3d4e5f6g7h8j9k0'
  AND user_id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0';


-- ----------------------------------------------------------------------------
-- Feature: Financial Goals & Milestones
-- ----------------------------------------------------------------------------

-- W10 WRITE — Create new long-term financial goal with target date and planned return
-- Source: backend/app/api/v1/goals.py:87 (create_goal)
INSERT INTO financial_goals (
    id, user_id, title, goal_type, target_amount, current_saved,
    monthly_contribution, target_date, expected_annual_return_pct,
    status, created_at, updated_at
) VALUES (
    'gol_01h7x8a9b2c3d4e5f6g7h8j9k0',
    'usr_01h7x8a9b2c3d4e5f6g7h8j9k0',
    'Financial Independence (FIRE)',
    'RETIREMENT',
    2500000.00,
    420000.00,
    18000.00,
    '2033-10-31',
    12.00,
    'IN_PROGRESS',
    now(),
    now()
);

-- W11 WRITE — Insert intermediate target milestone for a financial goal
-- Source: backend/app/api/v1/goals.py:80 (create_goal)
INSERT INTO goal_milestones (
    id, goal_id, title, target_amount, target_date, is_achieved, achieved_at
) VALUES (
    'mls_01h7x8a9b2c3d4e5f6g7h8j9k0',
    'gol_01h7x8a9b2c3d4e5f6g7h8j9k0',
    'Quarter Milestone (25%)',
    625000.00,
    '2028-06-30',
    FALSE,
    NULL
);

-- W12 WRITE — Record incremental savings contribution towards financial goal target
-- Source: backend/app/api/v1/goals.py:121 (update_goal_progress)
UPDATE financial_goals
SET current_saved = current_saved + 25000.00,
    updated_at = now()
WHERE id = 'gol_01h7x8a9b2c3d4e5f6g7h8j9k0'
  AND user_id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0';

-- W13 WRITE — Mark milestone achieved when current saved balance reaches target threshold
-- Source: backend/app/api/v1/goals.py:124 (update_goal_progress)
UPDATE goal_milestones
SET is_achieved = TRUE,
    achieved_at = now()
WHERE goal_id = 'gol_01h7x8a9b2c3d4e5f6g7h8j9k0'
  AND target_amount <= 445000.00
  AND is_achieved = FALSE;


-- ----------------------------------------------------------------------------
-- Feature: Statement File Ingestion
-- ----------------------------------------------------------------------------

-- W14 WRITE — Ingest and persist deduplicated canonical transaction from statement file
-- Source: backend/app/api/v1/statements.py:84 (upload_statement)
INSERT INTO transactions (
    id, user_id, account_id, category_id, merchant_id, occurred_at,
    amount, currency, transaction_type, raw_description, balance_before,
    balance_after, reference_id, source, dedup_hash, tax_info, metadata, created_at
) VALUES (
    'tx_01h7x8a9b2c3d4e5f6g7h8j9k1',
    'usr_01h7x8a9b2c3d4e5f6g7h8j9k0',
    'acc_01h7x8a9b2c3d4e5f6g7h8j9k0',
    NULL,
    NULL,
    '2026-10-04 19:12:00+05:30',
    899.00,
    'INR',
    'DEBIT',
    'AMAZON PAY INDIA',
    151849.00,
    150950.00,
    'STMT-OCT-00491',
    'CSV',
    'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2',
    NULL,
    '{"imported_file": "october_2026_statement.csv"}'::jsonb,
    now()
);


-- ----------------------------------------------------------------------------
-- Feature: ML Intelligence Profiles
-- ----------------------------------------------------------------------------

-- W15 WRITE — Persist computed ML behavioural profile snapshot and feature weights
-- Source: backend/app/db/models/ml_profile.py (MLProfile persistence)
INSERT INTO ml_profiles (
    id, user_id, behavioural_score, impulse_spending_index, average_monthly_burn,
    predicted_savings_rate, category_spending_distribution, weekend_vs_weekday_ratio,
    feature_weights, last_computed_at
) VALUES (
    'mlp_01h7x8a9b2c3d4e5f6g7h8j9k0',
    'usr_01h7x8a9b2c3d4e5f6g7h8j9k0',
    82.50,
    0.1850,
    42350.00,
    24.50,
    '{"Food & Dining": 0.28, "Shopping": 0.18, "Bills & Utilities": 0.34, "Travel": 0.20}'::jsonb,
    '{"weekend_ratio": 1.45, "weekday_average": 1120.00, "weekend_average": 1624.00}'::jsonb,
    '{"savings_weight": 0.35, "impulse_weight": 0.35, "budget_adherence": 0.30}'::jsonb,
    now()
);


-- ----------------------------------------------------------------------------
-- Feature: Database Seeder Execution
-- ----------------------------------------------------------------------------

-- W16 WRITE — Seed initial demo profile and transaction history
-- Source: backend/app/db/seeder.py:39-114 (seed_demo_data_if_empty)
INSERT INTO users (
    id, email, hashed_password, full_name, currency, preferences, created_at, updated_at
) VALUES (
    'usr_seed_user_001',
    'demo_seed@financialcall.ai',
    '$2b$12$K8yXvL3Qv1mKzJ6Y3tGq5.EXAMPLEHASH1234567890',
    'Yash Srivastava',
    'INR',
    '{"plan_tier": "INDIVIDUAL_PRO", "theme": "dark"}'::jsonb,
    now(),
    now()
);

-- End of dbms/04_queries.sql
