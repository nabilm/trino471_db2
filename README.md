# trino-db2

A community fork of [IBM/trino-db2](https://github.com/IBM/trino-db2) progressively upgraded from version **405 → 471 → 480**, with full support for **Apple Silicon Macs running Colima x86_64 + Rosetta**.

> Original plugin by IBM: https://github.com/IBM/trino-db2

---

## What This Is

The IBM DB2 connector for Trino was last officially published for Trino 405. This fork upgrades it to **Trino 480**, fixing all breaking API changes across versions, and packages it as a ready-to-use Docker image published to Docker Hub as `nabilm/trino-db2`.

---

## Quick Start

### Pull the image

```bash
docker pull nabilm/trino-db2:480
```

### Use in docker-compose

```yaml
services:
  trino-coordinator:
    image: nabilm/trino-db2:480
```

### Catalog configuration

Create `etc/catalog/db2.properties` in your Trino deployment:

```properties
connector.name=db2
connection-url=jdbc:db2://<host>:<port>/<database>
connection-user=<user>
connection-password=<password>
```

---

## Building Locally

### Prerequisites

- Maven 3.9+
- Java 18+ (JDK 24 required by Trino 480 parent POM — see Apple Silicon notes for workaround)

### Build the plugin JAR

```bash
mvn clean package \
  -Dmaven.test.skip=true \
  -Dmaven.enforcer.skip=true
```

Output: `target/trino-db2-480.zip` (plugin archive with all JARs)

### Build the Docker image

```bash
docker build \
  --build-arg BASE=trinodb/trino:480 \
  -t nabilm/trino-db2:480 \
  -t nabilm/trino-db2:latest \
  .
```

### Push to Docker Hub

```bash
docker login
docker push nabilm/trino-db2:480
docker push nabilm/trino-db2:latest
```

---

## Apple Silicon / Rosetta Notes

This repo is developed on an **Apple Silicon Mac running Colima in x86_64 mode with Rosetta emulation**:

```bash
colima start \
  --arch x86_64 \
  --vm-type vz \
  --vz-rosetta \
  --cpu 6 \
  --memory 12 \
  --disk 60
```

### Build issues under Rosetta

JDK 24 JIT (both Temurin and Corretto) emits x86_64 instructions that Rosetta cannot translate, causing **SIGILL crashes**. The fix: build with your local JDK and skip the enforcer:

```bash
mvn clean package \
  -Dmaven.test.skip=true \
  -Dmaven.enforcer.skip=true
```

If you get a JDK vendor enforcer failure, also add:

```bash
  -Dmaven.compiler.release=18 \
  -Dmaven.compiler.source=18 \
  -Dmaven.compiler.target=18
```

The resulting JAR runs fine inside `trinodb/trino:480` which ships with JDK 25.

### Runtime under Rosetta

The Dockerfile appends `-Xint` to `/etc/trino/jvm.config`, disabling JIT at runtime. This is **~5-10x slower** than native JIT but stable under Rosetta x86 emulation.

For full native performance, switch Colima to ARM64:

```bash
colima stop
colima start --arch aarch64 --vm-type vz --cpu 6 --memory 12 --disk 60
```

---

## What Changed from IBM/trino-db2

### 405 → 471

| File | Change |
|---|---|
| `pom.xml` | Parent version bumped to `471` |
| `pom.xml` | `javax.inject`, `javax.validation` moved to `provided` scope |
| `pom.xml` | OpenTelemetry dependencies added as `provided` |
| `DB2Client.java` | Removed `BaseJdbcConfig` from `super()` constructor |
| `DB2Client.java` | Updated column mapping method signatures |
| `DB2ClientModule.java` | Added `OpenTelemetry` param to `getConnectionFactory()` |
| `DB2ClientModule.java` | Replaced `CredentialProviderModule` with explicit `@Provides` bindings |
| `DB2Plugin.java` | Changed `new DB2ClientModule()` to `DB2ClientModule::new` |

### 471 → 480

| File | Change |
|---|---|
| `pom.xml` | Parent version bumped to `480` |
| `pom.xml` | `javax.validation:validation-api` → `jakarta.validation:jakarta.validation-api` (version managed by parent) |
| `pom.xml` | `javax.inject:javax.inject` removed (managed internally by Guice) |
| `pom.xml` | `com.google.inject:guice` — added `<classifier>classes</classifier>` |
| `pom.xml` | `org.openjdk.jol:jol-core` removed (dropped from Trino 480 SPI) |
| `pom.xml` | All `test`-scoped Trino artifacts removed (not published to Maven Central for 480) |
| `DB2Config.java` | `import javax.validation.constraints.Min` → `import jakarta.validation.constraints.Min` |
| `Dockerfile` | Default `BASE` changed to `trinodb/trino:480` |
| `Dockerfile` | Removes `-Djava.security.manager=allow` from jvm.config — unsupported in JDK 25 |
| `jvm.config` (coordinator + worker) | Removed `-Djava.security.manager=allow` — crashes JVM on startup in JDK 25 |

---

## Configuration Reference

### Required properties

| Property | Description |
|---|---|
| `connector.name` | Must be `db2` |
| `connection-url` | JDBC URL: `jdbc:db2://<host>:<port>/<database>` |
| `connection-user` | DB2 username |
| `connection-password` | DB2 password |

### Optional properties

| Property | Default | Description |
|---|---|---|
| `db2.varchar-max-length` | `32672` | Max VARCHAR length in CREATE/ALTER TABLE |
| `db2.iam-api-key` | — | IBM Cloud IAM API key (replaces user/password) |

### SSL

```properties
connection-url=jdbc:db2://<host>:<port>/<database>:sslConnection=true;
```

---

## Security Scan Notes (JFrog Xray)

### ✅ Apache Ranger — CVE-2025-59059 / CVE-2025-59060 (Fixed)

`trinodb/trino:471` bundled **Apache Ranger 2.6.0**, vulnerable to RCE and hostname bypass.
`trinodb/trino:480` ships with **Apache Ranger 2.8.0** — both CVEs are resolved.

### ⚠️ Apache FreeMarker — ProtectionDomain classloader escape (Suppress)

FreeMarker is used **internally** by Trino for template rendering. No Trino API accepts user-supplied FreeMarker templates. The attack surface does not exist in standard deployments.

Suggested Xray suppression justification:
> *FreeMarker in Trino is an internal dependency used for server-side HTML/text rendering. No user-supplied FreeMarker templates are processed. The classloader escape vector requires the attacker to already control template input, which is not possible through any public Trino API or connector interface.*

---

## Links

- [IBM/trino-db2](https://github.com/IBM/trino-db2) — original plugin
- [Trino 480 release notes](https://trino.io/docs/current/release/release-480.html)
- [Docker Hub: nabilm/trino-db2](https://hub.docker.com/r/nabilm/trino-db2)
- [trino_db2_minio](../trino_db2_minio) — full local dev stack using this image
