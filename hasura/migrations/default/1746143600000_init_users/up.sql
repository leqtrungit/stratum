-- =============================================================================
-- Migration: 0001_init_users
-- Creates the minimal users table used as FK reference by all audit fields.
-- This is intentionally minimal — full auth (JWT, roles) comes in v0.2.
-- =============================================================================

CREATE TABLE public.users (
  id         UUID        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  email      TEXT        NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.users IS 'Minimal user identity table. Extended in v0.2 with JWT auth and roles.';

-- Auto-update trigger function (shared across all tables)
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
