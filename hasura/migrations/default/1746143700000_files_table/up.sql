-- =============================================================================
-- Migration: 0002_files_table
-- File metadata table for the StorageModule (Garage S3 integration).
-- Only applied when STORAGE_ENABLED=true, but safe to always include.
-- =============================================================================

CREATE TABLE public.files (
  id         UUID        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,

  -- S3 object info
  key        TEXT        NOT NULL UNIQUE,
  url        TEXT        NOT NULL,
  size       INTEGER     NOT NULL,
  mime_type  TEXT        NOT NULL,
  bucket     TEXT        NOT NULL,

  -- Audit fields (mandatory convention — see docs/adding-tables.md)
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by UUID        REFERENCES public.users(id) ON DELETE SET NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_by UUID        REFERENCES public.users(id) ON DELETE SET NULL,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID        REFERENCES public.users(id) ON DELETE SET NULL
);

COMMENT ON TABLE public.files IS 'File metadata for objects stored in Garage S3. Managed by StorageModule via Hasura Actions.';

-- Auto-update updated_at on every UPDATE
CREATE TRIGGER set_files_updated_at
  BEFORE UPDATE ON public.files
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();
