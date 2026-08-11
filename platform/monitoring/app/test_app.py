import os
import tempfile
import time
import unittest

os.environ.setdefault("HISTORY_DB_PATH", os.path.join(tempfile.gettempdir(), "monitor-import.sqlite3"))

import app


class HistoryStoreTest(unittest.TestCase):
    def test_records_hourly_low_and_high_for_every_numeric_metric(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            store = app.HistoryStore(os.path.join(directory, "history.sqlite3"))
            first = {
                "ok": True,
                "containers": [
                    {
                        "id": "abc123",
                        "name": "web",
                        "image": "web:first",
                        "state": "running",
                        "cpuPercent": 2.5,
                        "memoryBytes": 100,
                        "running": 1,
                    }
                ],
            }
            second = {
                "ok": True,
                "containers": [
                    {
                        "id": "abc123",
                        "name": "web",
                        "image": "web:first",
                        "state": "running",
                        "cpuPercent": 9.5,
                        "memoryBytes": 80,
                        "running": 1,
                    }
                ],
            }

            now = time.time()
            store.record(first, now=now)
            store.record(second, now=now + 60)
            overview = store.overview()
            by_metric = {item["metric"]: item for item in overview["metrics"]}

            self.assertTrue(overview["ok"])
            self.assertEqual(by_metric["cpuPercent"]["low"], 2.5)
            self.assertEqual(by_metric["cpuPercent"]["high"], 9.5)
            self.assertEqual(by_metric["memoryBytes"]["low"], 80)
            self.assertEqual(by_metric["memoryBytes"]["high"], 100)
            self.assertEqual(by_metric["running"]["samples"], 2)

    def test_series_can_filter_by_container(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            store = app.HistoryStore(os.path.join(directory, "history.sqlite3"))
            now = time.time()
            store.record(
                {
                    "ok": True,
                    "containers": [
                        {"id": "a", "name": "web", "image": "web", "pids": 4},
                        {"id": "b", "name": "worker", "image": "worker", "pids": 8},
                    ],
                },
                now=now,
            )

            series = store.series(container_name="worker", hours=24 * 30)

            self.assertTrue(series["ok"])
            self.assertEqual({item["container"] for item in series["series"]}, {"worker"})


class DashboardHtmlTest(unittest.TestCase):
    def test_opens_live_with_clear_initial_connection_state(self) -> None:
        self.assertNotIn("?demo=", app.HTML)
        self.assertNotIn("Healthy example", app.HTML)
        self.assertNotIn("Incident example", app.HTML)
        self.assertIn("Connecting to live metrics", app.HTML)
        self.assertIn("Waiting for the first live sample", app.HTML)
        self.assertIn("Live · updated", app.HTML)


if __name__ == "__main__":
    unittest.main()
