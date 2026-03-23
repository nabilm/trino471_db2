# Trino DB2 Plugin — Upgrade to Trino 471

Based on the original IBM repo: https://github.com/IBM/trino-db2

## Summary

This fork upgrades the Trino DB2 connector plugin from version **405** to **471**, fixing all breaking API changes introduced between those releases.

---

## Files Changed

### `pom.xml`
- Bumped `trino.version` from `405` to `471`
- Added explicit versions for `javax.inject` and `javax.validation` as `provided` scope to fix classloader split issues with Guice in Trino 471
- Added `opentelemetry` dependencies as `provided` scope (required by new `DriverConnectionFactory` constructor)
- Added `-Dgit-commit-id.skip=true` to Maven build flags

### `Dockerfile`
- Switched builder image from `maven:3.9.9-eclipse-temurin-21` to `maven:3.9.9-eclipse-temurin-23` (Trino 471 requires Java 23 to compile)
- Added `JAVA_TOOL_OPTIONS="-Xint"` to disable JIT during Maven build — prevents SIGILL/SIGSEGV crashes under Rosetta x86 emulation on Apple Silicon Macs
- Added `rm -rf .git && git init` step to work around missing `.git` directory in Docker build context (git worktree issue)
- Added `-Dgit-commit-id.skip=true` to skip the `git-commit-id-maven-plugin` which fails without a real git history
- Changed Maven parallelism from `-T C1` to `-T 1` for stability under `-Xint`
- Added `-Xint` to the base Trino image's `jvm.config` to prevent JVM crashes at runtime under Rosetta

### `src/main/java/io/trino/plugin/db2/DB2Client.java`
- Updated `super()` constructor call — `BaseJdbcClient` in Trino 471 no longer accepts `BaseJdbcConfig` as the first parameter; removed it from the call
- Fixed deprecated import references for new Trino 471 package structure
- Updated `dateWriteFunctionUsingSqlDate()` and related column mapping calls to match new signatures

### `src/main/java/io/trino/plugin/db2/DB2ClientModule.java`
- Updated `DriverConnectionFactory` constructor call — added `OpenTelemetry` parameter required in Trino 471
- Replaced `CredentialProvider` / `CredentialPropertiesProvider` with the correct Trino 471 binding pattern:
  - Bind `CredentialConfig` via `configBinder`
  - Provide `CredentialProvider` as a `@Provides` method using `StaticCredentialProvider`
  - Bind `CredentialPropertiesProvider` to `DefaultCredentialPropertiesProvider` via `@Provides` method
- Removed `binder.install(new CredentialProviderModule())` — this module extends `AbstractConfigurationAwareModule` and cannot be installed from a plain `Module.configure()` method; Guice throws `configurationFactory was not set`
- Added `OpenTelemetry` injection to `getConnectionFactory()`

### `src/main/java/io/trino/plugin/db2/DB2Plugin.java`
- Changed `new DB2ClientModule()` to `DB2ClientModule::new` (method reference) to satisfy Trino 471's `ConnectorFactory` interface which expects a `Module` supplier

---

## Notes

### Apple Silicon / Rosetta Compatibility
Trino 471 uses Java 23 which has JIT compiler bugs under Rosetta x86 emulation (SIGILL/SIGSEGV in C1 compiler). The fix is `-Xint` in:
- The Docker builder (`JAVA_TOOL_OPTIONS="-Xint"` during `mvn install`)
- The Trino coordinator and worker `jvm.config`

This disables JIT (pure interpreter mode) which is slower but stable. For full performance, run Colima in ARM mode (`colima start --arch aarch64`) where JIT works natively.

### MinIO AIStor / Iceberg REST Catalog
The `local_stack` docker-compose uses MinIO AIStor as the Iceberg REST catalog. The correct Trino 471 config for this is:
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
s3.aws-access-key=minioadmin
s3.aws-secret-key=minioadmin123!
```

Key points:
- `security=SIGV4` is **not** a valid enum value in Trino 471 — use `sigv4-enabled=true` instead
- `signing-name` must be `s3tables` (MinIO AIStor implements the AWS S3 Tables API)
- `s3.region=local` — MinIO AIStor does not enforce region in on-prem deployments
- The warehouse must be created via `mc table warehouse create <alias> <name>` before use
