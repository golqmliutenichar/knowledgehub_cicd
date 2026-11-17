"""Unit tests for the monitoring API (run: python -m unittest discover -s tests -v).

They use an in-memory SQLite database, so no Azure access is needed.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from app import create_app  # noqa: E402
from app.models import db  # noqa: E402

KEY = "test-key"


class ApiTestCase(unittest.TestCase):
    def setUp(self):
        self.app = create_app({
            "TESTING": True,
            "SQLALCHEMY_DATABASE_URI": "sqlite://",
            "SQLALCHEMY_ENGINE_OPTIONS": {},
            "API_KEY": KEY,
            "MAX_BATCH": 5,
            "LOG_LEVEL": "WARNING",
        })
        self.client = self.app.test_client()
        self.headers = {"X-API-Key": KEY}

    def tearDown(self):
        with self.app.app_context():
            db.session.remove()
            db.drop_all()
            db.engine.dispose()

    def post(self, body, headers=None):
        return self.client.post("/api/v1/measurements", json=body,
                                headers=self.headers if headers is None else headers)

    def sample(self, host="monitor", **extra):
        body = {"host": host, "measurements": [
            {"metric": "cpu", "value": 10.0, "measured_at": "2026-11-17T10:00:00Z"},
            {"metric": "cpu", "value": 30.0, "measured_at": "2026-11-17T10:05:00Z"},
            {"metric": "memory", "value": 55.5, "measured_at": "2026-11-17T10:00:00Z"},
        ]}
        body.update(extra)
        return self.post(body)


class HealthTests(ApiTestCase):
    def test_live_needs_no_key(self):
        self.assertEqual(self.client.get("/health/live").status_code, 200)

    def test_health_reports_database(self):
        response = self.client.get("/health")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["database"], "ok")


class AuthTests(ApiTestCase):
    def test_missing_key_is_rejected(self):
        self.assertEqual(self.post({"host": "a", "metric": "cpu", "value": 1}, headers={}).status_code, 401)

    def test_wrong_key_is_rejected(self):
        response = self.client.get("/api/v1/measurements", headers={"X-API-Key": "wrong"})
        self.assertEqual(response.status_code, 401)

    def test_empty_configured_key_rejects_everything(self):
        self.app.config["API_KEY"] = ""
        self.assertEqual(self.client.get("/api/v1/hosts", headers={"X-API-Key": ""}).status_code, 401)


class StoreTests(ApiTestCase):
    def test_store_batch(self):
        response = self.sample()
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.get_json()["stored"], 3)

    def test_store_single_measurement_without_time(self):
        response = self.post({"host": "ws01", "metric": "disk", "value": 71, "unit": "%"})
        self.assertEqual(response.status_code, 201)

    def test_rejects_non_numeric_value(self):
        response = self.post({"host": "a", "metric": "cpu", "value": "high"})
        self.assertEqual(response.status_code, 400)

    def test_rejects_boolean_value(self):
        self.assertEqual(self.post({"host": "a", "metric": "cpu", "value": True}).status_code, 400)

    def test_rejects_invalid_metric_name(self):
        self.assertEqual(self.post({"host": "a", "metric": "cpu; DROP TABLE", "value": 1}).status_code, 400)

    def test_rejects_bad_time(self):
        body = {"host": "a", "metric": "cpu", "value": 1, "measured_at": "yesterday"}
        self.assertEqual(self.post(body).status_code, 400)

    def test_rejects_too_large_batch(self):
        items = [{"metric": "cpu", "value": i} for i in range(6)]
        self.assertEqual(self.post({"host": "a", "measurements": items}).status_code, 413)

    def test_rejects_non_json_body(self):
        response = self.client.post("/api/v1/measurements", data="not json", headers=self.headers)
        self.assertEqual(response.status_code, 400)


class ReadTests(ApiTestCase):
    def setUp(self):
        super().setUp()
        self.sample()
        self.sample(host="fs")

    def query(self, path, **params):
        return self.client.get(path, query_string=params, headers=self.headers)

    def test_list_filters_on_host_and_metric(self):
        data = self.query("/api/v1/measurements", host="monitor", metric="cpu",
                          start="2026-11-17T09:00:00", end="2026-11-17T11:00:00").get_json()
        self.assertEqual(data["count"], 2)
        self.assertEqual(data["measurements"][0]["value"], 30.0)  # newest first

    def test_list_respects_time_window(self):
        data = self.query("/api/v1/measurements", start="2026-11-17T10:01:00",
                          end="2026-11-17T11:00:00").get_json()
        self.assertEqual(data["count"], 2)  # only the 10:05 cpu values of both hosts

    def test_summary_gives_min_avg_max(self):
        data = self.query("/api/v1/measurements/summary", host="monitor",
                          start="2026-11-17T09:00:00", end="2026-11-17T11:00:00").get_json()
        cpu = next(row for row in data["summary"] if row["metric"] == "cpu")
        self.assertEqual((cpu["min"], cpu["avg"], cpu["max"], cpu["count"]), (10.0, 20.0, 30.0, 2))

    def test_hosts_lists_every_sender(self):
        hosts = {row["host"] for row in self.query("/api/v1/hosts").get_json()["hosts"]}
        self.assertEqual(hosts, {"monitor", "fs"})

    def test_bad_limit_is_400(self):
        self.assertEqual(self.query("/api/v1/measurements", limit="many").status_code, 400)

    def test_unknown_path_is_json_404(self):
        response = self.query("/api/v1/nothing")
        self.assertEqual(response.status_code, 404)
        self.assertIn("error", response.get_json())


if __name__ == "__main__":
    unittest.main()
