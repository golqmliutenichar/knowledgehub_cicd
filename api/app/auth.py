"""API key authentication (header X-API-Key)."""

import hmac
import logging
from functools import wraps

from flask import current_app, jsonify, request

log = logging.getLogger(__name__)


def require_api_key(view):
    """Reject the request with 401 unless it carries the configured API key."""

    @wraps(view)
    def wrapper(*args, **kwargs):
        expected = current_app.config["API_KEY"]
        given = request.headers.get("X-API-Key", "")
        # compare_digest takes the same time for every wrong key (no timing leaks)
        if not expected or not hmac.compare_digest(given.encode(), expected.encode()):
            log.warning("Rejected request to %s from %s: invalid or missing API key",
                        request.path, request.headers.get("X-Forwarded-For", request.remote_addr))
            return jsonify(error="invalid or missing API key"), 401
        return view(*args, **kwargs)

    return wrapper
