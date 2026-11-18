"""v4: measure metrics, send them to the monitoring API in Azure, and check the cloud services.

Changes since v3 (CS1):
  - measurements are sent to the API (REQ-S2P2-06) with the requests library
  - the API URL and key come from .env / environment variables, never from the code
  - every measurement is first saved in the local SQLite database; rows that could not
    be sent (VPN down, API asleep) are sent on the next run, so no data is lost
  - "cloud" metrics: is the API up, how fast is it, and is its database reachable

Usage:
  python monitor.py measure                 measure once, send, check the cloud
  python monitor.py measure --count 0       keep measuring (cron or Docker)
  python monitor.py report --stats          last 24 hours from the local database
  python monitor.py report --source api     last 24 hours from the central database
"""

import argparse
import logging
import os
import socket
import sqlite3
import sys
import time
from datetime import datetime, timedelta, timezone

import psutil
import requests
from dotenv import find_dotenv, load_dotenv

log = logging.getLogger("monitor")


# ── settings ────────────────────────────────────────────────────────────

def load_settings():
    """Read all settings from .env (in the current folder) and the environment."""
    load_dotenv(find_dotenv(usecwd=True))
    limits = {}
    for name in ("cpu", "memory", "disk"):
        limit = os.getenv(f"{name.upper()}_LIMIT")       # e.g. CPU_LIMIT=90
        if limit:
            limits[name] = float(limit)
    return {
        "database": os.getenv("DATABASE", "monitor.db"),
        "host": os.getenv("MONITOR_HOST", socket.gethostname()),
        "metrics": [m.strip() for m in os.getenv("METRICS", "cpu,memory,disk").split(",") if m.strip()],
        "limits": limits,
        "count": int(os.getenv("COUNT", "1")),
        "interval": int(os.getenv("INTERVAL", "60")),
        "api_url": os.getenv("API_URL", "").rstrip("/"),
        "api_key": os.getenv("API_KEY", ""),
        "timeout": float(os.getenv("REQUEST_TIMEOUT", "30")),
        "check_cloud": os.getenv("CHECK_CLOUD", "true").lower() == "true",
    }


# ── measuring ───────────────────────────────────────────────────────────

def measure_metric(name):
    """Current value of one local metric, in %."""
    if name == "cpu":
        return psutil.cpu_percent(interval=1)
    if name == "memory":
        return psutil.virtual_memory().percent
    if name == "disk":
        return psutil.disk_usage("/").percent
    raise ValueError(f"unknown metric: {name}")


def check_cloud(settings):
    """Health of the cloud services, measured from here: API up/latency, database up/latency.

    Returns a list of (metric, value, unit). The API's /health endpoint runs a query on the
    Azure MySQL database, so its answer also tells whether the database is reachable.
    """
    if not settings["api_url"]:
        return []
    start = time.perf_counter()
    try:
        response = requests.get(f"{settings['api_url']}/health", timeout=settings["timeout"])
        latency = (time.perf_counter() - start) * 1000
        body = response.json() if response.headers.get("Content-Type", "").startswith("application/json") else {}
    except requests.RequestException as error:
        log.warning("API not reachable: %s", error)
        return [("api_up", 0, "bool"), ("db_up", 0, "bool")]

    results = [("api_up", 1, "bool"), ("api_latency_ms", round(latency, 1), "ms")]
    db_ok = response.status_code == 200 and body.get("database") == "ok"
    results.append(("db_up", 1 if db_ok else 0, "bool"))
    if db_ok and "db_latency_ms" in body:
        results.append(("db_latency_ms", body["db_latency_ms"], "ms"))
    return results


# ── local buffer (SQLite) ───────────────────────────────────────────────

def open_database(path):
    db = sqlite3.connect(path)
    db.execute("""CREATE TABLE IF NOT EXISTS measurements (
                      time   TEXT,
                      metric TEXT,
                      value  REAL)""")
    # v4 columns, added to an existing v3 database without losing its data.
    # Old v3 rows get sent = 1: they were measured in local time and stay local.
    columns = {row[1] for row in db.execute("PRAGMA table_info(measurements)")}
    for column, kind in (("host", "TEXT"), ("unit", "TEXT DEFAULT '%'"), ("sent", "INTEGER DEFAULT 1")):
        if column not in columns:
            db.execute(f"ALTER TABLE measurements ADD COLUMN {column} {kind}")
    db.commit()
    return db


def save(db, host, moment, metric, value, unit):
    db.execute("INSERT INTO measurements (time, metric, value, host, unit, sent) VALUES (?, ?, ?, ?, ?, 0)",
               (moment, metric, value, host, unit))


# ── sending to the API ──────────────────────────────────────────────────

def send_pending(db, settings, batch_size=200):
    """Send every unsent row to the API, oldest first. Returns the number sent."""
    if not settings["api_url"] or not settings["api_key"]:
        log.info("API_URL or API_KEY not set: measurements are only stored locally")
        return 0

    sent = 0
    while True:
        rows = db.execute("SELECT rowid, time, metric, value, host, unit FROM measurements "
                          "WHERE sent = 0 ORDER BY rowid LIMIT ?", (batch_size,)).fetchall()
        if not rows:
            return sent
        body = {"measurements": [
            {"host": host or settings["host"], "metric": metric, "value": value,
             "unit": unit or "%", "measured_at": moment}
            for _rowid, moment, metric, value, host, unit in rows
        ]}
        try:
            response = requests.post(f"{settings['api_url']}/api/v1/measurements", json=body,
                                     headers={"X-API-Key": settings["api_key"]},
                                     timeout=settings["timeout"])
        except requests.RequestException as error:
            log.warning("Could not reach the API, %d row(s) kept for the next run: %s", len(rows), error)
            return sent
        if response.status_code != 201:
            log.error("API refused the data (%s): %s", response.status_code, response.text[:200])
            return sent
        db.executemany("UPDATE measurements SET sent = 1 WHERE rowid = ?", [(r[0],) for r in rows])
        db.commit()
        sent += len(rows)


# ── modes ───────────────────────────────────────────────────────────────

def measure(db, settings, count):
    """Measure `count` rounds (0 = forever): local metrics, cloud checks, then send."""
    i = 0
    while count == 0 or i < count:
        moment = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        for name in settings["metrics"]:
            value = measure_metric(name)
            save(db, settings["host"], moment, name, value, "%")
            alert = "  ALERT: over the limit!" if value >= settings["limits"].get(name, 101) else ""
            print(f"{moment}  {name:<15} {value:>8.1f} %{alert}", flush=True)

        if settings["check_cloud"]:
            for name, value, unit in check_cloud(settings):
                save(db, "azure", moment, name, value, unit)
                alert = "  ALERT: down!" if unit == "bool" and value == 0 else ""
                print(f"{moment}  {name:<15} {value:>8} {unit}{alert}", flush=True)
        db.commit()

        sent = send_pending(db, settings)
        waiting = db.execute("SELECT COUNT(*) FROM measurements WHERE sent = 0").fetchone()[0]
        print(f"sent to API: {sent}, waiting: {waiting}", flush=True)

        i += 1
        if count == 0 or i < count:
            time.sleep(settings["interval"])


def report_local(db, start, end, show_stats):
    rows = db.execute("SELECT time, host, metric, value FROM measurements "
                      "WHERE time BETWEEN ? AND ? ORDER BY time",
                      (start.strftime("%Y-%m-%dT%H:%M:%SZ"), end.strftime("%Y-%m-%dT%H:%M:%SZ")))
    print(f"\n{'Time (UTC)':<21} {'Host':<10} {'Metric':<15} {'Value':>8}")
    for moment, host, name, value in rows:
        print(f"{moment:<21} {host or '':<10} {name:<15} {value:>8.1f}")
    if show_stats:
        stats = db.execute("SELECT host, metric, MIN(value), AVG(value), MAX(value) FROM measurements "
                           "WHERE time BETWEEN ? AND ? GROUP BY host, metric",
                           (start.strftime("%Y-%m-%dT%H:%M:%SZ"), end.strftime("%Y-%m-%dT%H:%M:%SZ")))
        print(f"\n{'Host':<10} {'Metric':<15} {'Min':>8} {'Avg':>8} {'Max':>8}")
        for host, name, low, average, high in stats:
            print(f"{host or '':<10} {name:<15} {low:>8.1f} {average:>8.1f} {high:>8.1f}")


def report_api(settings, start, end):
    """Statistics from the central database, through the API."""
    response = requests.get(f"{settings['api_url']}/api/v1/measurements/summary",
                            params={"start": start.isoformat(), "end": end.isoformat()},
                            headers={"X-API-Key": settings["api_key"]}, timeout=settings["timeout"])
    response.raise_for_status()
    print(f"\n{'Host':<10} {'Metric':<15} {'Min':>8} {'Avg':>8} {'Max':>8} {'Count':>6}")
    for row in response.json()["summary"]:
        print(f"{row['host']:<10} {row['metric']:<15} {row['min']:>8.1f} {row['avg']:>8.1f} "
              f"{row['max']:>8.1f} {row['count']:>6}")


def to_time(text):
    return datetime.strptime(text, "%Y-%m-%d %H:%M")


def main(argv=None):
    parser = argparse.ArgumentParser(description="Knowledge Hub monitor v4")
    parser.add_argument("mode", choices=["measure", "report"])
    parser.add_argument("--count", type=int, help="0 = keep measuring")
    parser.add_argument("--start", type=to_time, help='"YYYY-MM-DD HH:MM" (UTC)')
    parser.add_argument("--end", type=to_time, help='"YYYY-MM-DD HH:MM" (UTC)')
    parser.add_argument("--stats", action="store_true")
    parser.add_argument("--source", choices=["local", "api"], default="local")
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    settings = load_settings()
    db = open_database(settings["database"])
    try:
        if args.mode == "measure":
            measure(db, settings, args.count if args.count is not None else settings["count"])
        else:
            end = args.end or datetime.now(timezone.utc).replace(tzinfo=None)
            start = args.start or end - timedelta(days=1)
            if args.source == "api":
                report_api(settings, start, end)
            else:
                report_local(db, start, end, args.stats)
    except requests.RequestException as error:
        log.error("API request failed: %s", error)
        return 1
    finally:
        db.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
