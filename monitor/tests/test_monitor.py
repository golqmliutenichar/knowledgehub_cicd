"""Unit tests for monitor v4 (run: python -m unittest discover -s tests -v).

The API is replaced by mocks, so the tests run without network access.
"""

import os
import sqlite3
import sys
import tempfile
import unittest
from unittest import mock

import requests

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import monitor  # noqa: E402


def settings(**extra):
    base = {"database": ":memory:", "host": "monitor", "metrics": ["cpu"], "limits": {},
            "count": 1, "interval": 0, "api_url": "https://api.test", "api_key": "k",
            "timeout": 1, "check_cloud": True}
    base.update(extra)
    return base


def fake_response(status, body=None):
    response = mock.Mock(status_code=status, text=str(body))
    response.headers = {"Content-Type": "application/json"}
    response.json.return_value = body or {}
    return response


class BufferTests(unittest.TestCase):
    def setUp(self):
        self.db = monitor.open_database(":memory:")
        monitor.save(self.db, "monitor", "2026-11-17T10:00:00Z", "cpu", 12.5, "%")
        monitor.save(self.db, "monitor", "2026-11-17T10:00:00Z", "memory", 40.0, "%")
        self.db.commit()

    def pending(self):
        return self.db.execute("SELECT COUNT(*) FROM measurements WHERE sent = 0").fetchone()[0]

    @mock.patch("monitor.requests.post")
    def test_rows_are_marked_sent_after_201(self, post):
        post.return_value = fake_response(201, {"stored": 2})
        self.assertEqual(monitor.send_pending(self.db, settings()), 2)
        self.assertEqual(self.pending(), 0)
        body = post.call_args.kwargs["json"]
        self.assertEqual(body["measurements"][0]["metric"], "cpu")
        self.assertEqual(post.call_args.kwargs["headers"]["X-API-Key"], "k")

    @mock.patch("monitor.requests.post", side_effect=requests.ConnectionError("VPN down"))
    def test_rows_are_kept_when_api_unreachable(self, _post):
        self.assertEqual(monitor.send_pending(self.db, settings()), 0)
        self.assertEqual(self.pending(), 2)

    @mock.patch("monitor.requests.post")
    def test_rows_are_kept_when_api_refuses(self, post):
        post.return_value = fake_response(401, {"error": "invalid or missing API key"})
        monitor.send_pending(self.db, settings())
        self.assertEqual(self.pending(), 2)

    def test_nothing_is_sent_without_api_settings(self):
        self.assertEqual(monitor.send_pending(self.db, settings(api_url="")), 0)


class UpgradeTests(unittest.TestCase):
    def test_v3_database_is_upgraded_and_old_rows_stay_local(self):
        path = os.path.join(tempfile.mkdtemp(), "v3.db")
        old = sqlite3.connect(path)
        old.execute("CREATE TABLE measurements (time TEXT, metric TEXT, value REAL)")
        old.execute("INSERT INTO measurements VALUES ('2026-10-13 08:00:00', 'cpu', 5)")
        old.commit()
        old.close()
        db = monitor.open_database(path)
        self.assertEqual(db.execute("SELECT sent FROM measurements").fetchone()[0], 1)
        db.close()


class CloudCheckTests(unittest.TestCase):
    @mock.patch("monitor.requests.get")
    def test_healthy_api_and_database(self, get):
        get.return_value = fake_response(200, {"status": "ok", "database": "ok", "db_latency_ms": 3.2})
        results = dict((name, value) for name, value, _unit in monitor.check_cloud(settings()))
        self.assertEqual(results["api_up"], 1)
        self.assertEqual(results["db_up"], 1)
        self.assertEqual(results["db_latency_ms"], 3.2)

    @mock.patch("monitor.requests.get")
    def test_database_down_behind_running_api(self, get):
        get.return_value = fake_response(503, {"status": "degraded", "database": "unreachable"})
        results = dict((name, value) for name, value, _unit in monitor.check_cloud(settings()))
        self.assertEqual((results["api_up"], results["db_up"]), (1, 0))

    @mock.patch("monitor.requests.get", side_effect=requests.Timeout("no answer"))
    def test_api_unreachable(self, _get):
        results = dict((name, value) for name, value, _unit in monitor.check_cloud(settings()))
        self.assertEqual((results["api_up"], results["db_up"]), (0, 0))


if __name__ == "__main__":
    unittest.main()
