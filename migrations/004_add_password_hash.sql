-- Add password_hash column for Vben5 Admin authentication
ALTER TABLE users ADD COLUMN IF NOT EXISTS password_hash TEXT NOT NULL DEFAULT '';

-- Index for password lookups (if needed)
CREATE INDEX IF NOT EXISTS idx_users_password_hash ON users(password_hash);

-- Migration: Create password_hash for existing users
-- For existing users without a password, set a default hash that won't validate
-- Users will need to reset their password
UPDATE users SET password_hash = '$pbkdf2$10000$YTJiY2RiOGYtNDQzZi00YzQ2LWE3YjgtZTI5YmFkOWNlMDAw$invalid' WHERE password_hash = '';
