#!/usr/bin/env bash
set -euo pipefail
container="hidrobairro-ci-${BUILD_BUILDID:-$$}"
password="Hb$(openssl rand -hex 20)"
mkdir -p test-results/oracle
cleanup() {
  cp target/surefire-reports/TEST-*.xml test-results/oracle/ 2>/dev/null || true
  docker rm -f "$container" >/dev/null 2>&1 || true
}
trap cleanup EXIT
docker run -d --name "$container" -p 127.0.0.1:1525:1521 \
  -e ORACLE_PASSWORD="$password" -e APP_USER=hidrobairro -e APP_USER_PASSWORD="$password" \
  --health-cmd healthcheck.sh --health-interval 5s --health-timeout 5s --health-retries 90 \
  gvenzl/oracle-free:23-slim >/dev/null
ready=false
for attempt in $(seq 1 90); do
  if [ "$(docker inspect --format '{{.State.Health.Status}}' "$container")" = healthy ]; then
    ready=true
    break
  fi
  sleep 5
done
if [ "$ready" != true ]; then
  echo 'Oracle nao ficou pronto dentro do limite de 450 segundos.' >&2
  exit 1
fi
export TEST_DB_URL='jdbc:oracle:thin:@//localhost:1525/FREEPDB1'
export TEST_DB_DRIVER='oracle.jdbc.OracleDriver'
export TEST_DB_USER=hidrobairro
export TEST_DB_PASSWORD="$password"
export TEST_FLYWAY_ENABLED=true
export TEST_DDL_AUTO=validate
./mvnw --batch-mode --no-transfer-progress verify
