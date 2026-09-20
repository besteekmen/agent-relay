# Agent Relay (SQLite and PostgreSQL)

Agent Relay is a small FastAPI service for registering agents, delivering one
task at a time, and recording results. The local starter is self-contained:
SQLite persists the queue and attempts, while workers execute tasks on their own
machines. The included worker deterministically returns `input.upper()`.

## Run it

```bash
uv sync
uv run uvicorn main:app --reload
```

Open <http://127.0.0.1:8000/> for the token-based local dashboard. The default
database is `./agent-relay.db`; set `RELAY_DATABASE_URL` to use another SQLite
file. `GET /health` is a liveness check and `GET /ready` verifies database
connectivity and schema (it queries the real tables, so a wiped volume
reports not-ready instead of passing with zero tables).

Register two identities and send a task:

```bash
alice=$(curl -sS -X POST http://127.0.0.1:8000/api/v1/agents \
  -H 'content-type: application/json' -d '{"name":"alice"}')
bob=$(curl -sS -X POST http://127.0.0.1:8000/api/v1/agents \
  -H 'content-type: application/json' -d '{"name":"uppercase"}')
```

The response contains each agent's secret `token` once. Keep it outside source
control. Use `Authorization: Bearer <token>` for all subsequent API calls;
registration is the only unauthenticated endpoint. For a shared installation,
set `RELAY_ENROLLMENT_SECRET` and send it as `X-Enrollment-Secret` when
registering.

## Run the deterministic worker

The worker can register itself and save credentials in a mode-0600 JSON file:

```bash
uv run python main.py worker \
  --base-url http://127.0.0.1:8000 \
  --name uppercase \
  --credentials ./uppercase-credentials.json \
  --worker-id laptop-1
```

For failure/redelivery demonstrations, make local execution intentionally slow
and stop the process after one completion:

```bash
uv run python main.py worker --credentials ./uppercase-credentials.json \
  --slow-seconds 75 --worker-id slow-laptop
```

The worker heartbeats during long work. Killing it leaves the claim leased;
after the 60-second lease expires, another worker can claim the task with a new
token and incremented attempt number. `RELAY_LEASE_SECONDS` and
`RELAY_MAX_ATTEMPTS` are configurable server settings.

An existing credential can also be supplied explicitly (the token is not
written to disk):

```bash
uv run python main.py worker --agent-id agent_123 --token agt_… --worker-id laptop-2
```

## Storage and delivery behavior

`database.py` contains SQLAlchemy models, SQLite WAL setup, and the isolated
`BEGIN IMMEDIATE` transaction helper. `storage.py` contains task/claim/recovery
operations; routes and request models are kept in `main.py` and `schemas.py`.
SQLite does not provide PostgreSQL's `FOR UPDATE SKIP LOCKED`, so the starter
serializes writer transactions to make concurrent claims safe across processes.
PostgreSQL uses normal transactions and `FOR UPDATE SKIP LOCKED` for claims.
Heartbeat, completion, and recovery lock the task before inspecting its attempt;
sender row locks serialize idempotent submissions. SQLite remains the default
for local development. Both backends use the HTTP protocol in `SPEC.md`.

Claims are at-least-once and leased for 60 seconds by default. Heartbeats extend
an active lease. A completion or failure must include the recipient's bearer
token and claim token. Repeating the exact terminal request with that claim
token is idempotent; a stale token or different result receives `409`.

## Verify

The test suite covers the main protocol, sender/recipient access boundaries,
hashed claim-token behavior, idempotent terminal retries, concurrent claims,
lease expiry before and after recovery, pagination/error shape, and dashboard
asset serving:

```bash
uv run pytest -q
```

Tests default to a scratch database at `/tmp/agent-relay-test.db` so they
don't reset your dev server's `./agent-relay.db`. The fixture drops and
recreates all tables on whatever `RELAY_DATABASE_URL` points at, so stop
the dev server first or set `RELAY_DATABASE_URL` to a scratch file before
running tests against another database.

## PostgreSQL with Docker Compose

Stop any existing server or standalone container publishing port 8000 first
(for example, `docker stop agent-relay-local`). Then start both services:

```bash
docker compose up --build
```

Open <http://localhost:8000/>. Compose waits for PostgreSQL's health check before
starting the API, whose health check calls `/ready`. The API creates missing
tables and connects using
`postgresql+psycopg://relay:relay-local@postgres:5432/agent_relay`.
`postgres` is the database service's hostname on the Compose network; database
port 5432 does not need to be published to the host. These credentials are for
local development.

PostgreSQL data lives in the named `postgres_data` volume and survives container
recreation and `docker compose down`. `docker compose down -v` deletes that data.
Existing SQLite data is not automatically migrated.

In another terminal, after the API is ready, run the existing acceptance test
against the running stack:

```bash
RELAY_TEST_BASE_URL=http://localhost:8000 uv run --frozen pytest -q \
  test_agent_relay.py::test_acceptance_scenario_1_sender_reads_completed_result
```

Live mode uses HTTP requests without importing the local application or resetting
database tables. It registers fresh agents and leaves its completed task available
in the database. Other tests that require local storage are skipped in live mode.
If WSL cannot reach Docker Desktop through localhost, run the test from an
environment that can reach the published port and set `RELAY_TEST_BASE_URL` to
that address.

Without `RELAY_TEST_BASE_URL`, the acceptance test still uses `TestClient` and
the isolated database fixture. Run the full local suite with:

```bash
uv run --frozen pytest -q
```
