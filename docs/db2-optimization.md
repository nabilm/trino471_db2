# DB2 Connector — Performance Optimization Guide

> Based on Trino 471 + IBM DB2 JDBC plugin (`trino-db2-shb:471`)

---

## 1. Catalog Properties (`catalog/db2.properties`)

```properties
connector.name=db2
connection-url=jdbc:db2://<host>:50000/<DB>:currentSchema=DB2INST1;progressiveStreaming=2;queryDataSize=1048576;

# ----------------------------
# Connection Pool
# ----------------------------
connection-pool.max-size=30
connection-pool.min-size=5
connection-pool.idle-timeout=10m

# ----------------------------
# Pushdown — offload work to DB2 engine
# ----------------------------
join-pushdown.enabled=true
join-pushdown.strategy=EAGER
aggregation-pushdown.enabled=true
topn-pushdown.enabled=true

# ----------------------------
# Metadata Caching
# Avoids repeated JDBC metadata calls on every query
# ----------------------------
metadata.cache-ttl=10m
metadata.cache-missing-duration=2m
metadata.schemas-cache-ttl=10m

# ----------------------------
# Type Handling
# ----------------------------
decimal-mapping=ALLOW_OVERFLOW
unsupported-type-handling=CONVERT_TO_VARCHAR

# ----------------------------
# Write / Batch
# ----------------------------
write.batch-size=1000
```

---

## 2. DB2 JDBC URL Parameters

Append these to `connection-url` as `;key=value;` pairs.

| Parameter | Recommended Value | What it does |
|---|---|---|
| `progressiveStreaming` | `2` | Streams large result sets instead of buffering all rows in memory |
| `queryDataSize` | `1048576` | Fetch buffer size (1 MB) — increase for wide/large tables |
| `currentSchema` | `DB2INST1` | Avoids schema resolution overhead on every query |
| `sslConnection` | `false` | Skip SSL handshake on internal networks (faster) |
| `retrieveMessagesFromServerOnGetMessage` | `true` | Returns detailed DB2 error messages |

**Example full URL:**
```
jdbc:db2://db2-host:50000/MYDB:currentSchema=DB2INST1;progressiveStreaming=2;queryDataSize=1048576;sslConnection=false;retrieveMessagesFromServerOnGetMessage=true;
```

---

## 3. JVM Config — Workers (`worker/jvm.config`)

```
-Xmx8G
-XX:+UseG1GC
-XX:G1HeapRegionSize=32M
-XX:+ExplicitGCInvokesConcurrent
-XX:+HeapDumpOnOutOfMemoryError
-XX:ReservedCodeCacheSize=512M
```

> ⚠️ **Do NOT use `-Xint` on RHEL (x86_64).** That flag disables JIT compilation and was only needed on Apple Silicon Mac under Rosetta x86 emulation. Leaving it on will make Trino significantly slower.

---

## 4. Pushdown — What Gets Offloaded to DB2

When enabled, Trino pushes these operations directly into DB2 SQL rather than pulling raw data and processing in Trino:

| Feature | Config | Benefit |
|---|---|---|
| `JOIN` pushdown | `join-pushdown.enabled=true` | DB2 executes the join, less data transferred |
| `GROUP BY` / aggregations | `aggregation-pushdown.enabled=true` | SUM, COUNT, AVG run on DB2 side |
| `ORDER BY` + `LIMIT` | `topn-pushdown.enabled=true` | Pagination offloaded to DB2 |

> ⚠️ Set `join-pushdown.strategy=EAGER` only if DB2 is **not** under heavy concurrent load — it shifts CPU pressure from Trino workers to the DB2 server.

---

## 5. Things to Avoid

| Anti-pattern | Why | Fix |
|---|---|---|
| `SELECT *` from DB2 tables | Disables column pruning — fetches all columns even if unused | Always select specific columns |
| High `metadata.cache-ttl` on frequently changing schemas | Trino caches stale table/column definitions | Keep TTL low (`1m`) or `0` during development |
| `join-pushdown.strategy=EAGER` under DB2 load | Overloads DB2 with complex SQL | Use `AUTOMATIC` instead |
| `-Xint` in `jvm.config` on RHEL | Disables JIT — severe performance degradation | Remove it entirely on native x86 |

---

## 6. Checking if Pushdown is Working

Run `EXPLAIN` on a query and look for `TableScanNode` with pushed predicates:

```sql
EXPLAIN
SELECT count(*), region
FROM db2.db2inst1.customers
WHERE status = 'ACTIVE'
GROUP BY region;
```

Look for `:: [[ACTIVE]]` under the scan node — means the `WHERE` filter was pushed to DB2. If you see a `FilterNode` above the scan, the predicate was **not** pushed.
