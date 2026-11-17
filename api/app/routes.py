"""HTTP endpoints of the monitoring API (see docs/API.md)."""

import logging
import time
from datetime import timedelta

from flask import Blueprint, current_app, jsonify, request
from sqlalchemy import func, text

from .auth import require_api_key
from .models import Measurement, db, utc_now
from .validation import ValidationError, check_measurement, parse_time

log = logging.getLogger(__name__)
bp = Blueprint("api", __name__)


@bp.get("/health/live")
def live():
    """Liveness: the process is running (no database call, used by the platform probe)."""
    return jsonify(status="ok")


@bp.get("/health")
def health():
    """Readiness: is the database reachable, and how fast does it answer?"""
    start = time.perf_counter()
    try:
        db.session.execute(text("SELECT 1"))
    except Exception:  # any driver error means the database is not usable
        log.exception("Health check: database not reachable")
        return jsonify(status="degraded", database="unreachable"), 503
    latency = round((time.perf_counter() - start) * 1000, 1)
    return jsonify(status="ok", database="ok", db_latency_ms=latency)


@bp.post("/api/v1/measurements")
@require_api_key
def add_measurements():
    """Store one measurement or a batch: {"host": "...", "measurements": [...]}."""
    body = request.get_json(silent=True)
    if not isinstance(body, dict):
        return jsonify(error="body must be a JSON object"), 400

    items = body.get("measurements", [body])
    if not isinstance(items, list) or not items:
        return jsonify(error="measurements must be a non-empty list"), 400
    if len(items) > current_app.config["MAX_BATCH"]:
        return jsonify(error=f"at most {current_app.config['MAX_BATCH']} measurements per request"), 413

    try:
        clean = [check_measurement(item, body.get("host")) for item in items]
    except ValidationError as error:
        return jsonify(error=str(error)), 400

    now = utc_now()
    rows = [Measurement(measured_at=item.pop("measured_at", now), **item) for item in clean]
    db.session.add_all(rows)
    db.session.commit()
    log.info("Stored %d measurement(s) from %s", len(rows), rows[0].host)
    return jsonify(stored=len(rows)), 201


def _filtered_query(query):
    """Apply the shared filters ?host= &metric= &start= &end= (default: last 24 hours)."""
    end = parse_time(request.args["end"], "end") if "end" in request.args else utc_now()
    start = parse_time(request.args["start"], "start") if "start" in request.args else end - timedelta(days=1)
    query = query.filter(Measurement.measured_at.between(start, end))
    if "host" in request.args:
        query = query.filter(Measurement.host == request.args["host"])
    if "metric" in request.args:
        query = query.filter(Measurement.metric == request.args["metric"])
    return query


@bp.get("/api/v1/measurements")
@require_api_key
def list_measurements():
    """Measurements in a time window, newest first."""
    try:
        limit = min(int(request.args.get("limit", 100)), 1000)
        query = _filtered_query(Measurement.query)
    except (ValueError, ValidationError) as error:
        return jsonify(error=str(error)), 400
    rows = query.order_by(Measurement.measured_at.desc()).limit(limit).all()
    return jsonify(count=len(rows), measurements=[row.to_dict() for row in rows])


@bp.get("/api/v1/measurements/summary")
@require_api_key
def summary():
    """Minimum, average and maximum per host and metric in a time window."""
    try:
        query = _filtered_query(db.session.query(
            Measurement.host, Measurement.metric,
            func.min(Measurement.value), func.avg(Measurement.value),
            func.max(Measurement.value), func.count(Measurement.id)))
    except ValidationError as error:
        return jsonify(error=str(error)), 400
    rows = query.group_by(Measurement.host, Measurement.metric).all()
    return jsonify(summary=[
        {"host": host, "metric": metric, "min": low, "avg": round(float(avg), 2),
         "max": high, "count": count}
        for host, metric, low, avg, high, count in rows
    ])


@bp.get("/api/v1/hosts")
@require_api_key
def hosts():
    """Every host that sent data, with the time of its last measurement."""
    rows = (db.session.query(Measurement.host, func.max(Measurement.measured_at))
            .group_by(Measurement.host).all())
    return jsonify(hosts=[{"host": host, "last_seen": last.isoformat() + "Z"} for host, last in rows])
