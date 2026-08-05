-- ============================================
-- Migration 009: Add updated_at + version tracking for incremental sync
-- ============================================

-- Add updated_at to tables missing it
ALTER TABLE friends ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE group_members ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE blacks ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- Backfill: set updated_at from existing timestamp columns
UPDATE friends SET updated_at = create_time WHERE updated_at = create_time;
UPDATE group_members SET updated_at = join_time WHERE updated_at = join_time;
UPDATE blacks SET updated_at = create_time WHERE updated_at = create_time;

-- Create trigger function to auto-update updated_at on row modification
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Attach triggers to auto-update updated_at on UPDATE
DROP TRIGGER IF EXISTS update_friends_updated_at ON friends;
CREATE TRIGGER update_friends_updated_at
    BEFORE UPDATE ON friends
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_group_members_updated_at ON group_members;
CREATE TRIGGER update_group_members_updated_at
    BEFORE UPDATE ON group_members
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_blacks_updated_at ON blacks;
CREATE TRIGGER update_blacks_updated_at
    BEFORE UPDATE ON blacks
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
