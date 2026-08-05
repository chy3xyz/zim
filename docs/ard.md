# Architecture Document - Zig IM Server (zim)

**Framework**: [zigmodu](https://github.com/chy3xyz/zigmodu) v0.16.0+
**Language**: Zig 0.16.0+

---

## 1. Design Philosophy

**Simplicity First**: Single Postgres instance with JSONB + PGMQ replaces MongoDB + Kafka cluster.

| Original Stack | Simplified Stack |
|----------------|------------------|
| MongoDB (sharded cluster) | PostgreSQL + JSONB |
| Kafka (multi-broker) | PGMQ (PostgreSQL Message Queue) |
| 10+ microservices | 3 core services |
| etcd (service discovery) | Redis (simpler) |

**Target**: 100,000+ concurrent users, <100ms message latency.

---

## 2. Target Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Flutter App                          │
└─────────────────────────┬───────────────────────────────────┘
                          │ WebSocket / REST
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                     Gateway Service                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐   │
│  │ HTTP REST   │  │  WebSocket  │  │  Session Mgmt   │   │
│  │   Server    │  │   Server    │  │   (in-memory)   │   │
│  └─────────────┘  └─────────────┘  └─────────────────┘   │
└─────────────────────────┬───────────────────────────────────┘
                          │ Direct DB calls (low latency)
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                    PostgreSQL 16+                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐   │
│  │  JSONB      │  │   PGMQ      │  │  Connection     │   │
│  │  Tables     │  │   Queues    │  │  Pool (PgBouncer)│   │
│  └─────────────┘  └─────────────┘  └─────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ PGMQ async workers
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                  Background Workers                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐   │
│  │ Push Notify │  │  Msg Sync   │  │  Typing/Status  │   │
│  │   Worker    │  │   Worker    │  │     Worker      │   │
│  └─────────────┘  └─────────────┘  └─────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. Service Breakdown

### 3.1 Gateway Service (Single Process)

Handles all external traffic:
- **HTTP REST API** - synchronous requests (send msg, get conversations)
- **WebSocket Server** - bidirectional real-time communication
- **Session Manager** - tracks online users with in-memory store + Redis fallback

```
src/gateway/
├── main.zig          # Entry point
├── http.zig          # REST API handlers ( Gin-equivalent in Zig )
├── websocket.zig     # WebSocket connection handler
├── session.zig       # Online user tracking
└── routes.zig        # Route definitions
```

### 3.2 Core Domain (No Separate RPC)

All business logic in same process, called directly:

```
src/core/
├── user.zig          # User management
├── friend.zig        # Friend relationships
├── group.zig         # Group chat logic
├── conversation.zig  # Conversation management
├── message.zig       # Message storage/retrieval
└── auth.zig          # Authentication/JWT
```

### 3.3 Background Workers (Same Binary, Different Tasks)

```
src/workers/
├── push.zig          # FCM/APNs push notifications
├── sync.zig          # Message history sync for offline users
├── presence.zig      # User presence updates
└── cleanup.zig       # Expired session cleanup
```

---

## 4. Database Schema (PostgreSQL + JSONB)

### 4.1 Users Table

```sql
CREATE TABLE users (
    user_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username     VARCHAR(64) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,  -- bcrypt/argon2
    email        VARCHAR(255) UNIQUE,
    phone        VARCHAR(32),
    profile      JSONB DEFAULT '{}',       -- avatar, bio, custom fields
    created_at   TIMESTAMPTZ DEFAULT NOW(),
    updated_at   TIMESTAMPTZ DEFAULT NOW(),
    is_online    BOOLEAN DEFAULT FALSE,
    last_seen_at TIMESTAMPTZ
);

CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_phone ON users(phone);
```

### 4.2 Conversations Table

```sql
CREATE TABLE conversations (
    conversation_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type             SMALLINT NOT NULL,  -- 1: single, 2: group, 3: supergroup
    name             VARCHAR(255),
    owner_id         UUID REFERENCES users(user_id),
    group_id         UUID,                -- for supergroup linking
    recv_msg_opt     SMALLINT DEFAULT 0,  -- 0: normal, 1: muted, 2: blocked
    is_pinned        BOOLEAN DEFAULT FALSE,
    is_private       BOOLEAN DEFAULT FALSE,
    ex               JSONB DEFAULT '{}',  -- extension data
    created_at       TIMESTAMPTZ DEFAULT NOW(),
    updated_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_conversations_owner ON conversations(owner_id);
CREATE INDEX idx_conversations_type ON conversations(type);
```

### 4.3 Messages Table (JSONB Content)

```sql
CREATE TABLE messages (
    msg_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(conversation_id),
    sender_id       UUID NOT NULL REFERENCES users(user_id),
    client_msg_id   UUID NOT NULL,        -- idempotency key from client
    msg_type        SMALLINT NOT NULL,    -- 1: text, 2: image, 3: audio, etc.
    content         JSONB NOT NULL,        -- flexible content storage
    ex              JSONB DEFAULT '{}',   -- extra: reactions, mentions
    is_recall       BOOLEAN DEFAULT FALSE,
    created_at       TIMESTAMPTZ DEFAULT NOW(),  -- indexed for pagination

    UNIQUE(conversation_id, client_msg_id)  -- deduplication
);

CREATE INDEX idx_messages_conversation_time ON messages(conversation_id, created_at DESC);
CREATE INDEX idx_messages_sender ON messages(sender_id);
CREATE INDEX idx_messages_content ON messages USING GIN(content);  -- JSONB search
```

### 4.4 Friends Table

```sql
CREATE TABLE friendships (
    user_id_1   UUID NOT NULL REFERENCES users(user_id),
    user_id_2   UUID NOT NULL REFERENCES users(user_id),
    status      SMALLINT NOT NULL,  -- 1: pending, 2: friends, 3: blocked
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW(),

    PRIMARY KEY (user_id_1, user_id_2),
    CHECK (user_id_1 < user_id_2)  -- canonical ordering
);

CREATE INDEX idx_friendships_user ON friendships(user_id_1, status);
CREATE INDEX idx_friendships_status ON friendships(status);
```

### 4.5 Groups Table

```sql
CREATE TABLE groups (
    group_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name           VARCHAR(255) NOT NULL,
    description    TEXT,
    owner_id       UUID NOT NULL REFERENCES users(user_id),
    member_count   INT DEFAULT 0,
    ex             JSONB DEFAULT '{}',
    created_at     TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE group_members (
    group_id    UUID NOT NULL REFERENCES groups(group_id),
    user_id     UUID NOT NULL REFERENCES users(user_id),
    role        SMALLINT DEFAULT 0,  -- 0: member, 1: admin, 2: owner
    joined_at   TIMESTAMPTZ DEFAULT NOW(),

    PRIMARY KEY (group_id, user_id)
);

CREATE INDEX idx_group_members_user ON group_members(user_id);
CREATE INDEX idx_groups_owner ON groups(owner_id);
```

---

## 5. PGMQ Message Queues

```sql
-- Enable PGMQ extension
CREATE EXTENSION IF NOT EXISTS pgmq;

-- Queue definitions (created at startup)
-- msg_push: push notifications
-- msg_sync: offline message sync
-- presence_updates: user online/offline events

-- Example message format in queue:
-- {
--   "queue": "msg_push",
--   "msg": {
--     "user_id": "uuid",
--     "title": "New message",
--     "body": "...",
--     "data": {...}
--   }
-- }
```

### Worker Polling Pattern

```zig
// Pseudo-code for worker loop
while (running) {
    const msg = pgmq.recv("msg_push", timeout = 5);
    if (msg) {
        // process push notification
        pgmq.delete("msg_push", msg.msg_id);
    }
}
```

---

## 6. Connection Pooling Strategy

```
App (Gateway)  ────  PgBouncer (Pooler)  ────  PostgreSQL

                  Transaction mode
                  Max connections: 100
                  Pool size: 20
```

- **PgBouncer** in transaction mode handles 100k users with ~20 actual PG connections
- Zig client uses `pg` crate with built-in connection pooling
- Prepared statements for frequently used queries

---

## 7. WebSocket Session Management

```zig
// In-memory session store (per Gateway instance)
// For multi-instance, use Redis pub/sub for session sync

pub const SessionStore = struct {
    mutex: std.Thread.Mutex,
    sessions: std.AutoHashMap(u64, Session),  // fd -> Session
    user_sessions: std.AutoHashMap([]const u8, std.ArrayList(u64)),  // user_id -> fds

    pub fn set(&self, fd: u64, user_id: []const u8) !void
    pub fn get_user_fds(&self, user_id: []const u8) []u64
    pub fn remove(&self, fd: u64) void
};
```

---

## 8. API Endpoints (Simplified)

### Auth
- `POST /auth/login` - Login, returns JWT
- `POST /auth/register` - Register new user
- `POST /auth/refresh` - Refresh token

### Conversations
- `GET /conversations` - List user's conversations
- `POST /conversations` - Create conversation
- `PUT /conversations/:id` - Update conversation settings

### Messages
- `GET /conversations/:id/messages` - Get messages (cursor pagination)
- `POST /conversations/:id/messages` - Send message
- `PUT /messages/:id/recall` - Recall message

### Users & Friends
- `GET /users/:id` - Get user profile
- `GET /friends` - List friends
- `POST /friends/:id` - Add friend
- `DELETE /friends/:id` - Remove friend

### Groups
- `GET /groups` - List user's groups
- `POST /groups` - Create group
- `POST /groups/:id/members` - Add member
- `DELETE /groups/:id/members/:uid` - Remove member

### WebSocket Events
- `Connect: ws://server/ws?token=xxx`
- `SendMsg`, `RecvMsg`, `Typing`, `ReadReceipt`, `Presence`

---

## 9. Performance Considerations

### 9.1 Message Write Path (Critical Path)

```
Client -> WebSocket -> Validate -> 
  INSERT message (JSONB) -> 
  PGMQ enqueue (for push/sync) ->
  WebSocket broadcast to online recipients ->
  Return to client
```

**Target**: <50ms p99

### 9.2 Indexing Strategy

- Messages: Composite index on `(conversation_id, created_at DESC)` for pagination
- JSONB GIN index only on content field for search, not all JSONB fields
- Use `EXPLAIN ANALYZE` to verify index usage

### 9.3 Horizontal Scaling Path

When single instance insufficient:

1. **Read replicas** - PgBouncer routes reads to replicas
2. **Multiple Gateway instances** - Redis pub/sub for session sync
3. **Sharding** - By user_id % N (when needed, complex)

For 100k users: single large instance (32+ cores, 128GB RAM) with PgBouncer should suffice.

---

## 10. File Structure

```
zim/
├── src/
│   ├── main.zig              # Entry point, starts gateway
│   ├── gateway/
│   │   ├── server.zig        # HTTP/WS server setup
│   │   ├── http.zig          # REST handlers
│   │   ├── websocket.zig     # WS connection handler
│   │   ├── session.zig       # Session management
│   │   └── routes.zig        # Route registration
│   ├── core/
│   │   ├── db.zig            # PostgreSQL client
│   │   ├── user.zig
│   │   ├── friend.zig
│   │   ├── group.zig
│   │   ├── conversation.zig
│   │   ├── message.zig
│   │   └── auth.zig
│   ├── queue/
│   │   ├── pgmq.zig          # PGMQ wrapper
│   │   └── workers.zig       # Background worker runner
│   ├── config.zig            # Configuration loading
│   └── util.zig
├── migrations/               # SQL migrations
│   └── 001_initial.sql
├── config/
│   └── config.yaml           # Runtime config
├── build.zig
└── AGENTS.md
```

---

## 11. Configuration

```yaml
# config/config.yaml
database:
  host: localhost
  port: 5432
  name: zim
  user: zim
  password: ""
  max_conns: 100
  min_conns: 10

queue:
  pgmq_queues:
    - msg_push
    - msg_sync
    - presence_updates
  poll_timeout_ms: 5000

gateway:
  host: 0.0.0.0
  http_port: 10000
  ws_port: 10001
  max_connections: 100000

jwt:
  secret: ""
  expiry_hours: 24
  refresh_expiry_days: 30

redis:
  host: localhost
  port: 6379
  password: ""
  db: 0
```

---

## 12. Comparison with Original Architecture

| Aspect | Original (Go) | Simplified (Zig) |
|--------|---------------|------------------|
| DB | MongoDB (sharded) | PostgreSQL 16+ (single) |
| Queue | Kafka (3+ brokers) | PGMQ (single PG) |
| Services | 10+ RPC services | 1 Gateway + Workers |
| Config | etcd | YAML file |
| Deployment | Kubernetes cluster | Single binary + PG |
| Scaling | Complex | Straightforward |
| 100k users | Requires expertise | Single instance OK |

**Complexity Reduction**: ~80% fewer moving parts.

---

## 13. Open Questions / Future Considerations

1. **Citus** - If single PG instance insufficient, Citus provides horizontal scaling
2. **Search** - Full-text search on messages could use PG `tsvector` or separate Elasticsearch
3. **Media** - For image/audio storage, consider S3-compatible (MinIO) for simplicity
4. **Push Notifications** - FCM/APNs integration needed for mobile

---

## 14. Development Phases

### Phase 1: Core Messaging
- Gateway with WebSocket + HTTP
- User auth with JWT
- 1:1 messaging with JSONB storage
- Basic session management

### Phase 2: Groups + Friends
- Group creation and management
- Friend relationships
- Group messages

### Phase 3: Async Processing
- PGMQ integration
- Push notification worker
- Offline message sync worker

### Phase 4: Production Hardening
- PgBouncer integration
- Connection pooling tuning
TY|### Phase 4: Production Hardening
YQ|- PgBouncer integration
QJ|- Connection pooling tuning
TY|- Monitoring/metrics

---

## 15. ZigModu Module Patterns

### 15.1 Module Declaration

```zig
// src/modules/user/module.zig
const std = @import("std");
const zigmodu = @import("zigmodu");

const UserModule = struct {
    pub const info = zigmodu.api.Module{
        .name = "user",
        .description = "User management - registration, auth, profile",
        .dependencies = &.{"db", "config"},
    };

    pub fn init() !void {
        std.log.info("UserModule initialized", .{});
    }

    pub fn deinit() void {
        std.log.info("UserModule cleaned up", .{});
    }
};
```

### 15.2 Application Bootstrap

```zig
// src/main.zig
const std = @import("std");
const zigmodu = @import("zigmodu");

const config_module = @import("modules/config/module.zig");
const db_module = @import("modules/db/module.zig");
const user_module = @import("modules/user/module.zig");
const message_module = @import("modules/message/module.zig");
const gateway_module = @import("modules/gateway/module.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var modules = try zigmodu.scanModules(allocator, .{
        config_module.ConfigModule,
        db_module.DatabaseModule,
        user_module.UserModule,
        message_module.MessageModule,
        gateway_module.GatewayModule,
    });
    defer modules.deinit();

    try zigmodu.validateModules(&modules);
    try zigmodu.startAll(&modules);
    defer zigmodu.stopAll(&modules);

    std.log.info("ZIM Server started!", .{});
    try zigmodu.waitForShutdown();
}
```

### 15.3 Event-Driven Communication

```zig
// Publish event
try self.event_bus.publish("message.sent", MessageSentEvent{
    .message = saved_msg,
});

// Subscribe to event
try self.event_bus.subscribe("message.sent", struct {
    fn handle(event: MessageSentEvent) void {
        session_manager.broadcast(event.conversation_id, event.message);
    }
}.handle);

### 15.4 Dependency Injection Container

```zig
// Register service
try container.register("database", &db);

// Get service
const db = container.get(*pg.Pool, "db").?;
