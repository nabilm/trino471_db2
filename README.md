# trino-db2 — Trino 471 Fork

A community fork of [IBM/trino-db2](https://github.com/IBM/trino-db2) upgraded from version **405 to 471**, with full support for **Apple Silicon Macs running Colima x86_64 + Rosetta**.

> Original plugin by IBM: https://github.com/IBM/trino-db2 (branch `leeyh0216/trino-405-release`)

---

## What This Is

The IBM DB2 connector for Trino was last officially published for Trino 405. This fork manually upgrades it to Trino 471, fixing all breaking API changes and adding Rosetta compatibility.

---

## Quick Start

### Prerequisites
- Docker (Colima or Docker Desktop)
- Java 23+ and Maven 3.9+ (for local builds)

### Build the Docker Image

```bash
docker build \
  --build-arg BASE=trinodb/trino:471 \
  -t trino-db2:471 \
  .
```

> **Apple Silicon (Colima x86_64 + Rosetta):** The build uses `-Xint` to disable JIT and prevent SIGILL/SIGSEGV crashes. Expect a slower build (~15-30 min) but a stable image.

### Use in docker-compose

```yaml
services:
  trino-coordinator:
    image: trino-db2:471
```

---

## What Changed from IBM/trino-db2 (405 → 471)

### `pom.xml`
- Bumped `trino.version` to `471`
- `javax.inject` and `javax.validation` set to `provided` scope — fixes Guice classloader split issues
- `opentelemetry` dependencies added as `provided` (required by new `DriverConnectionFactory`)

### `Dockerfile`
- Builder image switched to `maven:3.9.9-eclipse-temurin-23` (Trino 471 requires Java 23)
- `JAVA_TOOL_OPTIONS="-Xint"` during Maven build — prevents JVM crashes under Rosetta
- `git init` step added — workaround for missing `.git` in Docker build context
- `-Dgit-commit-id.skip=true` — skips git-commit-id plugin (no git history in Docker)
- `-Xint` appended to base Trino image's `/etc/trino/jvm.config` — prevents runtime crashes under Rosetta

### `DB2Client.java`
- Removed `BaseJdbcConfig` from `super()` constructor call — no longer accepted in Trino 471
- Updated column mapping method calls to match new Trino 471 signatures

### `DB2ClientModule.java`
- Added `OpenTelemetry` parameter to `getConnectionFactory()`
- Replaced broken `CredentialProviderModule` install with proper Trino 471 binding:
  - `CredentialConfig` bound via `configBinder`
  - `CredentialProvider` provided via `@Provides` using `StaticCredentialProvider`
  - `CredentialPropertiesProvider` provided via `@Provides` wrapping `DefaultCredentialPropertiesProvider`
- Removed `binder.install(new CredentialProviderModule())` — throws `configurationFactory was not set` in Trino 471

### `DB2Plugin.java`
- Changed `new DB2ClientModule()` to `DB2ClientModule::new` (method reference) to satisfy Trino 471 API

---

## Catalog Configuration

Create `etc/catalog/db2.properties` in your Trino deployment:

```properties
connector.name=db2
connection-url=jdbc:db2://<host>:<port>/<database>
connection-user=<user>
connection-password=<password>
```

For SSL:
```properties
connection-url=jdbc:db2://<host>:<port>/<database>:sslConnection=true;
```

### Configuration Properties

| Property Name | Description |
|---|---|
| `db2.varchar-max-length` | Max length of VARCHAR in CREATE/ALTER TABLE. Default: `32672` |
| `db2.iam-api-key` | IBM Cloud IAM API Key (alternative to user/password) |

---

## Apple Silicon / Rosetta Notes

Trino 471 uses Java 23 which has JIT compiler bugs (SIGILL/SIGSEGV in C1) under Rosetta x86 emulation. The fix is `-Xint` in:

1. The Docker builder — `JAVA_TOOL_OPTIONS="-Xint"` during `mvn install`
2. The coordinator and worker `jvm.config` files

This runs the JVM in pure interpreter mode — **stable but ~5-10x slower than native**.

**For full performance:** Switch Colima to ARM mode:
```bash
colima stop
colima start --arch aarch64 --vm-type vz
```
No `-Xint` needed, full JIT, full speed.

---

## MinIO AIStor + Iceberg REST Catalog

This plugin was tested alongside MinIO AIStor as the Iceberg REST catalog backend. Trino 471 `iceberg.properties`:

```properties
connector.name=iceberg
iceberg.catalog.type=rest
iceberg.rest-catalog.uri=http://local-minio:9000/_iceberg
iceberg.rest-catalog.warehouse=lakehouse
iceberg.rest-catalog.sigv4-enabled=true
iceberg.rest-catalog.signing-name=s3tables
iceberg.rest-catalog.vended-credentials-enabled=true
iceberg.unique-table-location=true
fs.native-s3.enabled=true
fs.hadoop.enabled=false
s3.endpoint=http://local-minio:9000
s3.path-style-access=true
s3.region=local
s3.aws-access-key=<access-key>
s3.aws-secret-key=<secret-key>
```

Key points:
- `iceberg.rest-catalog.security=SIGV4` is **not** a valid value in Trino 471 — use `sigv4-enabled=true` instead
- `signing-name=s3tables` — MinIO AIStor implements the AWS S3 Tables API
- The warehouse must be created as a **table bucket** via the MinIO AIStor CLI or Console before use

---

## Replicating a DB2 Table to Iceberg (MinIO)

```sql
-- Create a schema in Iceberg
CREATE SCHEMA iceberg.myschema;

-- Copy a DB2 table to Iceberg in one shot
CREATE TABLE iceberg.myschema.mytable AS
SELECT * FROM db2.myschema.mytable;

-- Verify
SELECT * FROM iceberg.myschema.mytable;
```

---

## Links

- [IBM/trino-db2](https://github.com/IBM/trino-db2) — original plugin
- [Trino 471 docs](https://trino.io/docs/current/)
- [MinIO AIStor Tables](https://docs.min.io/enterprise/aistor-object-store/administration/aistor-tables/)
