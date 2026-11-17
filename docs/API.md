# Monitoring API – specification (REQ-S2P2-05)

Base URL (private, reachable from the VNet or over the VPN only):
`https://kh-monitoring-api.<containerAppsDomain>` – the domain is shown in the Deploy run summary.

## Authentication

Every `/api/v1/...` call needs the header `X-API-Key: <API_KEY>`. A missing or wrong key gives
`401 {"error": "invalid or missing API key"}`. The key is a GitHub secret, stored as a Container
Apps secret, and in the monitor's `.env` – never in code. The health endpoints need no key.

## Endpoints

| Method | Path | Purpose | Success |
|---|---|---|---|
| GET | `/health/live` | Process is running (platform liveness probe) | 200 |
| GET | `/health` | Database reachable + query time | 200, or 503 when the database is down |
| POST | `/api/v1/measurements` | Store one measurement or a batch (max 500) | 201 |
| GET | `/api/v1/measurements` | List measurements, newest first | 200 |
| GET | `/api/v1/measurements/summary` | Min / avg / max / count per host and metric | 200 |
| GET | `/api/v1/hosts` | Hosts that sent data, with their last measurement | 200 |

Query filters for the GET endpoints: `host`, `metric`, `start`, `end` (ISO 8601, default the last
24 hours) and `limit` (default 100, max 1000) on the list endpoint. All times are UTC.

## POST /api/v1/measurements

Request:

```json
{
  "host": "monitor",
  "measurements": [
    {"metric": "cpu", "value": 12.5, "unit": "%", "measured_at": "2026-11-17T20:00:00Z"},
    {"metric": "memory", "value": 41.0}
  ]
}
```

`host` may also be set per measurement. `unit` defaults to `%`, `measured_at` to the time of arrival.
A single measurement without the `measurements` list is accepted too.

Response `201`:

```json
{"stored": 2}
```

## GET /api/v1/measurements/summary?host=monitor&start=2026-11-17T00:00:00

```json
{"summary": [
  {"host": "monitor", "metric": "cpu", "min": 0.5, "avg": 7.3, "max": 31.0, "count": 288}
]}
```

## GET /health

```json
{"status": "ok", "database": "ok", "db_latency_ms": 3.4}
```

## Errors

| Status | When |
|---|---|
| 400 | Body is not JSON, a field is missing/invalid (metric name, non-numeric value, bad time) |
| 401 | Missing or wrong API key |
| 404 / 405 | Unknown path / wrong method |
| 413 | More than 500 measurements in one request |
| 500 | Unexpected error (logged with a stack trace, details not returned) |
| 503 | `/health`: database not reachable |

All errors are JSON: `{"error": "<message>"}`.

## Data model (MySQL table `measurements`)

| Column | Type | Note |
|---|---|---|
| id | BIGINT, primary key | |
| host | VARCHAR(100) | e.g. `monitor`, `azure` |
| metric | VARCHAR(50) | e.g. `cpu`, `api_latency_ms` |
| value | FLOAT | |
| unit | VARCHAR(20) | `%`, `ms`, `bool` |
| measured_at | DATETIME (UTC) | index together with host and metric |
| received_at | DATETIME (UTC) | set by the API |

## Logging

One line per request (method, path, status, duration, client IP) to stdout, collected by
Log Analytics through the Container Apps environment. Rejected keys are logged as warnings.
Bodies and keys are never logged.
