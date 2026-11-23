-- Deterministic AP CP4 workload fixture. Load after dbms/03_schema.sql.
SET search_path TO finora;
SELECT setseed(0.42);

INSERT INTO users (id, email, hashed_password, full_name, currency, preferences, created_at, updated_at)
SELECT 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0', 'yash@finora.app', '$2b$12$fixture-placeholder',
       'Yash Srivastava', 'INR', '{"theme":"dark"}'::jsonb, TIMESTAMPTZ '2025-05-23 00:00:00+05:30', now()
UNION ALL
SELECT CASE WHEN g = 2 THEN 'usr_seed_user_001' ELSE 'usr_gen_' || lpad(g::text, 4, '0') END,
       CASE WHEN g = 1 THEN 'demo@financialcall.ai' WHEN g = 2 THEN 'demo_seed@financialcall.ai' ELSE 'user' || lpad(g::text, 4, '0') || '@finora.app' END,
       '$2b$12$fixture-placeholder', 'Finora User ' || g, 'INR', '{}'::jsonb,
       TIMESTAMPTZ '2025-05-23 00:00:00+05:30' + g * INTERVAL '1 minute', now()
FROM generate_series(1, 999) AS g;

INSERT INTO categories (id, name, slug, icon, color_hex, is_system, parent_id) VALUES
('cat_01h7x8a9b2c3d4e5f6g7h8j9k0', 'Food & Dining', 'food-and-dining', 'Utensils', '#EF4444', TRUE, NULL),
('cat_sys_02', 'Groceries', 'groceries', 'ShoppingBasket', '#22C55E', TRUE, NULL),
('cat_sys_03', 'Transportation', 'transportation', 'Car', '#3B82F6', TRUE, NULL),
('cat_sys_04', 'Bills & Utilities', 'bills-utilities', 'Receipt', '#F97316', TRUE, NULL),
('cat_sys_05', 'Shopping', 'shopping', 'ShoppingBag', '#A855F7', TRUE, NULL),
('cat_sys_06', 'Healthcare', 'healthcare', 'HeartPulse', '#EC4899', TRUE, NULL),
('cat_sys_07', 'Entertainment', 'entertainment', 'Clapperboard', '#14B8A6', TRUE, NULL),
('cat_sys_08', 'Travel', 'travel', 'Plane', '#0EA5E9', TRUE, NULL),
('cat_sys_09', 'Education', 'education', 'BookOpen', '#6366F1', TRUE, NULL),
('cat_sys_10', 'Personal Care', 'personal-care', 'Sparkles', '#D946EF', TRUE, NULL),
('cat_sys_11', 'Housing', 'housing', 'House', '#64748B', TRUE, NULL),
('cat_sys_12', 'Insurance', 'insurance', 'Shield', '#84CC16', TRUE, NULL),
('cat_sys_13', 'Investments', 'investments', 'ChartNoAxesCombined', '#10B981', TRUE, NULL),
('cat_sys_14', 'Income', 'income', 'Wallet', '#059669', TRUE, NULL),
('cat_sys_15', 'Fees & Charges', 'fees-charges', 'CircleDollarSign', '#DC2626', TRUE, NULL),
('cat_sys_16', 'Gifts & Donations', 'gifts-donations', 'Gift', '#DB2777', TRUE, NULL),
('cat_sys_17', 'Pet Care', 'pet-care', 'PawPrint', '#CA8A04', TRUE, NULL),
('cat_sys_18', 'Dining Out', 'dining-out', 'UtensilsCrossed', '#FB7185', TRUE, 'cat_01h7x8a9b2c3d4e5f6g7h8j9k0'),
('cat_sys_19', 'Fast Food', 'fast-food', 'Sandwich', '#F43F5E', TRUE, 'cat_01h7x8a9b2c3d4e5f6g7h8j9k0'),
('cat_sys_20', 'Coffee & Cafes', 'coffee-cafes', 'Coffee', '#A16207', TRUE, 'cat_01h7x8a9b2c3d4e5f6g7h8j9k0');

INSERT INTO merchants (id, clean_name, raw_patterns, default_category_id, logo_url, created_at)
SELECT CASE WHEN g = 1 THEN 'mer_01h7x8a9b2c3d4e5f6g7h8j9k0' ELSE 'mer_gen_' || lpad(g::text, 3, '0') END,
       CASE WHEN g = 1 THEN 'Swiggy' ELSE 'Merchant ' || lpad(g::text, 3, '0') END,
       jsonb_build_array(lower(CASE WHEN g = 1 THEN 'Swiggy' ELSE 'Merchant ' || g END)),
       CASE WHEN g = 1 THEN 'cat_01h7x8a9b2c3d4e5f6g7h8j9k0' ELSE 'cat_sys_' || lpad(((g - 2) % 19 + 2)::text, 2, '0') END,
       NULL, TIMESTAMPTZ '2025-05-23 00:00:00+05:30' + g * INTERVAL '1 minute'
FROM generate_series(1, 300) AS g;

WITH ranked_users AS (
  SELECT id, row_number() OVER (ORDER BY CASE WHEN id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0' THEN 0 ELSE 1 END, id) - 1 AS user_no
  FROM users
)
INSERT INTO bank_accounts (id, user_id, institution_name, account_number_masked, account_type, current_balance, currency, adapter_type, last_synced_at, created_at, updated_at)
SELECT CASE WHEN u.user_no = 0 AND a.n = 1 THEN 'acc_01h7x8a9b2c3d4e5f6g7h8j9k0' ELSE 'acc_' || u.id || '_' || a.n END,
       u.id, CASE WHEN a.n = 1 THEN 'HSBC Demo Bank' ELSE 'Finora Bank ' || a.n END,
       '•••• ' || lpad((1000 + u.user_no * 2 + a.n)::text, 4, '0'),
       CASE WHEN a.n = 1 THEN 'SAVINGS' ELSE 'CHECKING' END,
       (50000 + u.user_no * 17 + a.n * 100)::numeric(14,2), 'INR', 'HSBC_DEMO',
       TIMESTAMPTZ '2026-11-22 10:00:00+05:30', now(), now()
FROM ranked_users u CROSS JOIN generate_series(1, 2) AS a(n);

WITH ranked_users AS (
  SELECT id, row_number() OVER (ORDER BY CASE WHEN id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0' THEN 0 ELSE 1 END, id) - 1 AS user_no
  FROM users
), ranked_categories AS (
  SELECT id, row_number() OVER (ORDER BY CASE WHEN id = 'cat_01h7x8a9b2c3d4e5f6g7h8j9k0' THEN 0 ELSE 1 END, id) AS category_no
  FROM categories
), ranked_merchants AS (
  SELECT id, row_number() OVER (ORDER BY CASE WHEN id = 'mer_01h7x8a9b2c3d4e5f6g7h8j9k0' THEN 0 ELSE 1 END, id) AS merchant_no
  FROM merchants
), generated AS (
  SELECT g AS n, ((g - 1) % 1000) AS user_no, (((g - 1) / 1000) % 2 + 1)::int AS account_no,
         ((g * 7919) % 549)::int AS day_no, ((g * 37) % 86400)::int AS second_no
  FROM generate_series(1, 200000) AS g
)
INSERT INTO transactions (id, user_id, account_id, category_id, merchant_id, occurred_at, amount, currency, transaction_type, raw_description, balance_before, balance_after, reference_id, source, dedup_hash, tax_info, metadata, created_at)
SELECT CASE n WHEN 1 THEN 'tx_01h7x8a9b2c3d4e5f6g7h8j9k0' WHEN 2 THEN 'tx_01h7x8a9b2c3d4e5f6g7h8j9k1' ELSE 'tx_gen_' || lpad(n::text, 6, '0') END,
       u.id,
       CASE WHEN u.user_no = 0 AND g.account_no = 1 THEN 'acc_01h7x8a9b2c3d4e5f6g7h8j9k0' ELSE 'acc_' || u.id || '_' || g.account_no END,
       c.id, m.id,
       TIMESTAMPTZ '2025-05-23 00:00:00+05:30' + g.day_no * INTERVAL '1 day' + g.second_no * INTERVAL '1 second',
       round((100 + random() * 50000)::numeric, 2), 'INR',
       CASE n % 3 WHEN 0 THEN 'CREDIT' WHEN 1 THEN 'DEBIT' ELSE 'TRANSFER' END,
       CASE n % 3 WHEN 0 THEN 'SALARY CREDIT' WHEN 1 THEN 'CARD PURCHASE' ELSE 'ACCOUNT TRANSFER' END,
       200000 + n * 500, 200000 + n * 500 - 250,
       'REF-' || lpad(n::text, 8, '0'), CASE WHEN n % 4 = 0 THEN 'CSV' ELSE 'BANK_API' END,
       CASE n WHEN 1 THEN 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
              WHEN 2 THEN 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2'
              ELSE md5('finora_cp4_transaction_' || n::text) END,
       NULL, jsonb_build_object('fixture_row', n), now()
FROM generated g
JOIN ranked_users u ON u.user_no = g.user_no
JOIN ranked_categories c ON c.category_no = ((g.n - 1) % 20 + 1)
JOIN ranked_merchants m ON m.merchant_no = ((g.n - 1) % 300 + 1);

WITH ranked_users AS (
  SELECT id, row_number() OVER (ORDER BY CASE WHEN id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0' THEN 0 ELSE 1 END, id) - 1 AS user_no
  FROM users
)
INSERT INTO budgets (id, user_id, name, period, total_limit, start_date, end_date, created_at)
SELECT CASE WHEN g = 1 THEN 'bgt_01h7x8a9b2c3d4e5f6g7h8j9k0' ELSE 'bgt_gen_' || lpad(g::text, 4, '0') END,
       u.id, CASE WHEN g = 1 THEN 'October Monthly Budget' ELSE 'Monthly Budget ' || g END,
       'MONTHLY', 30000 + g * 10, DATE '2026-10-01', DATE '2026-10-31', now()
FROM generate_series(1, 3000) AS g
JOIN ranked_users u ON u.user_no = (g - 1) % 1000;

WITH ranked_categories AS (
  SELECT id, row_number() OVER (ORDER BY CASE WHEN id = 'cat_01h7x8a9b2c3d4e5f6g7h8j9k0' THEN 0 ELSE 1 END, id) AS category_no
  FROM categories
)
INSERT INTO budget_categories (id, budget_id, category_id, allocated_amount, alert_threshold_percentage)
SELECT CASE WHEN g = 1 THEN 'bca_01h7x8a9b2c3d4e5f6g7h8j9k0' ELSE 'bca_gen_' || lpad(g::text, 5, '0') END,
       CASE WHEN ((g - 1) / 3 + 1) = 1 THEN 'bgt_01h7x8a9b2c3d4e5f6g7h8j9k0' ELSE 'bgt_gen_' || lpad((((g - 1) / 3 + 1)::int)::text, 4, '0') END,
       c.id, 1000 + g * 5, 80.00
FROM generate_series(1, 9000) AS g
JOIN ranked_categories c ON c.category_no = ((g - 1) % 20 + 1);

WITH ranked_users AS (
  SELECT id, row_number() OVER (ORDER BY CASE WHEN id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0' THEN 0 ELSE 1 END, id) - 1 AS user_no
  FROM users
)
INSERT INTO financial_goals (id, user_id, title, goal_type, target_amount, current_saved, monthly_contribution, target_date, expected_annual_return_pct, status, created_at, updated_at)
SELECT CASE WHEN g = 1 THEN 'gol_01h7x8a9b2c3d4e5f6g7h8j9k0' ELSE 'gol_gen_' || lpad(g::text, 4, '0') END,
       u.id, CASE WHEN g = 1 THEN 'Financial Independence (FIRE)' ELSE 'Savings Goal ' || g END,
       CASE WHEN g = 1 THEN 'RETIREMENT' ELSE 'EMERGENCY_FUND' END,
       CASE WHEN g = 1 THEN 2500000 ELSE 100000 + g * 1000 END,
       CASE WHEN g = 1 THEN 420000 ELSE 5000 + g * 100 END,
       CASE WHEN g = 1 THEN 18000 ELSE 1000 + g * 10 END,
       DATE '2033-10-31', 8.00, 'IN_PROGRESS', now(), now()
FROM generate_series(1, 1500) AS g
JOIN ranked_users u ON u.user_no = (g - 1) % 1000;

INSERT INTO goal_milestones (id, goal_id, title, target_amount, target_date, is_achieved, achieved_at)
SELECT CASE WHEN g = 1 THEN 'mls_01h7x8a9b2c3d4e5f6g7h8j9k0' ELSE 'mls_gen_' || lpad(g::text, 5, '0') END,
       CASE WHEN ((g - 1) / 3 + 1) = 1 THEN 'gol_01h7x8a9b2c3d4e5f6g7h8j9k0' ELSE 'gol_gen_' || lpad((((g - 1) / 3 + 1)::int)::text, 4, '0') END,
       CASE WHEN g = 1 THEN 'Quarter Milestone (25%)' ELSE 'Milestone ' || g END,
       CASE WHEN g = 1 THEN 400000 ELSE 10000 + g * 1000 END,
       DATE '2028-06-30' + g,
       FALSE, NULL
FROM generate_series(1, 4500) AS g;

WITH ranked_users AS (
  SELECT id, row_number() OVER (ORDER BY CASE WHEN id = 'usr_01h7x8a9b2c3d4e5f6g7h8j9k0' THEN 0 ELSE 1 END, id) - 1 AS user_no
  FROM users
)
INSERT INTO ml_profiles (id, user_id, behavioural_score, impulse_spending_index, average_monthly_burn, predicted_savings_rate, category_spending_distribution, weekend_vs_weekday_ratio, feature_weights, last_computed_at)
SELECT CASE WHEN u.user_no = 0 THEN 'mlp_01h7x8a9b2c3d4e5f6g7h8j9k0' ELSE 'mlp_gen_' || lpad((u.user_no + 1)::text, 4, '0') END,
       u.id, 70 + (u.user_no % 3000) / 100.0, 0.1 + (u.user_no % 7000) / 10000.0,
       20000 + u.user_no * 10, 15 + (u.user_no % 3000) / 100.0,
       '{"Food & Dining":0.28,"Shopping":0.18}'::jsonb,
       '{"weekend_ratio":1.2,"weekday_average":900,"weekend_average":1080}'::jsonb,
       '{"savings_weight":0.35,"impulse_weight":0.35,"budget_adherence":0.30}'::jsonb,
       now() - u.user_no * INTERVAL '1 minute'
FROM ranked_users u;

ANALYZE;
