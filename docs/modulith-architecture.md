# Modulith Architecture - ZIM Server

## Design Principles

1. **Single Process, Modular Design** - All modules in one executable, separated by domain
2. **High Concurrency** - Zig's async/await with event-driven architecture
3. **Event-Driven Communication** - Modules communicate via EventBus, not direct calls
4. **Database-per-Module** - Each module owns its data operations
5. **Queue-Based Messaging** - PGMQ for async message delivery

## Module Structure

```
┌─────────────────────────────────────────────────────────────┐
│                     Gateway (HTTP/WS)                       │
│              Routes requests to services                     │
└─────────────────────┬─────────────────────────────────────┘
                      │
┌─────────────────────▼─────────────────────────────────────┐
│                      EventBus                               │
│         Publish/Subscribe for module communication          │
└──────┬──────────┬──────────┬──────────┬─────────────────┘
       │          │          │          │
┌──────▼──┐ ┌─────▼──┐ ┌────▼────┐ ┌───▼────┐
│  User   │ │Conversation│ │ Message │ │ Group  │
│ Service │ │  Service  │ │ Service │ │Service │
└────┬───┘ └────┬────┘ └───┬─────┘ └───┬────┘
     │           │           │           │
┌────▼───────────▼───────────▼───────────▼────┐
│              Database Layer (PostgreSQL)        │
│   Users │ Conversations │ Messages │ Groups    │
│   Friends │ GroupMembers │ Conversations     │
└─────────────────────────────────────────────────┘
                         │
┌────────────────────────▼─────────────────────────┐
│              Queue Layer (PGMQ)                   │
│   offline_msgs │ user_events │ group_events      │
└──────────────────────────────────────────────────┘
```

## Event Types

```zig
pub const Event = struct {
    type: EventType,
    payload: []const u8,
    timestamp: i64,
};

pub const EventType = enum {
    user_created,
    user_updated,
    user_online,
    user_offline,
    message_sent,
    message_received,
    conversation_updated,
    friend_requested,
    friend_accepted,
    group_created,
    group_member_joined,
    group_member_left,
};
```

## Concurrency Model

- **Async I/O** - All database and queue operations are async
- **Worker Threads** - Connection pool with dedicated workers
- **Event-Driven** - Non-blocking event propagation
- **Backpressure** - Queue-based throttling

## Module Responsibilities

### User Service
- User CRUD operations
- Online/Offline status tracking
- User search and pagination
- Account validation

### Conversation Service
- Create/delete conversations
- Conversation settings (mute, pinned)
- Unread count tracking
- Seq number management

### Message Service
- Message sending (single/group)
- Message storage (JSONB)
- Message recall/delete
- Offline message queue

### Group Service
- Group CRUD
- Member management (invite, kick, role)
- Group settings

### Friend Service
- Friend requests
- Accept/decline workflow
- Blacklist management

## Database Schema (PostgreSQL)

See `migrations/001_initial.sql` for full schema.

Key optimizations:
- JSONB for flexible fields (profile, content, ex)
- UUID for all entity IDs
- Timestamps with timezone
- Proper indexes for common queries

## Queue Schema (PGMQ)

- `offline_msgs` - Pending messages for offline users
- `user_events` - User status changes
- `push_queue` - Push notification tasks
