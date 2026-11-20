-- ============================================
-- RTC MEETING PERSISTENCE (Phase 84)
-- Meetings/participants survive process restarts; state was
-- previously in-memory only and was lost on restart.
-- ============================================

CREATE TABLE IF NOT EXISTS rtc_meetings (
    room_id      VARCHAR(64) PRIMARY KEY,
    host_user_id VARCHAR(64) NOT NULL,
    meeting_name VARCHAR(255) NOT NULL DEFAULT '',
    status       SMALLINT NOT NULL DEFAULT 1, -- 1=active, 2=ended
    layout       INT NOT NULL DEFAULT 0,
    record_id    VARCHAR(64),
    create_time  BIGINT NOT NULL DEFAULT 0,
    ended_at     BIGINT
);
CREATE INDEX IF NOT EXISTS idx_rtc_meetings_status ON rtc_meetings(status);

CREATE TABLE IF NOT EXISTS rtc_participants (
    id          BIGSERIAL PRIMARY KEY,
    room_id     VARCHAR(64) NOT NULL,
    user_id     VARCHAR(64) NOT NULL,
    nickname    VARCHAR(255) NOT NULL DEFAULT '',
    joined_at   BIGINT NOT NULL DEFAULT 0,
    is_muted    BOOLEAN NOT NULL DEFAULT FALSE,
    is_video_on BOOLEAN NOT NULL DEFAULT TRUE,
    UNIQUE (room_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_rtc_participants_room ON rtc_participants(room_id);
