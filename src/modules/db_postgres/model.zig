pub const QueryParam = union(enum) {
    string: []const u8,
    int: i64,
    bigint: i64,
    smallint: i16,
    bool: bool,
    string_array: []const []const u8,
    null,
};

pub const QueryResult = struct {
    rows: []const []const []const u8,
    row_count: usize,
    affected_rows: usize,
};
