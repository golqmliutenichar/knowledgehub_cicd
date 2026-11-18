"""The Knowledge Hub monitoring API (Flask)."""

import logging
import sys
import time

from dotenv import load_dotenv
from flask import Flask, g, jsonify, request
from werkzeug.exceptions import HTTPException

from .config import Config
from .models import db
from .routes import bp

log = logging.getLogger("api")


def create_app(overrides=None):
    """Build the Flask app. `overrides` replaces settings (used by the tests)."""
    load_dotenv()
    app = Flask(__name__)
    app.config.from_object(Config())
    if overrides:
        app.config.update(overrides)

    logging.basicConfig(stream=sys.stdout, level=app.config["LOG_LEVEL"],
                        format="%(asctime)s %(levelname)s %(name)s: %(message)s")

    db.init_app(app)
    app.register_blueprint(bp)
    state = {"tables_ready": False, "last_try": 0.0}

    def ensure_tables():
        """Create the table once. A database that is down must not stop the API from starting,
        so /health can still answer and report the problem."""
        if state["tables_ready"] or time.monotonic() - state["last_try"] < 30:
            return
        state["last_try"] = time.monotonic()
        try:
            db.create_all()
            state["tables_ready"] = True
            log.info("Database ready")
        except Exception as error:  # driver errors differ per database
            log.warning("Database not reachable yet, will retry: %s", str(error).splitlines()[0][:300])

    with app.app_context():
        ensure_tables()

    @app.before_request
    def start_timer():
        g.start = time.perf_counter()
        if request.path.startswith("/api/"):
            ensure_tables()

    @app.after_request
    def log_request(response):
        # One line per request, without bodies or keys (no personal data in logs)
        if request.path != "/health/live":
            duration = (time.perf_counter() - g.get("start", time.perf_counter())) * 1000
            log.info("%s %s %s %.0fms from %s", request.method, request.path, response.status_code,
                     duration, request.headers.get("X-Forwarded-For", request.remote_addr))
        return response

    @app.errorhandler(404)
    def not_found(_error):
        return jsonify(error="not found"), 404

    @app.errorhandler(405)
    def wrong_method(_error):
        return jsonify(error="method not allowed"), 405

    @app.errorhandler(Exception)
    def unexpected(error):
        if isinstance(error, HTTPException):   # 400, 415, ... keep their own status
            return jsonify(error=error.description), error.code
        log.exception("Unhandled error on %s %s", request.method, request.path)
        db.session.rollback()
        return jsonify(error="internal server error"), 500

    return app
