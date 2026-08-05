-- ============================================
-- Chat Enterprise Features Migration
-- Work Moments, Organization, Departments
-- ============================================

-- ============================================
-- WORK MOMENTS (朋友圈/工作圈)
-- ============================================
CREATE TABLE IF NOT EXISTS work_moments (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             VARCHAR(64) NOT NULL,
    content             TEXT NOT NULL DEFAULT '',
    metas               JSONB DEFAULT '[]',
    permission          JSONB DEFAULT '{}',
    like_users          JSONB DEFAULT '[]',
    comments            JSONB DEFAULT '[]',
    create_time         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_work_moments_user ON work_moments(user_id);
CREATE INDEX IF NOT EXISTS idx_work_moments_create_time ON work_moments(create_time DESC);

-- ============================================
-- WORK MOMENT READS (阅读记录)
-- ============================================
CREATE TABLE IF NOT EXISTS workmoment_reads (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             VARCHAR(64) NOT NULL,
    work_moment_id      UUID NOT NULL REFERENCES work_moments(id) ON DELETE CASCADE,
    read_time           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, work_moment_id)
);
CREATE INDEX IF NOT EXISTS idx_workmoment_reads_user ON workmoment_reads(user_id);

-- ============================================
-- ORGANIZATIONS
-- ============================================
CREATE TABLE IF NOT EXISTS organizations (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    logo_url            VARCHAR(1024) NOT NULL DEFAULT '',
    name                VARCHAR(255) NOT NULL DEFAULT '',
    homepage            VARCHAR(1024) NOT NULL DEFAULT '',
    introduction        TEXT NOT NULL DEFAULT '',
    create_time         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- DEPARTMENTS
-- ============================================
CREATE TABLE IF NOT EXISTS departments (
    department_id       VARCHAR(128) PRIMARY KEY,
    name                VARCHAR(255) NOT NULL DEFAULT '',
    face_url            VARCHAR(1024) NOT NULL DEFAULT '',
    parent_department_id VARCHAR(128) NOT NULL DEFAULT '',
    order_val           INTEGER NOT NULL DEFAULT 0,
    create_time         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_departments_parent ON departments(parent_department_id);

-- ============================================
-- DEPARTMENT MEMBERS
-- ============================================
CREATE TABLE IF NOT EXISTS department_members (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             VARCHAR(64) NOT NULL,
    department_id       VARCHAR(128) NOT NULL REFERENCES departments(department_id) ON DELETE CASCADE,
    position            VARCHAR(255) NOT NULL DEFAULT '',
    station             VARCHAR(255) NOT NULL DEFAULT '',
    order_val           INTEGER NOT NULL DEFAULT 0,
    entry_time          TIMESTAMPTZ,
    termination_time    TIMESTAMPTZ,
    create_time         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, department_id)
);
CREATE INDEX IF NOT EXISTS idx_dept_members_dept ON department_members(department_id);
CREATE INDEX IF NOT EXISTS idx_dept_members_user ON department_members(user_id);

-- Insert default organization
INSERT INTO organizations (name, introduction) VALUES ('Default Organization', 'Default organization') ON CONFLICT DO NOTHING;

-- Insert default departments
INSERT INTO departments (department_id, name, parent_department_id, order_val) VALUES
('dept_root', 'Root', '', 0)
ON CONFLICT DO NOTHING;

-- Link existing users to root department
INSERT INTO department_members (user_id, department_id, position)
SELECT user_id, 'dept_root', '' FROM users
ON CONFLICT DO NOTHING;
