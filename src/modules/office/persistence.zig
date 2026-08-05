const std = @import("std");
const core = @import("core");
const db_mod = @import("../db_postgres.zig");
const model = @import("model.zig");

fn parseWorkMoment(allocator: std.mem.Allocator, row: []const []const u8) !model.WorkMoment {
    return model.WorkMoment{
        .id = try allocator.dupe(u8, row[0]),
        .user_id = try allocator.dupe(u8, row[1]),
        .face_url = try allocator.dupe(u8, row[2]),
        .nickname = try allocator.dupe(u8, row[3]),
        .content = try allocator.dupe(u8, row[4]),
        .metas = try allocator.dupe(u8, row[5]),
        .permission = try allocator.dupe(u8, row[6]),
        .at_user_ids = try allocator.dupe(u8, row[7]),
        .permission_user_ids = try allocator.dupe(u8, row[8]),
        .like_users = try allocator.dupe(u8, row[9]),
        .comments = try allocator.dupe(u8, row[10]),
        .create_time = try std.fmt.parseInt(i64, row[11], 10),
    };
}

fn freeResult(allocator: std.mem.Allocator, result: db_mod.QueryResult) void {
    for (result.rows) |row| {
        for (row) |cell| allocator.free(cell);
        _ = allocator.free(row);
    }
    _ = allocator.free(result.rows);
}

pub const OfficePersistence = struct {
    allocator: std.mem.Allocator,
    db: *db_mod.PostgresClient,

    pub fn init(allocator: std.mem.Allocator, db: *db_mod.PostgresClient) OfficePersistence {
        return .{ .allocator = allocator, .db = db };
    }

    pub fn deinit(self: *OfficePersistence) void {
        _ = self;
    }

    pub fn create(self: *OfficePersistence, input: model.WorkMomentCreateInput) !model.WorkMoment {
        const metas = input.metas orelse "[]";
        const permission = input.permission orelse "0";
        const at_users = input.at_user_ids orelse "[]";
        const perm_users = input.permission_user_ids orelse "[]";

        const sql = "INSERT INTO work_moments (user_id, content, metas, permission, at_user_ids, permission_user_ids) " ++
            "VALUES ($1, $2, $3::jsonb, $4::jsonb, $5::jsonb, $6::jsonb) " ++
            "RETURNING id::text, user_id, content, metas::text, permission::text, at_user_ids::text, permission_user_ids::text, like_users::text, comments::text, EXTRACT(EPOCH FROM create_time)::bigint";
        const params = &[_]db_mod.QueryParam{
            .{ .string = input.user_id },
            .{ .string = input.content },
            .{ .string = metas },
            .{ .string = permission },
            .{ .string = at_users },
            .{ .string = perm_users },
        };
        const result = try self.db.queryParams(sql, params);
        defer freeResult(self.allocator, result);

        const row = result.rows[0];
        // create RETURNING has no JOIN columns (face_url/nickname) — parse inline
        return model.WorkMoment{
            .id = try self.allocator.dupe(u8, row[0]),
            .user_id = try self.allocator.dupe(u8, row[1]),
            .face_url = "",
            .nickname = "",
            .content = try self.allocator.dupe(u8, row[2]),
            .metas = try self.allocator.dupe(u8, row[3]),
            .permission = try self.allocator.dupe(u8, row[4]),
            .at_user_ids = try self.allocator.dupe(u8, row[5]),
            .permission_user_ids = try self.allocator.dupe(u8, row[6]),
            .like_users = try self.allocator.dupe(u8, row[7]),
            .comments = try self.allocator.dupe(u8, row[8]),
            .create_time = try std.fmt.parseInt(i64, row[9], 10),
        };
    }

    pub fn delete(self: *OfficePersistence, moment_id: []const u8, user_id: []const u8) bool {
        const sql = "DELETE FROM work_moments WHERE id = $1 AND user_id = $2";
        const params = &[_]db_mod.QueryParam{
            .{ .string = moment_id },
            .{ .string = user_id },
        };
        const affected = self.db.execParams(sql, params) catch return false;
        return affected > 0;
    }

    pub fn get(self: *OfficePersistence, moment_id: []const u8) !?model.WorkMoment {
        const sql = "SELECT wm.id::text, wm.user_id, COALESCE(u.face_url, '') as face_url, COALESCE(u.nickname, '') as nickname, " ++
            "wm.content, wm.metas::text, wm.permission::text, wm.at_user_ids::text, wm.permission_user_ids::text, wm.like_users::text, wm.comments::text, EXTRACT(EPOCH FROM wm.create_time)::bigint " ++
            "FROM work_moments wm LEFT JOIN users u ON wm.user_id = u.user_id WHERE wm.id = $1";
        const params = &[_]db_mod.QueryParam{.{ .string = moment_id }};
        const result = self.db.queryParams(sql, params) catch return null;
        defer freeResult(self.allocator, result);

        if (result.row_count == 0) return null;
        return try parseWorkMoment(self.allocator, result.rows[0]);
    }

    pub fn getRecvList(self: *OfficePersistence, allocator: std.mem.Allocator, user_id: []const u8, page: u32, size: u32) ![]model.WorkMoment {
        const offset = (if (page > 0) page - 1 else 0) * size;
        const perm_json = std.fmt.allocPrint(self.allocator, "[\"{s}\"]", .{user_id}) catch return &[_]model.WorkMoment{};
        defer self.allocator.free(perm_json);
        const sql = "SELECT wm.id::text, wm.user_id, COALESCE(u.face_url, '') as face_url, COALESCE(u.nickname, '') as nickname, " ++
            "wm.content, wm.metas::text, wm.permission::text, wm.at_user_ids::text, wm.permission_user_ids::text, wm.like_users::text, wm.comments::text, EXTRACT(EPOCH FROM wm.create_time)::bigint " ++
            "FROM work_moments wm LEFT JOIN users u ON wm.user_id = u.user_id " ++
            "WHERE wm.user_id IN (SELECT friend_user_id FROM friends WHERE owner_user_id = $1) " ++
            "AND (COALESCE(NULLIF(wm.permission::text, '{}'), '0') = '0' " ++
            "OR (COALESCE(NULLIF(wm.permission::text, '{}'), '0') = '2' AND wm.permission_user_ids @> $2::jsonb) " ++
            "OR (COALESCE(NULLIF(wm.permission::text, '{}'), '0') = '3' AND NOT (wm.permission_user_ids @> $3::jsonb))) " ++
            "ORDER BY wm.create_time DESC LIMIT $4 OFFSET $5";
        const params = &[_]db_mod.QueryParam{
            .{ .string = user_id },
            .{ .string = perm_json },
            .{ .string = perm_json },
            .{ .int = size },
            .{ .int = offset },
        };
        const result = self.db.queryParams(sql, params) catch return &[_]model.WorkMoment{};
        defer freeResult(self.allocator, result);

        var list = std.ArrayList(model.WorkMoment).empty;
        for (result.rows) |row| {
            try list.append(allocator, try parseWorkMoment(self.allocator, row));
        }
        return list.toOwnedSlice(allocator);
    }

    pub fn getRecvCount(self: *OfficePersistence, user_id: []const u8) !u32 {
        const perm_json = std.fmt.allocPrint(self.allocator, "[\"{s}\"]", .{user_id}) catch return 0;
        defer self.allocator.free(perm_json);
        const sql = "SELECT COUNT(*) FROM work_moments wm " ++
            "WHERE wm.user_id IN (SELECT friend_user_id FROM friends WHERE owner_user_id = $1) " ++
            "AND (COALESCE(NULLIF(wm.permission::text, '{}'), '0') = '0' " ++
            "OR (COALESCE(NULLIF(wm.permission::text, '{}'), '0') = '2' AND wm.permission_user_ids @> $2::jsonb) " ++
            "OR (COALESCE(NULLIF(wm.permission::text, '{}'), '0') = '3' AND NOT (wm.permission_user_ids @> $3::jsonb)))";
        const params = &[_]db_mod.QueryParam{
            .{ .string = user_id },
            .{ .string = perm_json },
            .{ .string = perm_json },
        };
        const result = self.db.queryParams(sql, params) catch return 0;
        defer freeResult(self.allocator, result);
        if (result.row_count == 0) return 0;
        return std.fmt.parseInt(u32, result.rows[0][0], 10) catch 0;
    }

    pub fn getSendList(self: *OfficePersistence, allocator: std.mem.Allocator, target_user_id: []const u8, viewer_user_id: []const u8, page: u32, size: u32) ![]model.WorkMoment {
        const offset = (if (page > 0) page - 1 else 0) * size;
        const perm_json = std.fmt.allocPrint(self.allocator, "[\"{s}\"]", .{viewer_user_id}) catch return &[_]model.WorkMoment{};
        defer self.allocator.free(perm_json);
        const sql = "SELECT wm.id::text, wm.user_id, COALESCE(u.face_url, '') as face_url, COALESCE(u.nickname, '') as nickname, " ++
            "wm.content, wm.metas::text, wm.permission::text, wm.at_user_ids::text, wm.permission_user_ids::text, wm.like_users::text, wm.comments::text, EXTRACT(EPOCH FROM wm.create_time)::bigint " ++
            "FROM work_moments wm LEFT JOIN users u ON wm.user_id = u.user_id " ++
            "WHERE wm.user_id = $1 " ++
            "AND (wm.user_id = $2 OR COALESCE(NULLIF(wm.permission::text, '{}'), '0') = '0' " ++
            "OR (COALESCE(NULLIF(wm.permission::text, '{}'), '0') = '2' AND wm.permission_user_ids @> $3::jsonb) " ++
            "OR (COALESCE(NULLIF(wm.permission::text, '{}'), '0') = '3' AND NOT (wm.permission_user_ids @> $4::jsonb))) " ++
            "ORDER BY wm.create_time DESC LIMIT $5 OFFSET $6";
        const params = &[_]db_mod.QueryParam{
            .{ .string = target_user_id },
            .{ .string = viewer_user_id },
            .{ .string = perm_json },
            .{ .string = perm_json },
            .{ .int = size },
            .{ .int = offset },
        };
        const result = self.db.queryParams(sql, params) catch return &[_]model.WorkMoment{};
        defer freeResult(self.allocator, result);

        var list = std.ArrayList(model.WorkMoment).empty;
        for (result.rows) |row| {
            try list.append(allocator, try parseWorkMoment(self.allocator, row));
        }
        return list.toOwnedSlice(allocator);
    }

    pub fn like(self: *OfficePersistence, moment_id: []const u8, user_id: []const u8, nickname: []const u8, face_url: []const u8) bool {
        const now = core.unixNowSeconds();
        const like_json = std.fmt.allocPrint(self.allocator, "{{\"userID\":\"{s}\",\"nickname\":\"{s}\",\"faceURL\":\"{s}\",\"likeTime\":{d},\"createTime\":{d}}}", .{ user_id, nickname, face_url, now, now }) catch return false;
        defer self.allocator.free(like_json);

        const sql = "UPDATE work_moments SET like_users = COALESCE(like_users, '[]'::jsonb) || $1::jsonb " ++
            "WHERE id = $2 AND NOT (like_users @> jsonb_build_array(jsonb_build_object('userID', $3)))";
        const params = &[_]db_mod.QueryParam{
            .{ .string = like_json },
            .{ .string = moment_id },
            .{ .string = user_id },
        };
        const affected = self.db.execParams(sql, params) catch return false;
        return affected > 0;
    }

    pub fn unlike(self: *OfficePersistence, moment_id: []const u8, user_id: []const u8) bool {
        const sql = "UPDATE work_moments SET like_users = COALESCE((SELECT jsonb_agg(elem) FROM jsonb_array_elements(like_users) AS elem WHERE elem->>'userID' != $1), '[]'::jsonb) WHERE id = $2";
        const params = &[_]db_mod.QueryParam{ .{ .string = user_id }, .{ .string = moment_id } };
        const affected = self.db.execParams(sql, params) catch return false;
        return affected > 0;
    }

    pub fn addComment(self: *OfficePersistence, moment_id: []const u8, user_id: []const u8, nickname: []const u8, face_url: []const u8, reply_user_id: ?[]const u8, reply_nickname: ?[]const u8, reply_face_url: ?[]const u8, content: []const u8) bool {
        const now = core.unixNowSeconds();
        const ruid = reply_user_id orelse "";
        const rnick = reply_nickname orelse "";
        const rface = reply_face_url orelse "";

        const sql = "UPDATE work_moments SET comments = COALESCE(comments, '[]'::jsonb) || " ++
            "jsonb_build_object('commentID', gen_random_uuid()::text, 'userID', $1, 'nickname', $2, 'faceURL', $3, " ++
            "'replyUserID', $4, 'replyNickname', $5, 'replyFaceURL', $6, " ++
            "'content', $7, 'createTime', $8)::jsonb " ++
            "WHERE id = $9";
        const params = &[_]db_mod.QueryParam{
            .{ .string = user_id },
            .{ .string = nickname },
            .{ .string = face_url },
            .{ .string = ruid },
            .{ .string = rnick },
            .{ .string = rface },
            .{ .string = content },
            .{ .bigint = now },
            .{ .string = moment_id },
        };
        const affected = self.db.execParams(sql, params) catch return false;
        return affected > 0;
    }

    pub fn deleteComment(self: *OfficePersistence, moment_id: []const u8, comment_id: []const u8) bool {
        const sql = "UPDATE work_moments SET comments = COALESCE((SELECT jsonb_agg(elem) FROM jsonb_array_elements(comments) AS elem WHERE elem->>'commentID' != $1), '[]'::jsonb) WHERE id = $2";
        const params = &[_]db_mod.QueryParam{ .{ .string = comment_id }, .{ .string = moment_id } };
        const affected = self.db.execParams(sql, params) catch return false;
        return affected > 0;
    }

    pub fn getUnreadCount(self: *OfficePersistence, user_id: []const u8) u32 {
        const read_time = self.getUserReadTime(user_id, .count) catch 0;
        const at_json = std.fmt.allocPrint(self.allocator, "[\"{s}\"]", .{user_id}) catch return 0;
        defer self.allocator.free(at_json);

        const sql = "SELECT COUNT(*) FROM (" ++
            "SELECT 1 FROM work_moments wm, jsonb_array_elements(wm.like_users) AS lu " ++
            "WHERE wm.user_id = $1 AND (lu->>'createTime')::bigint > $2 " ++
            "UNION ALL " ++
            "SELECT 1 FROM work_moments wm, jsonb_array_elements(wm.comments) AS c " ++
            "WHERE wm.user_id = $3 AND (c->>'createTime')::bigint > $4 " ++
            "UNION ALL " ++
            "SELECT 1 FROM work_moments wm, jsonb_array_elements(wm.comments) AS c " ++
            "WHERE c->>'replyUserID' = $5 AND (c->>'createTime')::bigint > $6 " ++
            "UNION ALL " ++
            "SELECT 1 FROM work_moments wm " ++
            "WHERE wm.at_user_ids @> $7::jsonb AND EXTRACT(EPOCH FROM wm.create_time)::bigint > $8" ++
            ") t";
        const params = &[_]db_mod.QueryParam{
            .{ .string = user_id },
            .{ .bigint = read_time },
            .{ .string = user_id },
            .{ .bigint = read_time },
            .{ .string = user_id },
            .{ .bigint = read_time },
            .{ .string = at_json },
            .{ .bigint = read_time },
        };
        const result = self.db.queryParams(sql, params) catch return 0;
        defer freeResult(self.allocator, result);

        if (result.row_count == 0) return 0;
        return std.fmt.parseInt(u32, result.rows[0][0], 10) catch 0;
    }

    pub fn clearUnread(self: *OfficePersistence, user_id: []const u8, read_type: i32) void {
        const now = core.unixNowSeconds();

        const sql = "INSERT INTO user_read_times (user_id, count_time, list_time) VALUES ($1, $2, $3) " ++
            "ON CONFLICT (user_id) DO UPDATE SET " ++
            "count_time = CASE WHEN $4 = 1 OR $5 = 3 THEN EXCLUDED.count_time ELSE user_read_times.count_time END, " ++
            "list_time = CASE WHEN $6 = 2 OR $7 = 3 THEN EXCLUDED.list_time ELSE user_read_times.list_time END";
        const params = &[_]db_mod.QueryParam{
            .{ .string = user_id },
            .{ .bigint = now },
            .{ .bigint = now },
            .{ .int = read_type },
            .{ .int = read_type },
            .{ .int = read_type },
            .{ .int = read_type },
        };
        _ = self.db.execParams(sql, params) catch {};
    }

    pub fn findRelevantWorkMoments(self: *OfficePersistence, allocator: std.mem.Allocator, user_id: []const u8, page: u32, size: u32) ![]model.WorkMoment {
        const offset = (if (page > 0) page - 1 else 0) * size;
        const like_json = std.fmt.allocPrint(self.allocator, "[{{\"userID\":\"{s}\"}}]", .{user_id}) catch return &[_]model.WorkMoment{};
        defer self.allocator.free(like_json);
        const comment_json = std.fmt.allocPrint(self.allocator, "[{{\"replyUserID\":\"{s}\"}}]", .{user_id}) catch return &[_]model.WorkMoment{};
        defer self.allocator.free(comment_json);
        const at_json = std.fmt.allocPrint(self.allocator, "[\"{s}\"]", .{user_id}) catch return &[_]model.WorkMoment{};
        defer self.allocator.free(at_json);

        const sql = "SELECT wm.id::text, wm.user_id, COALESCE(u.face_url, '') as face_url, COALESCE(u.nickname, '') as nickname, " ++
            "wm.content, wm.metas::text, wm.permission::text, wm.at_user_ids::text, wm.permission_user_ids::text, wm.like_users::text, wm.comments::text, EXTRACT(EPOCH FROM wm.create_time)::bigint " ++
            "FROM work_moments wm LEFT JOIN users u ON wm.user_id = u.user_id " ++
            "WHERE wm.id IN (" ++
            "SELECT DISTINCT wm2.id FROM work_moments wm2 " ++
            "WHERE wm2.user_id = $1 " ++
            "OR wm2.like_users @> $2::jsonb " ++
            "OR wm2.comments @> $3::jsonb " ++
            "OR wm2.at_user_ids @> $4::jsonb" ++
            ") " ++
            "ORDER BY wm.create_time DESC LIMIT $5 OFFSET $6";
        const params = &[_]db_mod.QueryParam{
            .{ .string = user_id },
            .{ .string = like_json },
            .{ .string = comment_json },
            .{ .string = at_json },
            .{ .int = size },
            .{ .int = offset },
        };
        const result = self.db.queryParams(sql, params) catch return &[_]model.WorkMoment{};
        defer freeResult(self.allocator, result);

        var list = std.ArrayList(model.WorkMoment).empty;
        for (result.rows) |row| {
            try list.append(allocator, try parseWorkMoment(self.allocator, row));
        }
        return list.toOwnedSlice(allocator);
    }

    pub fn getUserReadTime(self: *OfficePersistence, user_id: []const u8, read_type: model.ReadType) !i64 {
        const sql = "SELECT count_time, list_time FROM user_read_times WHERE user_id = $1";
        const params = &[_]db_mod.QueryParam{.{ .string = user_id }};
        const result = self.db.queryParams(sql, params) catch return 0;
        defer freeResult(self.allocator, result);

        if (result.row_count == 0) return 0;
        const field = if (read_type == .count) result.rows[0][0] else result.rows[0][1];
        return std.fmt.parseInt(i64, field, 10) catch 0;
    }

    // ============================================
    // TAG METHODS
    // ============================================

    pub fn getTags(self: *OfficePersistence, allocator: std.mem.Allocator, user_id: []const u8) ![]model.Tag {
        const sql = "SELECT id::text, user_id, tag_name, EXTRACT(EPOCH FROM create_time)::bigint FROM tags WHERE user_id = $1 ORDER BY create_time DESC";
        const params = &[_]db_mod.QueryParam{.{ .string = user_id }};
        const result = self.db.queryParams(sql, params) catch return &[_]model.Tag{};
        defer freeResult(self.allocator, result);

        var list = std.ArrayList(model.Tag).empty;
        for (result.rows) |row| {
            const tag_id = try allocator.dupe(u8, row[0]);
            var user_id_list = std.ArrayList([]const u8).empty;
            // Get members for this tag
            const member_sql = "SELECT user_id FROM tag_members WHERE tag_id = $1";
            const member_params = &[_]db_mod.QueryParam{.{ .string = tag_id }};
            const member_result = self.db.queryParams(member_sql, member_params) catch {
                allocator.free(tag_id);
                continue;
            };
            defer freeResult(self.allocator, member_result);
            for (member_result.rows) |mrow| {
                try user_id_list.append(allocator, try allocator.dupe(u8, mrow[0]));
            }
            try list.append(allocator, model.Tag{
                .id = tag_id,
                .user_id = try allocator.dupe(u8, row[1]),
                .tag_name = try allocator.dupe(u8, row[2]),
                .user_id_list = try user_id_list.toOwnedSlice(allocator),
                .create_time = std.fmt.parseInt(i64, row[3], 10) catch 0,
            });
        }
        return list.toOwnedSlice(allocator);
    }

    pub fn createTag(self: *OfficePersistence, input: model.TagCreateInput) !model.Tag {
        const sql = "INSERT INTO tags (user_id, tag_name) VALUES ($1, $2) RETURNING id::text, user_id, tag_name, EXTRACT(EPOCH FROM create_time)::bigint";
        const params = &[_]db_mod.QueryParam{ .{ .string = input.user_id }, .{ .string = input.tag_name } };
        const result = try self.db.queryParams(sql, params);
        defer freeResult(self.allocator, result);
        if (result.row_count == 0) return error.InsertFailed;
        const row = result.rows[0];
        const tag_id = try self.allocator.dupe(u8, row[0]);
        // Add members
        for (input.user_ids) |uid| {
            const m_sql = "INSERT INTO tag_members (tag_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING";
            const m_params = &[_]db_mod.QueryParam{ .{ .string = tag_id }, .{ .string = uid } };
            _ = self.db.execParams(m_sql, m_params) catch {};
        }
        var user_id_list = std.ArrayList([]const u8).empty;
        for (input.user_ids) |uid| {
            try user_id_list.append(self.allocator, try self.allocator.dupe(u8, uid));
        }
        return model.Tag{
            .id = tag_id,
            .user_id = try self.allocator.dupe(u8, row[1]),
            .tag_name = try self.allocator.dupe(u8, row[2]),
            .user_id_list = try user_id_list.toOwnedSlice(self.allocator),
            .create_time = std.fmt.parseInt(i64, row[3], 10) catch 0,
        };
    }

    pub fn deleteTag(self: *OfficePersistence, tag_id: []const u8) !bool {
        const sql = "DELETE FROM tags WHERE id = $1";
        const params = &[_]db_mod.QueryParam{.{ .string = tag_id }};
        const r = try self.db.execParams(sql, params);
        return r > 0;
    }

    pub fn updateTag(self: *OfficePersistence, input: model.TagUpdateInput) !bool {
        if (input.tag_name) |name| {
            const sql = "UPDATE tags SET tag_name = $1 WHERE id = $2";
            const params = &[_]db_mod.QueryParam{ .{ .string = name }, .{ .string = input.tag_id } };
            _ = try self.db.execParams(sql, params);
        }
        for (input.add_user_ids) |uid| {
            const sql = "INSERT INTO tag_members (tag_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING";
            const params = &[_]db_mod.QueryParam{ .{ .string = input.tag_id }, .{ .string = uid } };
            _ = self.db.execParams(sql, params) catch {};
        }
        for (input.del_user_ids) |uid| {
            const sql = "DELETE FROM tag_members WHERE tag_id = $1 AND user_id = $2";
            const params = &[_]db_mod.QueryParam{ .{ .string = input.tag_id }, .{ .string = uid } };
            _ = self.db.execParams(sql, params) catch {};
        }
        return true;
    }

    // ============================================
    // COLLECT / FAVORITE METHODS
    // ============================================

    pub fn addCollect(self: *OfficePersistence, user_id: []const u8, collect_type: []const u8, content: []const u8, uuid: []const u8) !model.Collect {
        const sql = "INSERT INTO collects (user_id, collect_type, content, uuid) VALUES ($1, $2, $3, $4) RETURNING id::text, user_id, collect_type, content, uuid, EXTRACT(EPOCH FROM create_time)::bigint";
        const params = &[_]db_mod.QueryParam{ .{ .string = user_id }, .{ .string = collect_type }, .{ .string = content }, .{ .string = uuid } };
        const result = try self.db.queryParams(sql, params);
        defer freeResult(self.allocator, result);
        if (result.row_count == 0) return error.InsertFailed;
        const row = result.rows[0];
        return model.Collect{
            .id = try self.allocator.dupe(u8, row[0]),
            .user_id = try self.allocator.dupe(u8, row[1]),
            .collect_type = try self.allocator.dupe(u8, row[2]),
            .content = try self.allocator.dupe(u8, row[3]),
            .uuid = try self.allocator.dupe(u8, row[4]),
            .create_time = std.fmt.parseInt(i64, row[5], 10) catch 0,
        };
    }

    pub fn removeCollect(self: *OfficePersistence, user_id: []const u8, collect_ids: []const []const u8) !bool {
        for (collect_ids) |cid| {
            const sql = "DELETE FROM collects WHERE id = $1 AND user_id = $2";
            const params = &[_]db_mod.QueryParam{ .{ .string = cid }, .{ .string = user_id } };
            _ = self.db.execParams(sql, params) catch {};
        }
        return true;
    }

    pub fn getCollects(self: *OfficePersistence, allocator: std.mem.Allocator, user_id: []const u8, collect_types: []const []const u8, page: u32, size: u32) ![]model.Collect {
        const offset = (if (page > 0) page - 1 else 0) * size;
        var sql: []const u8 = undefined;
        var type_filter: []const u8 = "";
        var params_list = std.ArrayList(db_mod.QueryParam).empty;
        defer params_list.deinit(self.allocator);
        try params_list.append(self.allocator, .{ .string = user_id });

        if (collect_types.len > 0) {
            var type_builder = std.ArrayList(u8).empty;
            defer type_builder.deinit(self.allocator);
            for (collect_types, 0..) |t, i| {
                try params_list.append(self.allocator, .{ .string = t });
                if (i > 0) try type_builder.appendSlice(self.allocator, ", ");
                var idx_buf: [16]u8 = undefined;
                const idx_str = try std.fmt.bufPrint(&idx_buf, "${d}", .{params_list.items.len});
                try type_builder.appendSlice(self.allocator, idx_str);
            }
            const inner = try type_builder.toOwnedSlice(self.allocator);
            defer self.allocator.free(inner);
            type_filter = try std.fmt.allocPrint(self.allocator, " AND collect_type IN ({s})", .{inner});
        }
        defer if (type_filter.len > 0) self.allocator.free(type_filter);

        sql = try std.fmt.allocPrint(self.allocator, "SELECT id::text, user_id, collect_type, content, uuid, EXTRACT(EPOCH FROM create_time)::bigint FROM collects WHERE user_id = $1{s} ORDER BY create_time DESC LIMIT ${d} OFFSET ${d}", .{ type_filter, params_list.items.len + 1, params_list.items.len + 2 });
        defer self.allocator.free(sql);
        try params_list.append(self.allocator, .{ .int = size });
        try params_list.append(self.allocator, .{ .int = offset });

        const result = self.db.queryParams(sql, params_list.items) catch return &[_]model.Collect{};
        defer freeResult(self.allocator, result);

        var list = std.ArrayList(model.Collect).empty;
        for (result.rows) |row| {
            try list.append(allocator, model.Collect{
                .id = try allocator.dupe(u8, row[0]),
                .user_id = try allocator.dupe(u8, row[1]),
                .collect_type = try allocator.dupe(u8, row[2]),
                .content = try allocator.dupe(u8, row[3]),
                .uuid = try allocator.dupe(u8, row[4]),
                .create_time = std.fmt.parseInt(i64, row[5], 10) catch 0,
            });
        }
        return list.toOwnedSlice(allocator);
    }

    // ============================================
    // CLIENT CONFIG METHODS
    // ============================================

    pub fn getClientConfig(self: *OfficePersistence) !model.ClientConfig {
        const sql = "SELECT key, value, COALESCE(EXTRACT(EPOCH FROM update_time)::bigint, 0) FROM client_configs WHERE key = 'client_config'";
        const result = self.db.query(sql) catch return model.ClientConfig{
            .key = "client_config",
            .value = "{}",
            .update_time = 0,
        };
        defer freeResult(self.allocator, result);
        if (result.row_count == 0) return model.ClientConfig{
            .key = "client_config",
            .value = "{}",
            .update_time = 0,
        };
        const row = result.rows[0];
        return model.ClientConfig{
            .key = try self.allocator.dupe(u8, row[0]),
            .value = try self.allocator.dupe(u8, row[1]),
            .update_time = std.fmt.parseInt(i64, row[2], 10) catch 0,
        };
    }
};
