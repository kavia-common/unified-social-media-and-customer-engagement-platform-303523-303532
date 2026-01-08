#!/bin/bash
set -euo pipefail

# Seed minimal development data for local UI flows.
# - Idempotent: safe to run multiple times.
# - Prefers db_connection.txt convention (mongosh <connection-string>), otherwise uses env vars.
# - Uses standardized env vars: MONGODB_URL, MONGODB_DB (accepts MONGO_URL/MONGO_DB aliases).
#
# Seeded data:
# - 1 tenant
# - roles: admin, support
# - 2 users: admin + support (with roleIds)
# - channels: Instagram, Facebook, Threads, WhatsApp
# - 1 sample conversation + 4 messages (user/agent alternating)
# - 1 knowledge base + 2 placeholder docs

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_PORT="5001"

get_mongosh_connection_arg() {
  local conn_file="${SCRIPT_DIR}/db_connection.txt"
  if [ -f "${conn_file}" ]; then
    local uri
    uri="$(grep -oE 'mongodb(\+srv)?:\/\/[^ ]+' "${conn_file}" | head -n 1 || true)"
    if [ -n "${uri}" ]; then
      echo "${uri}"
      return 0
    fi
  fi

  if [ -n "${MONGODB_URL:-}" ]; then
    echo "${MONGODB_URL}"
    return 0
  fi

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
  MONGO_URI="mongodb://localhost:${DEFAULT_PORT}/?directConnection=true"
fi

echo "Seeding MongoDB minimal dev data..."
echo " - URI: ${MONGO_URI}"
echo " - DB:  ${MONGO_DB}"

# We intentionally generate deterministic _id values to keep the seed stable/idempotent.
mongosh "${MONGO_URI}" --quiet --eval "
const dbName = \"${MONGO_DB}\";
const d = db.getSiblingDB(dbName);

function ensureOne(coll, filter, doc) {
  const existing = d.getCollection(coll).findOne(filter);
  if (existing) {
    // Keep existing doc, but ensure a couple of fields get updated if missing.
    d.getCollection(coll).updateOne(filter, { \$setOnInsert: doc }, { upsert: true });
    print('• exists: ' + coll + ' ' + JSON.stringify(filter));
    return existing;
  }
  d.getCollection(coll).updateOne(filter, { \$setOnInsert: doc }, { upsert: true });
  const created = d.getCollection(coll).findOne(filter);
  print('✓ created: ' + coll + ' ' + JSON.stringify(filter));
  return created;
}

function ensureMany(coll, docs, uniqueKeyFn) {
  docs.forEach((doc) => {
    const filter = uniqueKeyFn(doc);
    d.getCollection(coll).updateOne(filter, { \$setOnInsert: doc }, { upsert: true });
  });
  print('✓ ensured many: ' + coll + ' (' + docs.length + ')');
}

// ---- Deterministic IDs (24-hex strings) ----
const tenantId = ObjectId('64b000000000000000000001');
const roleAdminId = ObjectId('64b000000000000000000010');
const roleSupportId = ObjectId('64b000000000000000000011');

const adminUserId = ObjectId('64b000000000000000000100');
const supportUserId = ObjectId('64b000000000000000000101');

const channelInstagramId = ObjectId('64b000000000000000000200');
const channelFacebookId  = ObjectId('64b000000000000000000201');
const channelThreadsId   = ObjectId('64b000000000000000000202');
const channelWhatsAppId  = ObjectId('64b000000000000000000203');

const conversationId = ObjectId('64b000000000000000000300');

const kbId = ObjectId('64b000000000000000000400');
const kbDocWelcomeId = ObjectId('64b000000000000000000410');
const kbDocFaqId     = ObjectId('64b000000000000000000411');

const now = new Date();

// ---- Tenant ----
ensureOne('tenants', { _id: tenantId }, {
  _id: tenantId,
  tenantId: tenantId, // keep tenantId index happy even on tenant collection
  name: 'Acme Demo Tenant',
  slug: 'acme-demo',
  status: 'active',
  createdAt: now,
  updatedAt: now
});

// ---- Roles ----
ensureMany('roles', [
  {
    _id: roleAdminId,
    tenantId,
    name: 'admin',
    description: 'Administrator with full access (dev seed).',
    permissions: ['*'],
    createdAt: now,
    updatedAt: now
  },
  {
    _id: roleSupportId,
    tenantId,
    name: 'support',
    description: 'Support agent role (dev seed).',
    permissions: ['inbox:read', 'inbox:write', 'conversations:manage'],
    createdAt: now,
    updatedAt: now
  }
], (doc) => ({ tenantId: doc.tenantId, name: doc.name }));

// ---- Users ----
// NOTE: These are NOT real auth users; they're for UI/dev flows.
// If backend expects different auth fields, it can map these later.
ensureMany('users', [
  {
    _id: adminUserId,
    tenantId,
    email: 'admin@acme.test',
    displayName: 'Admin User',
    roleIds: [roleAdminId],
    status: 'active',
    createdAt: now,
    updatedAt: now
  },
  {
    _id: supportUserId,
    tenantId,
    email: 'support@acme.test',
    displayName: 'Support Agent',
    roleIds: [roleSupportId],
    status: 'active',
    createdAt: now,
    updatedAt: now
  }
], (doc) => ({ tenantId: doc.tenantId, email: doc.email }));

// ---- Channels ----
ensureMany('channels', [
  {
    _id: channelInstagramId,
    tenantId,
    type: 'instagram',
    name: 'Instagram (Demo)',
    handle: '@acme_demo',
    status: 'connected',
    createdAt: now,
    updatedAt: now
  },
  {
    _id: channelFacebookId,
    tenantId,
    type: 'facebook',
    name: 'Facebook Page (Demo)',
    handle: 'Acme Demo Page',
    status: 'connected',
    createdAt: now,
    updatedAt: now
  },
  {
    _id: channelThreadsId,
    tenantId,
    type: 'threads',
    name: 'Threads (Demo)',
    handle: '@acme_demo',
    status: 'connected',
    createdAt: now,
    updatedAt: now
  },
  {
    _id: channelWhatsAppId,
    tenantId,
    type: 'whatsapp',
    name: 'WhatsApp (Demo)',
    handle: '+1-555-0100',
    status: 'connected',
    createdAt: now,
    updatedAt: now
  }
], (doc) => ({ tenantId: doc.tenantId, type: doc.type }));

// ---- Sample Conversation ----
ensureOne('conversations', { _id: conversationId }, {
  _id: conversationId,
  tenantId,
  channelId: channelInstagramId,
  subject: 'Order status inquiry',
  status: 'open',
  priority: 'normal',
  assigneeUserId: supportUserId,
  customer: {
    name: 'Jamie Customer',
    externalId: 'ig:jamie_customer',
    username: 'jamie_customer'
  },
  createdAt: now,
  updatedAt: now
});

// ---- Messages (idempotent by (conversationId + createdAt) stable timestamps) ----
const t0 = new Date('2026-01-01T10:00:00.000Z');
const t1 = new Date('2026-01-01T10:00:15.000Z');
const t2 = new Date('2026-01-01T10:00:45.000Z');
const t3 = new Date('2026-01-01T10:01:10.000Z');

ensureMany('messages', [
  {
    tenantId,
    conversationId,
    channelId: channelInstagramId,
    direction: 'inbound',
    senderType: 'user',
    senderId: 'ig:jamie_customer',
    text: 'Hi! Can you tell me where my order is?',
    createdAt: t0
  },
  {
    tenantId,
    conversationId,
    channelId: channelInstagramId,
    direction: 'outbound',
    senderType: 'agent',
    senderId: String(supportUserId),
    text: 'Sure — could you share your order number?',
    createdAt: t1
  },
  {
    tenantId,
    conversationId,
    channelId: channelInstagramId,
    direction: 'inbound',
    senderType: 'user',
    senderId: 'ig:jamie_customer',
    text: 'It is #A12345. Thanks!',
    createdAt: t2
  },
  {
    tenantId,
    conversationId,
    channelId: channelInstagramId,
    direction: 'outbound',
    senderType: 'agent',
    senderId: String(supportUserId),
    text: 'Thanks! I see it is in transit and should arrive tomorrow. Anything else I can help with?',
    createdAt: t3
  }
], (doc) => ({ tenantId: doc.tenantId, conversationId: doc.conversationId, createdAt: doc.createdAt }));

// Ensure conversation updatedAt reflects last message time (safe/idempotent)
d.getCollection('conversations').updateOne(
  { _id: conversationId },
  { \$set: { updatedAt: t3 } }
);

// ---- Knowledge Base placeholders ----
ensureOne('knowledgeBases', { _id: kbId }, {
  _id: kbId,
  tenantId,
  name: 'Acme Support KB (Demo)',
  description: 'Placeholder knowledge base for local dev.',
  status: 'active',
  createdAt: now,
  updatedAt: now
});

ensureMany('knowledgeDocs', [
  {
    _id: kbDocWelcomeId,
    tenantId,
    knowledgeBaseId: kbId,
    title: 'Welcome',
    source: 'seed',
    content: 'Welcome to the Acme demo knowledge base. Replace with real docs.',
    tags: ['demo', 'welcome'],
    createdAt: now,
    updatedAt: now
  },
  {
    _id: kbDocFaqId,
    tenantId,
    knowledgeBaseId: kbId,
    title: 'FAQ (Placeholder)',
    source: 'seed',
    content: 'Q: Where is my order? A: Check tracking and estimated delivery.',
    tags: ['demo', 'faq'],
    createdAt: now,
    updatedAt: now
  }
], (doc) => ({ tenantId: doc.tenantId, knowledgeBaseId: doc.knowledgeBaseId, title: doc.title }));

print('MongoDB dev seed complete.');
" || {
  echo "✗ MongoDB dev seed failed. Check connectivity/credentials/port (expected ${DEFAULT_PORT})." >&2
  exit 1
}

echo "✓ Done."
