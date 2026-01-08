#!/bin/bash
set -euo pipefail

# MongoDB core collections + indexes bootstrapper.
# - Idempotent: safe to run multiple times.
# - Prefers db_connection.txt conventions (mongosh <connection-string>), otherwise uses env vars.
# - Defaults to port 5001 (per platform configuration).
#
# Collections:
# tenants, users, roles, channels, conversations, messages,
# knowledgeBases, knowledgeDocs, embeddings, auditLogs
#
# Required indexes:
# - tenantId on all collections
# - conversations: { tenantId: 1, status: 1, updatedAt: -1 }
# - messages: { tenantId: 1, conversationId: 1, createdAt: 1 }
# - users: { tenantId: 1, email: 1 } unique
# - channels: { tenantId: 1, type: 1 }
# - auditLogs: { tenantId: 1, createdAt: -1 }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_PORT="5001"

# Try to honor db_connection.txt convention: it typically contains "mongosh <connection-string>"
get_mongosh_connection_arg() {
  local conn_file="${SCRIPT_DIR}/db_connection.txt"
  if [ -f "${conn_file}" ]; then
    # Extract the mongodb://... portion.
    local uri
    uri="$(grep -oE 'mongodb(\+srv)?:\/\/[^ ]+' "${conn_file}" | head -n 1 || true)"
    if [ -n "${uri}" ]; then
      echo "${uri}"
      return 0
    fi
  fi

  # Fallback to env vars (standardized)
  if [ -n "${MONGODB_URL:-}" ]; then
    # Expect MONGODB_URL to include port; if not, it's still okay.
    echo "${MONGODB_URL}"
    return 0
  fi

  # Fallback to legacy aliases
  if [ -n "${MONGO_URL:-}" ]; then
    echo "${MONGO_URL}"
    return 0
  fi

  echo ""
  return 0
}

MONGO_URI="$(get_mongosh_connection_arg)"
MONGO_DB="${MONGODB_DB:-${MONGO_DB:-myapp}}"

if [ -z "${MONGO_URI}" ]; then
  # As a last resort, attempt localhost unauthenticated on default port.
  MONGO_URI="mongodb://localhost:${DEFAULT_PORT}/?directConnection=true"
fi

echo "Bootstrapping MongoDB collections/indexes..."
echo " - URI: ${MONGO_URI}"
echo " - DB:  ${MONGO_DB}"

# Run bootstrap logic in a single mongosh invocation.
# Notes:
# - createCollection is used only if collection doesn't exist; otherwise we skip.
# - createIndex is idempotent (same keys+options will be no-op).
mongosh "${MONGO_URI}" --quiet --eval "
const dbName = \"${MONGO_DB}\";
const targetDb = db.getSiblingDB(dbName);

function ensureCollection(name) {
  const existing = targetDb.getCollectionNames();
  if (!existing.includes(name)) {
    targetDb.createCollection(name);
    print('✓ created collection: ' + name);
  } else {
    print('• collection exists: ' + name);
  }
}

function ensureIndex(collName, keys, options) {
  options = options || {};
  const res = targetDb.getCollection(collName).createIndex(keys, options);
  print('✓ index ensured on ' + collName + ': ' + JSON.stringify(keys) + (options && Object.keys(options).length ? (' opts=' + JSON.stringify(options)) : ''));
  return res;
}

const collections = [
  'tenants',
  'users',
  'roles',
  'channels',
  'conversations',
  'messages',
  'knowledgeBases',
  'knowledgeDocs',
  'embeddings',
  'auditLogs',
];

collections.forEach(ensureCollection);

// tenantId index on all collections
collections.forEach((c) => ensureIndex(c, { tenantId: 1 }));

// Key compound indexes
ensureIndex('conversations', { tenantId: 1, status: 1, updatedAt: -1 });
ensureIndex('messages', { tenantId: 1, conversationId: 1, createdAt: 1 });
ensureIndex('users', { tenantId: 1, email: 1 }, { unique: true });
ensureIndex('channels', { tenantId: 1, type: 1 });
ensureIndex('auditLogs', { tenantId: 1, createdAt: -1 });

print('MongoDB bootstrap complete.');
" || {
  echo "✗ MongoDB bootstrap failed. Check connectivity/credentials/port (expected ${DEFAULT_PORT})." >&2
  exit 1
}

echo "✓ Done."
