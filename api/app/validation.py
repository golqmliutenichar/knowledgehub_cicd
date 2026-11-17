"""Checks on incoming data, so only clean values reach the database."""

import math
import re
from datetime import datetime, timezone

NAME_PATTERN = re.compile(r"^[A-Za-z0-9_.-]{1,50}$")
HOST_PATTERN = re.compile(r"^[A-Za-z0-9_.-]{1,100}$")


class ValidationError(ValueError):
    """Raised with a message that is safe to return to the client."""


def parse_time(text, field="time"):
    """ISO 8601 text (e.g. 2026-11-17T20:00:00Z) -> naive UTC datetime."""
    try:
        moment = datetime.fromisoformat(str(text))
    except ValueError:
        raise ValidationError(f"{field} must be an ISO 8601 date/time") from None
    if moment.tzinfo is not None:
        moment = moment.astimezone(timezone.utc).replace(tzinfo=None)
    return moment


def check_measurement(item, default_host):
    """Return a clean dict for one measurement or raise ValidationError."""
    if not isinstance(item, dict):
        raise ValidationError("each measurement must be an object")

    host = item.get("host", default_host)
    if not isinstance(host, str) or not HOST_PATTERN.match(host):
        raise ValidationError("host is missing or invalid")

    metric = item.get("metric")
    if not isinstance(metric, str) or not NAME_PATTERN.match(metric):
        raise ValidationError("metric is missing or invalid")

    value = item.get("value")
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValidationError(f"value of '{metric}' must be a number")

    unit = item.get("unit", "%")
    if not isinstance(unit, str) or len(unit) > 20:
        raise ValidationError("unit is invalid")

    measured_at = item.get("measured_at")
    clean = {"host": host, "metric": metric, "value": float(value), "unit": unit}
    if measured_at is not None:
        clean["measured_at"] = parse_time(measured_at, "measured_at")
    return clean
