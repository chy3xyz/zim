-- Add permission-related columns to work_moments
ALTER TABLE work_moments ADD COLUMN IF NOT EXISTS at_user_ids JSONB DEFAULT '[]'::jsonb;
ALTER TABLE work_moments ADD COLUMN IF NOT EXISTS permission_user_ids JSONB DEFAULT '[]'::jsonb;

-- Add user read times table for proper unread tracking
CREATE TABLE IF NOT EXISTS user_read_times (
    user_id VARCHAR(64) PRIMARY KEY,
    count_time BIGINT DEFAULT 0,
    list_time BIGINT DEFAULT 0
);
