#!/usr/bin/env bash
# Packages the trino-db2 source + DB2 JDBC driver into a tarball
# ready to transfer to a RHEL 8 / Podman build host.
# Maven runs inside Podman during the build — no Maven needed on Mac or RHEL host.
#
# Usage: ./package-for-rhel.sh
# Output: trino-db2-471-rhel-build.tar.gz

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB2_JAR="$HOME/.m2/repository/com/ibm/db2/jcc/db2jcc/db2jcc4/db2jcc-db2jcc4.jar"
OUT="trino-db2-471-rhel-build.tar.gz"

echo "==> Checking for DB2 JDBC driver..."
if [[ ! -f "$DB2_JAR" ]]; then
  echo "ERROR: DB2 driver not found at $DB2_JAR"
  echo "       Install it first:"
  echo "         mvn install:install-file -Dfile=<path>/db2jcc4.jar \\"
  echo "           -DgroupId=com.ibm.db2.jcc -DartifactId=db2jcc -Dversion=db2jcc4 -Dpackaging=jar"
  exit 1
fi

echo "==> Copying DB2 driver into libs/ ..."
mkdir -p "$SCRIPT_DIR/libs"
cp "$DB2_JAR" "$SCRIPT_DIR/libs/db2jcc-db2jcc4.jar"

echo "==> Creating tarball: $OUT ..."
tar -czf "$OUT" \
  --exclude='.git' \
  --exclude='target' \
  --exclude='*.tar.gz' \
  --exclude='libs' \
  -C "$(dirname "$SCRIPT_DIR")" \
  "$(basename "$SCRIPT_DIR")"

# Add libs/ separately (excluded above to avoid double-packing on re-runs)
tar -rzf "$OUT" \
  -C "$SCRIPT_DIR" \
  libs/

echo ""
echo "Done! Transfer $OUT to your RHEL host, then:"
echo ""
echo "  scp $OUT user@rhel-host:~/"
echo "  ssh user@rhel-host"
echo "  tar -xzf trino-db2-471-rhel-build.tar.gz"
echo "  cd $(basename "$SCRIPT_DIR")"
echo "  podman build -f Dockerfile.rhel \\"
echo "    --build-arg MAVEN_IMAGE=<artifact_proxy>/maven:3.9.9-eclipse-temurin-23 \\"
echo "    --build-arg BASE=<artifact_proxy/trinodb/trino:471 \\"
echo "    -t trino-db2:471 ."
