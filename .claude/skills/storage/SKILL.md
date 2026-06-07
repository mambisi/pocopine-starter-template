---
name: storage
description: >-
  Use when integrating object storage (S3/GCS/Azure) with resumable uploads, presigned/multipart/sequential transfer strategies, or browser-based file uploads
---

# Pocopine Storage API

Pocopine-storage is a **storage-agnostic file upload and object storage extension** that abstracts over S3, GCS, Azure, and custom backends. It decouples browser UI from provider details through a unified protocol: resumable multipart/sequential uploads, presigned or proxy targets, server-mediated access control, and a provider-neutral `ObjectRef`.

## When to use

- Uploading files from the browser with resumable/retry semantics
- Direct-to-cloud uploads with presigned URLs (bypassing the server)
- Multipart uploads with concurrent parts
- Storing provider-neutral `ObjectRef` in your database
- Implementing private object access with per-request authorization
- Local development/testing without a cloud account
- Swapping backends (S3 → R2 or GCS) without changing application code

## Key concepts

### Storage-agnostic interface

The framework owns the **protocol** (session creation, offset tracking, part receipts, completion), while **backends own the provider details**. Your code never calls AWS SDK, GCS SDK, or Azure SDK directly; it calls `StorageBackend` trait methods, and adapters map those onto provider-specific operations.

```
Browser UploadClient → Server routes → StorageBackend trait → S3/GCS/Azure SDK
```

### The three layers

1. **StorageServer + routes** (host): Routes at `/__pocopine/storage/v1/{scopes,uploads}` handle authorization, key resolution, and orchestration. Install via `storage_server_plugin()`.

2. **StorageBackend trait** (host): Per-provider implementers (`S3StorageBackend`, `GcsStorageBackend`, `AzureStorageBackend`, `LocalFsStorageBackend`, `MemoryStorageBackend`). One backend per scope.

3. **StorageClient + UploadClient** (browser): Async/await friendly clients that handle file selection, progress reporting, resumable transfers, and retries.

### Scopes and policies

Scopes are application-facing upload categories (e.g., "avatars", "invoices"). Each scope has:

- **UploadPolicy**: server-authoritative limits (max size, allowed content types, resumability, strategy options)
- **UploadPolicyDescriptor**: safe client projection (no secrets, no provider details)
- **StorageKeyResolver**: app-owned logic that maps an authorized upload intent to a safe object key (e.g., `avatars/{user_id}/{object_id}`)
- **StorageScopeGuard**: auth check (who can write, read, delete)

### Upload strategies

| Strategy | Protocol | Use case |
|----------|----------|----------|
| `Sequential` | `PATCH` with `Upload-Offset` header | Default; one chunk in flight; resume from offset |
| `Multipart` | `PUT` with `Upload-Part: N` header | Concurrent parts; each part is independent; map to S3/GCS/Azure native assembly |
| `SingleRequest` | `PUT` (no offset) | Single-shot small files; no resumption |
| `Auto` | Server picks best advertised | Client requests it; server negotiates |

### ObjectRef (the durable value)

An `ObjectRef` is what you store in your database after upload succeeds:

```rust
pub struct ObjectRef {
    pub backend: String,        // "s3", "gcs", "azure", "local_fs"
    pub scope: String,          // "avatars"
    pub key: String,            // "avatars/user123/file.png"
    pub version: Option<String>, // provider-specific version id
    pub etag: Option<String>,
    pub checksum: Option<ObjectChecksum>, // SHA256 or CRC32C
    pub content_type: Option<String>,
    pub size: u64,
    pub visibility: ObjectVisibility,  // Private (default) or Public
    pub metadata: BTreeMap<String, String>,
}
```

It's **not** a URL. Private reads go through `StorageClient::signed_read()` or a server proxy route. Public objects can expose a stable URL only when the scope policy allows it.

## Key API / syntax

### Server-side (Rust, `#[cfg(pocopine_host)]`)

**Plugin setup:**
```rust
pub fn storage_server() -> StorageResult<StorageServer> {
    let policy = UploadPolicy::new("s3")?
        .max_bytes(10 * 1024 * 1024)              // 10 MiB
        .preferred_chunk_size(5 * 1024 * 1024);   // 5 MiB chunks

    let scope = StorageScope::builder(policy)
        .key_resolver(AvatarKeyResolver)           // app-owned
        .write_guard(require_auth())               // auth check
        .build();

    StorageServer::builder()
        .backend("s3", S3StorageBackend::from_env()?)
        .scope("avatars", scope)?
        .build()
}
```

**StorageKeyResolver trait:**
```rust
impl StorageKeyResolver for AvatarKeyResolver {
    fn resolve_key<'a>(
        &'a self,
        ctx: &'a StorageContext,
        intent: &'a UploadIntent,
    ) -> StorageKeyFuture<'a> {
        Box::pin(async move {
            let principal = ctx.require_principal()?;
            let object_id = intent.generated_object_id(); // UUID
            let ext = intent.extension().unwrap_or("");

            let key = SafeObjectKey::parse(format!(
                "avatars/{}/{}{}",
                principal.subject, object_id, ext
            ))?;

            Ok(StorageKey::new(key)
                .owner(ObjectOwnerRef::principal(principal.subject))
                .metadata_from([("kind", "avatar")]))
        })
    }
}
```

**StorageBackend trait** (implement per provider):
```rust
pub trait StorageBackend: Send + Sync + 'static {
    fn name(&self) -> &'static str;
    fn capabilities(&self) -> BackendCapabilities; // sequential, multipart, signed_direct
    fn initiate_upload(&self, ctx, request) -> StorageBoxFuture<UploadSession>;
    fn inspect_upload(&self, ctx, session_id) -> StorageBoxFuture<UploadSession>;
    fn append_upload_bytes(&self, ctx, session, offset, bytes) -> StorageBoxFuture<UploadSession>;
    fn upload_part(&self, ctx, session, part_number, body) -> StorageBoxFuture<UploadSession>;
    fn complete_upload(&self, ctx, request) -> StorageBoxFuture<ObjectRef>;
    fn abort_upload(&self, ctx, session_id) -> StorageBoxFuture<()>;
    fn signed_read(&self, ctx, object, options) -> StorageBoxFuture<SignedRead>;
    fn public_url(&self, object) -> StorageBoxFuture<Option<String>>;
    fn delete_object(&self, ctx, object) -> StorageBoxFuture<()>;
}
```

**Server-side write** (e.g., for jobs that export data):
```rust
let storage = active_plugin::<StorageServer>()?;
let ctx = StorageContext::system("job:export");

let object = storage.write_object(
    ctx,
    "exports",
    ServerWriteObject {
        file_name: Some("report.csv".to_string()),
        content_type: Some("text/csv".to_string()),
        size_hint: Some(5_000_000),
        metadata: BTreeMap::from([("job_id", job_id)]),
        body: StorageBody::from_stream(csv_stream),
    }
).await?;
```

### Browser-side (Rust/WASM, `#[cfg(target_arch = "wasm32")]`)

**App plugin install:**
```rust
pocopine::app! {
    components: [AvatarUpload],
    plugins: [
        pocopine_storage::storage_plugin()
            .endpoint("/__pocopine/storage/v1")
            .with_credentials(true),
    ],
    routes: [("/", AvatarUpload)],
}
```

**Basic upload:**
```rust
let storage = plugin::<StorageClient>()?;
let descriptor = storage.scope("avatars").descriptor().await?;

let file: web_sys::File = get_file_from_input();
let upload = storage
    .scope("avatars")
    .upload(file)
    .strategy(UploadStrategy::Auto)
    .metadata("source", "profile-form")
    .send()
    .await?;

let object: ObjectRef = upload.object;
// Now store object in your sync row, database, etc.
```

**With progress:**
```rust
storage
    .scope("avatars")
    .upload(file)
    .strategy(UploadStrategy::Sequential)
    .on_progress(|progress| {
        tracing::debug!(
            sent = progress.bytes_sent,
            total = progress.bytes_total,
            phase = ?progress.phase, // Initiating, Uploading, Completing, Complete, Failed, etc.
        );
    })
    .send()
    .await?;
```

**Resume after browser reload:**
```rust
let session_id = UploadSessionId::new("..."); // saved before reload
let session = storage.scope("avatars").session(session_id).await?;

let upload = storage
    .scope("avatars")
    .resume(file, session)
    .send()
    .await?;
```

**Signed read for private objects:**
```rust
let object = ObjectRef { /* from database */ };
let signed = storage.signed_read(object).await?;
// signed.url is a short-lived presigned URL (S3, GCS, etc.)
```

## Examples

### Example 1: Setup S3 backend with auth

From `/home/zempare-mambisi/RustProjects/pocopine/examples/file-browser/src/storage_browser/server/storage/backend.rs`:

```rust
pub(crate) fn storage_server() -> StorageResult<StorageServer> {
    let settings = load_upload_settings()?;
    let policy = UploadPolicy::new("s3")?
        .max_bytes(MAX_UPLOAD_LIMIT_BYTES)
        .preferred_chunk_size(settings.preferred_chunk_bytes);
    
    let scope = StorageScope::builder(policy)
        .key_resolver(StorageBrowserUploadKeyResolver)
        .build();

    Ok(StorageServer::builder()
        .backend("s3", StorageBrowserUploadBackend)?
        .scope("browser", scope)?
        .build())
}

impl StorageKeyResolver for StorageBrowserUploadKeyResolver {
    fn resolve_key<'a>(
        &'a self,
        _ctx: &'a StorageContext,
        intent: &'a UploadIntent,
    ) -> StorageKeyFuture<'a> {
        Box::pin(async move {
            let connection_id = intent.metadata().get("connection_id")
                .ok_or_else(|| StorageError::policy_rejected("connection required"))?;
            let mut prefix = intent.metadata().get("prefix")
                .map(|s| s.to_string())
                .unwrap_or_default();
            
            let name = sanitize_upload_name(intent.file_name());
            let key = SafeObjectKey::parse(format!("{}{}", prefix, name))?;
            
            Ok(StorageKey::new(key)
                .metadata_from([
                    ("original_name", intent.file_name()),
                    ("connection_id", connection_id),
                ]))
        })
    }
}
```

### Example 2: Browser upload with multipart strategy

```rust
let file: web_sys::File = get_file_input();
let storage = plugin::<StorageClient>()?;

let result = storage
    .scope("invoices")
    .upload(file)
    .strategy(UploadStrategy::Multipart)
    .metadata("invoice_id", "INV-2024-001")
    .on_progress(|progress| {
        match progress.phase {
            UploadPhase::Initiating => println!("Preparing..."),
            UploadPhase::Uploading => {
                let pct = (progress.bytes_sent as f64 / progress.bytes_total.unwrap_or(1) as f64) * 100.0;
                println!("Uploading {:.1}%", pct);
            }
            UploadPhase::Completing => println!("Finalizing..."),
            UploadPhase::Complete => println!("Done!"),
            _ => {}
        }
    })
    .send()
    .await?;

println!("Object stored: {:?}", result.object);
```

### Example 3: Fetch signed URL for private read

```rust
// In a component or server function
let storage = plugin::<StorageClient>()?;
let object_ref: ObjectRef = load_from_database();

let signed_read = storage.signed_read(&object_ref).await?;
// signed_read.url is a presigned GET URL (expires at signed_read.expires_at)
// Use it in <img src=...> or <a href=...>
```

## Gotchas

### Keys are server-generated, not browser-chosen

The `StorageKeyResolver` runs on the server and chooses the final key. The browser never submits bucket names, paths, or keys. This prevents key collisions, path traversal, and ensures keys match your app's ownership model.

```rust
// ❌ Don't let browser submit the key:
// (the resolver gets intent.file_name(), not a user-provided path)

// ✓ Do normalize file names and prepend your own structure:
let key = SafeObjectKey::parse(format!(
    "scope/{owner_id}/{generated_uuid}{ext}"
))?;
```

### SafeObjectKey rejects unsafe paths

`SafeObjectKey::parse()` rejects `..`, `/`, empty segments, and control characters. File names are metadata only unless the resolver explicitly includes a sanitized form.

```rust
// ✓ Safe:
SafeObjectKey::parse("avatars/user123/photo.png")?;

// ❌ Rejected (no `/` or `..`):
SafeObjectKey::parse("../../etc/passwd")?;
SafeObjectKey::parse("avatars/../other/file")?;
```

### Private is the default; public requires scope policy

`ObjectVisibility::Private` is the default. Reading a private object requires the scope's read guard to pass, even if you hold the `ObjectRef`. Only scopes with `ObjectVisibility::Public` can bypass the guard.

### Completion can fail after bytes reach the provider

For direct multipart uploads (presigned URLs), bytes are already in the provider when the browser completes. If completion fails (checksum mismatch, session expired), the partial object or parts are orphaned. The server's cleanup job should run periodically to abort expired multipart sessions in the provider.

### Resumability depends on strategy and target

| Strategy | Proxy | Direct | Resumable |
|----------|-------|--------|-----------|
| Sequential | ✓ | (GCS only) | Always |
| Multipart | ✓ | ✓ | Always |
| SingleRequest | ✗ | ✗ | No |

`SingleRequest` is non-resumable; a failed upload must be retried from the start.

### Browser storage of session IDs

The client may persist `(scope, session_id, file_name, size)` in `IndexedDB` or `LocalStorage` to offer resume after reload. It **must not** persist signed URLs or provider credentials; those expire and must be re-prepared through the server.

### Proxied uploads require streaming

Proxy routes (non-direct) must stream bytes to the provider without buffering the entire file in memory. The server's part handlers use `UploadBody::into_byte_stream()` to avoid `to_bytes()` calls.

## References

**Crates:**
- `crates/pocopine-storage` — Protocol, browser client, server plugin, local filesystem and memory backends
- `crates/pocopine-storage-s3` — AWS S3 and S3-compatible (Cloudflare R2, MinIO, Supabase) adapter
- `crates/pocopine-storage-gcs` — Google Cloud Storage resumable-upload adapter
- `crates/pocopine-storage-azure` — Azure Blob Storage (Block Blob) adapter

**Documentation:**
- `docs/storage-uploads.md` — Deep dive into streaming, concurrency, part receipts, memory profiles, and failure recovery
- `docs/browser-storage.md` — Browser-local typed preferences (different feature; same crate-name prefix)
- `rfcs/rfc-082-pocopine-storage.md` — Full RFC with protocol spec, security model, implementation plan, and non-goals

**Example:**
- `examples/file-browser/src/storage_browser/` — Full multi-backend file browser with S3, GCS, Azure integration, key resolver, and upload configuration

**Protocol constants:**
- `STORAGE_ENDPOINT_PREFIX` = `"/__pocopine/storage/v1"`
- `STORAGE_TUS_ENDPOINT_PREFIX` = `"/__pocopine/storage/tus/v1"`
- `STORAGE_ANON_COOKIE` = `"pocopine_storage_anon"` (anonymous upload binding)
