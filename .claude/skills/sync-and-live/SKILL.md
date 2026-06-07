---
name: sync-and-live
description: >-
  Use when building offline-first data sync features or live invalidation in Pocopine apps — implementing sync streams, mutations, subscriptions, or multi-tenant filtered queries with local persistence.
---

## What This Is

Pocopine's **sync** layer coordinates snapshots, cursors, pulls, pushes, mutation deduplication, and conflict handling for offline-first client-side data stores (RFC 072). **Live invalidation** (via `pocopine-live`) adds a wake-up channel: the server publishes database-agnostic invalidation events and the browser refetches data it already knows how to load. Together they form the foundation for local-first SaaS apps.

## When to Use

- **Building offline-first features** — you need client-side rows to persist across refreshes, sync back to the server, and handle network gaps.
- **Multi-tenant filtered queries** — same table observed under many shapes (workspace filter, status filter). Use `#[query_resource]` + `pocopine-sync-query` instead of bare CRUD.
- **Optimistic mutations** — write to the local store first, render immediately, then confirm with the server; roll back on conflict.
- **Server-authoritative conflict handling** — the server rejects stale edits; the client refetches canonical data and surfaces conflicts to the UI.
- **Cross-browser / cross-device liveness** — SSE wake-ups notify waiting clients when mutations land, so tab B sees tab A's changes without polling.

## Key APIs / Syntax

### Server-side (RFC 072 / RFC 090)

**`#[query_resource]` macro** (on row struct):
```rust
#[query_resource(name = "issues", schema_version = 1, draft = IssueDraft)]
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Issue {
    pub id: String,
    #[query_param(required)]  pub workspace_id: String,  // tenant gate
    #[query_param]            pub status: String,        // optional filter
    pub title: String,
}
```
Emits: `Issue::query()` builder, `Issue::create(id, draft)` / `Issue::update(id, draft, version)` / `Issue::delete(id, version)` typed mutations, `issues::field::*` markers, `issues::resource(source_impl)` convenience.

**`Source` trait** (query-aware data source):
```rust
#[async_trait]
pub trait Source {
    type Row: Serialize + DeserializeOwned;
    type Draft;
    type Context;  // e.g. WorkspaceCtx — extracted once per request
    
    async fn list(&self, ctx, query: &Query<Self::Row>) -> SyncResult<Vec<Self::Row>>;
    async fn get(&self, ctx, id) -> SyncResult<Option<Self::Row>>;
    async fn create(&self, ctx, id, draft) -> SyncResult<Self::Row>;
    async fn update(&self, ctx, id, draft, expected_version) -> SyncResult<WriteResult>;
    async fn delete(&self, ctx, id, expected_version) -> SyncResult<DeleteResult>;
}
```
The `query` param lets you push filters down to SQL. Default impl ignores it (CRUD-like).

**Server registration**:
```rust
let sync = SyncServer::builder()
    .public_stream(issues::resource(IssueStore { db }))
    .events(Arc::new(live_backend()))  // for SSE wake-ups
    .build();

Server::new(router)
    .plugin(sync_server_plugin(sync))
    .plugin(live_plugin(live_backend()))
```

### Client-side

**`query_client_plugin()`** (app boot):
```rust
App::new()
    .plugin(query_client_plugin())
    .run();
```

**`#[query]` selector** (derived / memoized views):
```rust
#[query]
fn open_issue_count(client: QueryClient, ws: String) -> u32 {
    let view = client.observe(
        Issue::query()
            .eq(issues::field::workspace_id, ws)
            .any_of(issues::field::status, [Status::Open])?
            .build()
    );
    view.rows().len() as u32
}

// In component: view = open_issue_count::observe(&qc, "W1".to_string());
```

**`Query<Row>` DSL** (read subscriptions):
```rust
let handle = client.observe(
    Issue::query()
        .eq(issues::field::workspace_id, w1)
        .any_of(issues::field::status, [Status::Open, Status::InProgress])?
        .range(issues::field::created_at, last_week..now)
        .order_by("created_at", Order::Desc)
        .limit(50)
        .build()
);
for row in handle.rows() { render(row); }
```

Comparators: `.eq()` (any T), `.any_of()` / `.in_set()` (membership), `.range()` (ordered bounds: `a..b`, `a..=b`, `a..`, `..b`), `.contains()` (substring, auto-emitted for `String`).

**Typed mutations** (optimistic + push):
```rust
Issue::create(row_id, draft)
    .optimistic(|p| Issue { id, workspace_id: p.workspace_id, … })  // custom overlay
    .push(&qc)
    .await?;

Issue::update(row_id, draft, expected_version)
    .server_only()  // skip optimistic, render after confirm
    .push(&qc)
    .await?;
```

**Live invalidation** (SSE wake-up):
```rust
// Server publishes after mutation:
publish_posts_invalidation(pocopine::live::LiveOp::Upsert, post.id).await;

// Client refetches on invalidation:
LiveQuery::scoped(
    |s: &mut Self| &mut s.posts,
    || async { list_posts().await }
)
.query_tag("posts:list")
.open()?;
```

### Local storage (RFC 072 Phase D)

**`SyncLocalStore` trait**:
```rust
pub trait SyncLocalStore {
    fn hydrate_stream(&self, stream: &SyncStreamName)
        -> SyncLocalFuture<'_, LocalStreamSnapshot>;
    fn save_snapshot(&self, snapshot: LocalSnapshotBatch) -> SyncLocalFuture<'_, ()>;
    fn apply_changes(&self, changes: LocalChangeBatch) -> SyncLocalFuture<'_, ()>;
    fn enqueue_mutation(&self, stream, mutation) -> SyncLocalFuture<'_, ()>;
    fn pending_mutations(&self, stream) -> SyncLocalFuture<'_, Vec<ClientMutation>>;
}
```

**Built-in impls**:
- `MemoryLocalStore` — tests / ephemeral; no persistence.
- `SqliteLocalStore` (native + WASM/OPFS) — durable browser storage via `pocopine-sync-sqlite`.

## Examples

### 1. Server source with query-aware filtering (RFC 090)

From `/home/zempare-mambisi/RustProjects/pocopine/docs/sync.md`:
```rust
impl Source for IssueStore {
    type Row = Issue;
    type Draft = IssueDraft;
    type Context = WorkspaceCtx;
    
    async fn list(&self, ctx: WorkspaceCtx, query: &Query<Issue>)
        -> SyncResult<Vec<Issue>>
    {
        // `query.params()` exposes typed filters; push them to SQL.
        self.db.fetch_issues(ctx, query.params(), query.limit()).await
    }
    
    async fn create(&self, ctx: WorkspaceCtx, id: String, draft: IssueDraft)
        -> SyncResult<Issue>
    {
        self.db.insert_issue(&ctx, id, draft).await
    }
}
```

### 2. Client component with subscription + mutations

From `/home/zempare-mambisi/RustProjects/pocopine/docs/sync.md`:
```rust
#[handlers]
impl IssueList {
    pub fn on_mount(&mut self) {
        let qc = self.plugin::<Rc<QueryClient>>();
        Issue::query()
            .eq(issues::field::workspace_id, &self.workspace_id)
            .eq(issues::field::status, "open")
            .order_by(issues::field::created_at, Order::Desc)
            .limit(50)
            .bind::<Self, _>(&qc, |s: &mut Self| &mut s.rows);
    }
}

#[handlers]
impl IssueComposer {
    pub async fn create(&mut self) {
        let qc = self.plugin::<Rc<QueryClient>>();
        let draft = IssueDraft { workspace_id: w1, status: "open", title };
        match Issue::create(format!("iss_{}", uuid::Uuid::now_v7()), draft).push(&qc).await {
            Ok(_) => self.saving = false,
            Err(err) => { self.saving = false; self.error = err.to_string(); }
        }
    }
}
```

### 3. Live invalidation (RFC 071 wake-up)

From `/home/zempare-mambisi/RustProjects/pocopine/docs/live.md`:
```rust
#[pocopine::server(public)]
async fn create_post(draft: PostDraft) -> ServerResult<Post> {
    let post = insert_post(draft)?;
    if let Err(err) = live_backend()
        .publish(LiveInvalidation::new("posts", LiveOp::Upsert)
            .keys([post.id.clone()])
            .query_tags(["posts:list"])
            .into_draft()?
        ).await
    {
        tracing::warn!(target: "pocopine.log", error = %err);
    }
    Ok(post)
}
```

## Gotchas

- **`#[query_resource]` attribute order**: Must come BEFORE `#[derive(...)]` so it strips per-field attrs before serde sees them.
- **Required params as tenant gates**: Mark `#[query_param(required)]` on `workspace_id` or `tenant_id` to prevent accidental cross-tenant leaks (predicate fails if the query omits the filter).
- **Local store identity**: Browser client needs stable device ID + durable mutation IDs to dedupe replays after network reconnect. Use `SyncLocalStore` + `MutationIdGenerator`.
- **Live backend for multi-node deployments**: `MemoryEventBackend` is single-process only. Production with >1 server node MUST use `RedisEventBackend` or similar; mutations on Node 2 won't wake subscribers on Node 1 otherwise.
- **Cursor tokens**: Opaque server-issued. Clients must not parse them. If a cursor expires, the server returns `gap` and the client must re-snapshot.
- **Conflicts are explicit**: Server rejects stale `base_version` with `conflict`; the client pulls current data and lets UI decide how to proceed. No silent merge.
- **Stream guards run on every open/pull/push**: Access control is re-validated each call, not cached from `/open`.
- **Query params with unsupported predicates**: Frontend filters narrowing an authorized stream are fine; expanding beyond the server-registered stream is not.

## References

- **Core protocol**: `crates/pocopine-sync/` (RFC 072 §7: `/open`, `/pull`, `/push` endpoints; wire envelope; client `CollectionState`).
- **Query layer**: `crates/pocopine-sync-query/` (RFC 086 / RFC 090: `Query<Row>`, `Mutator`, `QueryClient`, predicate routing, `Source` trait).
- **Macros**: `crates/pocopine-sync-query-macros/` (`#[query_resource]`, `#[query]` decorators).
- **Storage backends**:
  - `crates/pocopine-sync-sqlite/` — native SQLite + WASM/OPFS (RFC 072 Phase D2).
  - `crates/pocopine-sync-indexdb/` — IndexedDB fallback (not primary query engine).
  - `crates/pocopine-sync/` — `MemoryLocalStore` for tests.
- **Live invalidation**: `crates/pocopine-live/` + `pocopine-events` (RFC 071: SSE topics, event backends, RefreshToken).
- **RFCs**:
  - RFC 072 — Offline sync protocol (core concepts, endpoints, conflict policy, phases A–G).
  - RFC 086 — `pocopine-sync-query` design (Query identity, Mutators, predicate evaluation, subscription registry).
  - RFC 090 — Merge CRUD into Query (unified `Source` trait, query-aware `list()`, typed writes).
  - RFC 071 — Event spine and live invalidation (topics, backends, event flow).
- **Docs**:
  - `docs/sync.md` — end-to-end tutorial (Steps 1–5: shared row, server source, client plugin, subscription, live wake-up).
  - `docs/sync-server.md` — `Source` / `SourceResource` / `MutationLog` contract reference.
  - `docs/sync-client.md` — `QueryClient` / `Query<Row>` DSL / typed writes reference.
  - `docs/sync-query-selector-mechanism.md` — `#[query]` read tracking, caching, invalidation (thread-local stack, `SelectorEntry`, listener routing).
  - `docs/live.md` — live invalidation tutorial + production backend strategy (Redis Cluster, NATS, Kafka scoping).
- **Examples**:
  - `examples/sync/` — memory-backed sync + live wake-up demo (`MemorySyncStream`, `/open`/`/pull`/`/push` flow, SSE).
  - `examples/live/` — simple live-invalidation flow (posts list with query-tag and collection topics).
