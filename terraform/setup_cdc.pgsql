-- 1) Create 'customer' table
CREATE TABLE IF NOT EXISTS public.customer (
  id              SERIAL PRIMARY KEY,
  full_name       TEXT NOT NULL,
  email           TEXT UNIQUE NOT NULL,
  phone           TEXT,
  classification  VARCHAR(10) CHECK (classification IN ('public','private')) NOT NULL,
  created_at      TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 2) Create replication user if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles
    WHERE rolname = 'debezium_user'
  ) THEN
    CREATE ROLE debezium_user WITH REPLICATION LOGIN PASSWORD 'StrongPassword123!';
  END IF;
END
$$;

-- 3) Grant SELECT on public.customer to debezium_user
GRANT SELECT ON public.customer TO debezium_user;

-- 4) Create publication if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication
    WHERE pubname = 'customer_pub'
  ) THEN
    CREATE PUBLICATION customer_pub FOR TABLE public.customer;
  END IF;
END
$$;
