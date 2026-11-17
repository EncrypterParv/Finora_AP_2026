-- Finora PostgreSQL 15+ schema, based on the SQLAlchemy models and dbms/01_normalization.md §6.
-- Run with: psql -v ON_ERROR_STOP=1 -f dbms/03_schema.sql
DROP SCHEMA IF EXISTS finora CASCADE;
CREATE SCHEMA finora;
SET search_path TO finora;

CREATE TABLE users (
    id VARCHAR(36) NOT NULL,
    email VARCHAR(255) NOT NULL,
    hashed_password VARCHAR(255) NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    currency VARCHAR(10) NOT NULL DEFAULT 'INR',
    preferences JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_users PRIMARY KEY (id),
    CONSTRAINT uq_users_email UNIQUE (email)
);

CREATE TABLE categories (
    id VARCHAR(36) NOT NULL,
    name VARCHAR(100) NOT NULL,
    slug VARCHAR(100) NOT NULL,
    icon VARCHAR(50) NOT NULL DEFAULT 'Tag',
    color_hex VARCHAR(20) NOT NULL DEFAULT '#6366F1',
    is_system BOOLEAN NOT NULL DEFAULT TRUE,
    parent_id VARCHAR(36),
    CONSTRAINT pk_categories PRIMARY KEY (id),
    CONSTRAINT uq_categories_name UNIQUE (name),
    CONSTRAINT uq_categories_slug UNIQUE (slug),
    CONSTRAINT fk_categories_parent_id FOREIGN KEY (parent_id) REFERENCES categories (id) ON DELETE SET NULL,
    -- CHECK: the application stores category colors as six-digit CSS hex colors.
    CONSTRAINT chk_categories_color_hex CHECK (color_hex ~ '^#[0-9A-Fa-f]{6}$')
);
-- FK categories.parent_id links a subcategory to its parent; deleting a parent clears the link.

CREATE TABLE merchants (
    id VARCHAR(36) NOT NULL,
    clean_name VARCHAR(150) NOT NULL,
    raw_patterns JSONB NOT NULL DEFAULT '[]'::jsonb,
    default_category_id VARCHAR(36),
    logo_url VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_merchants PRIMARY KEY (id),
    CONSTRAINT uq_merchants_clean_name UNIQUE (clean_name),
    CONSTRAINT fk_merchants_default_category_id FOREIGN KEY (default_category_id) REFERENCES categories (id) ON DELETE SET NULL
);
-- FK merchants.default_category_id supplies a category suggestion and remains nullable if that category is deleted.

CREATE TABLE bank_accounts (
    id VARCHAR(36) NOT NULL,
    user_id VARCHAR(36) NOT NULL,
    institution_name VARCHAR(100) NOT NULL,
    account_number_masked VARCHAR(50) NOT NULL,
    account_type VARCHAR(50) NOT NULL DEFAULT 'SAVINGS',
    current_balance NUMERIC(14, 2) NOT NULL DEFAULT 0.00,
    currency VARCHAR(10) NOT NULL DEFAULT 'INR',
    adapter_type VARCHAR(50) NOT NULL DEFAULT 'HSBC_DEMO',
    last_synced_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_bank_accounts PRIMARY KEY (id),
    CONSTRAINT fk_bank_accounts_user_id FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    -- This unique pair is required as the referenced key for the recommended transaction ownership FK.
    CONSTRAINT uq_bank_accounts_id_user_id UNIQUE (id, user_id),
    -- CHECK: these are the account types documented by the model.
    CONSTRAINT chk_bank_accounts_account_type CHECK (account_type IN ('SAVINGS', 'CHECKING', 'CREDIT'))
);
-- FK bank_accounts.user_id makes accounts user-owned and removes them with their user.

CREATE TABLE transactions (
    id VARCHAR(36) NOT NULL,
    user_id VARCHAR(36) NOT NULL,
    account_id VARCHAR(36) NOT NULL,
    category_id VARCHAR(36),
    merchant_id VARCHAR(36),
    occurred_at TIMESTAMPTZ NOT NULL,
    amount NUMERIC(14, 2) NOT NULL,
    currency VARCHAR(10) NOT NULL DEFAULT 'INR',
    transaction_type VARCHAR(20) NOT NULL DEFAULT 'DEBIT',
    raw_description VARCHAR(500) NOT NULL,
    balance_before NUMERIC(14, 2),
    balance_after NUMERIC(14, 2),
    reference_id VARCHAR(100) NOT NULL,
    source VARCHAR(50) NOT NULL DEFAULT 'BANK_API',
    dedup_hash VARCHAR(64) NOT NULL,
    tax_info JSONB,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_transactions PRIMARY KEY (id),
    CONSTRAINT uq_transactions_dedup_hash UNIQUE (dedup_hash),
    CONSTRAINT fk_transactions_user_id FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_transactions_account_id FOREIGN KEY (account_id) REFERENCES bank_accounts (id) ON DELETE CASCADE,
    CONSTRAINT fk_transactions_category_id FOREIGN KEY (category_id) REFERENCES categories (id) ON DELETE SET NULL,
    CONSTRAINT fk_transactions_merchant_id FOREIGN KEY (merchant_id) REFERENCES merchants (id) ON DELETE SET NULL,
    CONSTRAINT fk_transactions_account_user FOREIGN KEY (account_id, user_id) REFERENCES bank_accounts (id, user_id) ON DELETE CASCADE,
    -- CHECK: canonical transaction schemas require a positive absolute amount.
    CONSTRAINT chk_transactions_amount_positive CHECK (amount > 0),
    -- CHECK: values follow the canonical transaction enum used by the schemas.
    CONSTRAINT chk_transactions_transaction_type CHECK (transaction_type IN ('DEBIT', 'CREDIT', 'TRANSFER')),
    -- CHECK: values follow the canonical transaction source enum used by the schemas.
    CONSTRAINT chk_transactions_source CHECK (source IN ('BANK_API', 'CSV', 'XLSX', 'PDF', 'MANUAL'))
);
-- FK transactions.user_id preserves the directly modeled user reference and cascades with the user.
-- FK transactions.account_id references the account that owns this transaction; account deletion cascades.
-- FK transactions.category_id labels a transaction and is cleared if the category is deleted.
-- FK transactions.merchant_id labels a transaction and is cleared if the merchant is deleted.
-- FK transactions(account_id, user_id) enforces that the transaction user owns its referenced account.

CREATE TABLE budgets (
    id VARCHAR(36) NOT NULL,
    user_id VARCHAR(36) NOT NULL,
    name VARCHAR(100) NOT NULL,
    period VARCHAR(20) NOT NULL DEFAULT 'MONTHLY',
    total_limit NUMERIC(14, 2) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_budgets PRIMARY KEY (id),
    CONSTRAINT fk_budgets_user_id FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    -- CHECK: the model documents the supported budget periods.
    CONSTRAINT chk_budgets_period CHECK (period IN ('MONTHLY', 'CUSTOM')),
    -- CHECK: budget limits are required to be positive by the app's request schema.
    CONSTRAINT chk_budgets_total_limit_positive CHECK (total_limit > 0),
    -- CHECK: a budget's end date cannot precede its start date.
    CONSTRAINT chk_budgets_date_order CHECK (end_date >= start_date)
);
-- FK budgets.user_id makes budgets user-owned and removes them with their user.

CREATE TABLE budget_categories (
    id VARCHAR(36) NOT NULL,
    budget_id VARCHAR(36) NOT NULL,
    category_id VARCHAR(36) NOT NULL,
    allocated_amount NUMERIC(14, 2) NOT NULL,
    alert_threshold_percentage NUMERIC(5, 2) NOT NULL DEFAULT 80.0,
    CONSTRAINT pk_budget_categories PRIMARY KEY (id),
    CONSTRAINT uq_budget_categories_budget_id_category_id UNIQUE (budget_id, category_id),
    CONSTRAINT fk_budget_categories_budget_id FOREIGN KEY (budget_id) REFERENCES budgets (id) ON DELETE CASCADE,
    CONSTRAINT fk_budget_categories_category_id FOREIGN KEY (category_id) REFERENCES categories (id) ON DELETE CASCADE,
    -- CHECK: app request validation requires each allocation to be positive.
    CONSTRAINT chk_budget_categories_allocated_amount_positive CHECK (allocated_amount > 0),
    -- CHECK: an alert threshold is a percentage and must be between 0 and 100 inclusive.
    CONSTRAINT chk_budget_categories_alert_threshold CHECK (alert_threshold_percentage BETWEEN 0 AND 100)
);
-- FK budget_categories.budget_id removes allocations when their budget is deleted.
-- FK budget_categories.category_id prevents allocations from referring to a deleted category.

CREATE TABLE financial_goals (
    id VARCHAR(36) NOT NULL,
    user_id VARCHAR(36) NOT NULL,
    title VARCHAR(150) NOT NULL,
    goal_type VARCHAR(50) NOT NULL DEFAULT 'EMERGENCY_FUND',
    target_amount NUMERIC(14, 2) NOT NULL,
    current_saved NUMERIC(14, 2) NOT NULL DEFAULT 0.00,
    monthly_contribution NUMERIC(14, 2) NOT NULL DEFAULT 0.00,
    target_date DATE NOT NULL,
    expected_annual_return_pct NUMERIC(5, 2) NOT NULL DEFAULT 8.00,
    status VARCHAR(20) NOT NULL DEFAULT 'IN_PROGRESS',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_financial_goals PRIMARY KEY (id),
    CONSTRAINT fk_financial_goals_user_id FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    -- CHECK: goal types are limited to the choices documented by the model and request schema.
    CONSTRAINT chk_financial_goals_goal_type CHECK (goal_type IN ('EMERGENCY_FUND', 'EDUCATION', 'CAR', 'HOUSE', 'TRAVEL', 'RETIREMENT', 'FIRE', 'CUSTOM')),
    -- CHECK: status values are limited to those documented by the model.
    CONSTRAINT chk_financial_goals_status CHECK (status IN ('IN_PROGRESS', 'COMPLETED', 'PAUSED')),
    -- CHECK: the app's goal request schema requires a positive target.
    CONSTRAINT chk_financial_goals_target_positive CHECK (target_amount > 0),
    -- CHECK: saved and contribution amounts are non-negative in the app's request schema.
    CONSTRAINT chk_financial_goals_progress_nonnegative CHECK (current_saved >= 0 AND monthly_contribution >= 0)
);
-- FK financial_goals.user_id makes goals user-owned and removes them with their user.

CREATE TABLE goal_milestones (
    id VARCHAR(36) NOT NULL,
    goal_id VARCHAR(36) NOT NULL,
    title VARCHAR(150) NOT NULL,
    target_amount NUMERIC(14, 2) NOT NULL,
    target_date DATE NOT NULL,
    is_achieved BOOLEAN NOT NULL DEFAULT FALSE,
    achieved_at TIMESTAMPTZ,
    CONSTRAINT pk_goal_milestones PRIMARY KEY (id),
    CONSTRAINT fk_goal_milestones_goal_id FOREIGN KEY (goal_id) REFERENCES financial_goals (id) ON DELETE CASCADE,
    -- CHECK: a milestone target amount must be positive to represent a meaningful savings milestone.
    CONSTRAINT chk_goal_milestones_target_positive CHECK (target_amount > 0)
);
-- FK goal_milestones.goal_id removes milestones with their parent goal.

CREATE TABLE ml_profiles (
    id VARCHAR(36) NOT NULL,
    user_id VARCHAR(36) NOT NULL,
    behavioural_score NUMERIC(5, 2) NOT NULL DEFAULT 75.0,
    impulse_spending_index NUMERIC(5, 4) NOT NULL DEFAULT 0.20,
    average_monthly_burn NUMERIC(14, 2) NOT NULL DEFAULT 0.00,
    predicted_savings_rate NUMERIC(5, 2) NOT NULL DEFAULT 20.0,
    category_spending_distribution JSONB NOT NULL DEFAULT '{}'::jsonb,
    weekend_vs_weekday_ratio JSONB NOT NULL DEFAULT '{}'::jsonb,
    feature_weights JSONB NOT NULL DEFAULT '{}'::jsonb,
    last_computed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_ml_profiles PRIMARY KEY (id),
    CONSTRAINT fk_ml_profiles_user_id FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    -- CHECK: behavioural scores are percentages on a 0–100 scale.
    CONSTRAINT chk_ml_profiles_behavioural_score CHECK (behavioural_score BETWEEN 0 AND 100),
    -- CHECK: impulse spending index is a normalized ratio on a 0–1 scale.
    CONSTRAINT chk_ml_profiles_impulse_index CHECK (impulse_spending_index BETWEEN 0 AND 1),
    -- CHECK: average monthly burn is a non-negative spending total.
    CONSTRAINT chk_ml_profiles_average_monthly_burn CHECK (average_monthly_burn >= 0)
);
-- FK ml_profiles.user_id keeps computed profiles attached to a user and removes them with that user.
