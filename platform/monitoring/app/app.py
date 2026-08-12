#!/usr/bin/env python3
"""Tiny read-only dashboard for Docker and Cloudflare health."""

from __future__ import annotations

import json
import os
import sqlite3
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

DOCKER_API_URL = os.getenv("DOCKER_API_URL", "http://docker-proxy:2375")
TUNNEL_METRICS_URL = os.getenv(
    "TUNNEL_METRICS_URL", "http://host.docker.internal:20241/metrics"
)
CLOUDFLARE_API_URL = "https://api.cloudflare.com/client/v4/graphql"
HISTORY_DB_PATH = os.getenv("HISTORY_DB_PATH", "/data/history.sqlite3")
HISTORY_RETENTION_DAYS = max(int(os.getenv("HISTORY_RETENTION_DAYS", "30")), 24)
HISTORY_SAMPLE_INTERVAL_SECONDS = max(
    int(os.getenv("HISTORY_SAMPLE_INTERVAL_SECONDS", "60")), 15
)
CLOUDFLARE_QUERY = """
query ZoneTraffic($zoneTag: string, $filter: filter) {
  viewer {
    zones(filter: {zoneTag: $zoneTag}) {
      traffic: httpRequestsAdaptiveGroups(limit: 100, filter: $filter) {
        count
        sum { visits edgeResponseBytes }
        dimensions { clientRequestHTTPHost }
      }
    }
  }
}
"""


def get_json(url: str, timeout: int = 10) -> Any:
    with urllib.request.urlopen(url, timeout=timeout) as response:
        return json.load(response)


def block_io_bytes(stats: dict[str, Any], operation: str) -> int:
    entries = stats.get("blkio_stats", {}).get("io_service_bytes_recursive") or []
    return sum(
        int(entry.get("value", 0))
        for entry in entries
        if str(entry.get("op", "")).lower() == operation
    )


def get_container_logs(container_name: str, tail: int = 100) -> str:
    """Get logs from a Docker container."""
    try:
        containers = get_json(f"{DOCKER_API_URL}/containers/json")
        container_id = None
        for container in containers:
            labels = container.get("Labels") or {}
            if labels.get("com.docker.compose.service") == container_name:
                container_id = container["Id"]
                break

        if not container_id:
            return f"Container '{container_name}' not found"

        logs_url = f"{DOCKER_API_URL}/containers/{urllib.parse.quote(container_id)}/logs?stdout=1&stderr=1&tail={tail}"
        with urllib.request.urlopen(logs_url, timeout=5) as response:
            raw_logs = response.read()

        # Parse Docker stream format (8 bytes header + payload per message)
        lines = []
        i = 0
        while i < len(raw_logs):
            if i + 8 > len(raw_logs):
                break
            stream_type = raw_logs[i]
            size = int.from_bytes(raw_logs[i+4:i+8], 'big')
            payload = raw_logs[i+8:i+8+size].decode('utf-8', errors='replace')
            lines.append(payload.rstrip('\n'))
            i += 8 + size

        return '\n'.join(lines[-tail:]) if lines else "(no logs)"
    except Exception as e:
        return f"Error fetching logs: {str(e)}"


def docker_stats(container: dict[str, Any]) -> dict[str, Any]:
    container_id = container["Id"]
    stats = get_json(
        f"{DOCKER_API_URL}/containers/{urllib.parse.quote(container_id)}/stats?stream=false"
    )
    cpu = stats.get("cpu_stats", {})
    previous_cpu = stats.get("precpu_stats", {})
    cpu_delta = cpu.get("cpu_usage", {}).get("total_usage", 0) - previous_cpu.get(
        "cpu_usage", {}
    ).get("total_usage", 0)
    system_delta = cpu.get("system_cpu_usage", 0) - previous_cpu.get(
        "system_cpu_usage", 0
    )
    online_cpus = cpu.get("online_cpus") or len(
        cpu.get("cpu_usage", {}).get("percpu_usage", [])
    )
    cpu_percent = (
        cpu_delta / system_delta * max(online_cpus, 1) * 100 if system_delta > 0 else 0
    )

    memory = stats.get("memory_stats", {})
    cache = memory.get("stats", {}).get("inactive_file", 0)
    memory_used = max(memory.get("usage", 0) - cache, 0)
    networks = stats.get("networks", {}).values()
    rx_bytes = sum(network.get("rx_bytes", 0) for network in networks)
    networks = stats.get("networks", {}).values()
    tx_bytes = sum(network.get("tx_bytes", 0) for network in networks)
    memory_limit = memory.get("limit", 0)

    labels = container.get("Labels") or {}
    return {
        "id": container_id[:12],
        "name": (container.get("Names") or [container_id[:12]])[0].lstrip("/"),
        "service": labels.get("com.docker.compose.service", ""),
        "image": container.get("Image", ""),
        "state": container.get("State", "unknown"),
        "status": container.get("Status", "unknown"),
        "cpuPercent": round(cpu_percent, 2),
        "memoryBytes": memory_used,
        "memoryLimitBytes": memory_limit,
        "memoryPercent": round(memory_used / memory_limit * 100, 2)
        if memory_limit
        else 0,
        "rxBytes": rx_bytes,
        "txBytes": tx_bytes,
        "blockReadBytes": block_io_bytes(stats, "read"),
        "blockWriteBytes": block_io_bytes(stats, "write"),
        "pids": int(stats.get("pids_stats", {}).get("current", 0)),
        "running": 1,
    }


def collect_docker() -> dict[str, Any]:
    try:
        containers = get_json(f"{DOCKER_API_URL}/containers/json?all=1")
        results = []
        for container in containers:
            if container.get("State") == "running":
                try:
                    results.append(docker_stats(container))
                except (OSError, ValueError, KeyError) as error:
                    results.append(
                        {
                            "id": container["Id"][:12],
                            "name": (container.get("Names") or ["unknown"])[0].lstrip("/"),
                            "image": container.get("Image", ""),
                            "state": container.get("State", "unknown"),
                            "status": container.get("Status", "unknown"),
                            "running": 1,
                            "error": str(error),
                        }
                    )
            else:
                results.append(
                    {
                        "id": container["Id"][:12],
                        "name": (container.get("Names") or ["unknown"])[0].lstrip("/"),
                        "image": container.get("Image", ""),
                        "state": container.get("State", "unknown"),
                        "status": container.get("Status", "unknown"),
                        "running": 0,
                    }
                )
        results.sort(key=lambda item: (item["state"] != "running", item["name"]))
        return {"ok": True, "containers": results}
    except (OSError, ValueError, KeyError) as error:
        return {"ok": False, "error": str(error), "containers": []}


CONTAINER_METADATA_FIELDS = {
    "id",
    "name",
    "service",
    "image",
    "state",
    "status",
    "error",
}


class HistoryStore:
    """Small hourly min/max rollup store for every numeric container metric."""

    def __init__(self, path: str) -> None:
        self.path = path
        self.lock = threading.Lock()
        self.error = ""
        self.last_pruned_at = 0.0
        try:
            os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
            with self.connect() as connection:
                connection.execute("PRAGMA journal_mode=WAL")
                connection.execute(
                    """
                    CREATE TABLE IF NOT EXISTS container_metric_hourly (
                        bucket_start INTEGER NOT NULL,
                        container_name TEXT NOT NULL,
                        container_id TEXT NOT NULL,
                        image TEXT NOT NULL,
                        metric TEXT NOT NULL,
                        min_value REAL NOT NULL,
                        max_value REAL NOT NULL,
                        last_value REAL NOT NULL,
                        samples INTEGER NOT NULL,
                        PRIMARY KEY (bucket_start, container_name, metric)
                    )
                    """
                )
                connection.execute(
                    """
                    CREATE INDEX IF NOT EXISTS container_metric_hourly_lookup
                    ON container_metric_hourly (container_name, metric, bucket_start)
                    """
                )
        except (OSError, sqlite3.Error) as error:
            self.error = str(error)

    def connect(self) -> sqlite3.Connection:
        return sqlite3.connect(self.path, timeout=10)

    def record(self, docker: dict[str, Any], now: float | None = None) -> None:
        if self.error or not docker.get("ok"):
            return
        timestamp = now if now is not None else time.time()
        bucket_start = int(timestamp // 3600 * 3600)
        rows = []
        for container in docker.get("containers", []):
            for metric, value in container.items():
                if metric in CONTAINER_METADATA_FIELDS or isinstance(value, bool):
                    continue
                if not isinstance(value, (int, float)):
                    continue
                rows.append(
                    (
                        bucket_start,
                        str(container.get("name", "unknown")),
                        str(container.get("id", "unknown")),
                        str(container.get("image", "")),
                        metric,
                        float(value),
                        float(value),
                        float(value),
                        1,
                    )
                )
        if not rows:
            return
        try:
            with self.lock, self.connect() as connection:
                connection.executemany(
                    """
                    INSERT INTO container_metric_hourly (
                        bucket_start, container_name, container_id, image, metric,
                        min_value, max_value, last_value, samples
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT (bucket_start, container_name, metric) DO UPDATE SET
                        container_id = excluded.container_id,
                        image = excluded.image,
                        min_value = MIN(min_value, excluded.min_value),
                        max_value = MAX(max_value, excluded.max_value),
                        last_value = excluded.last_value,
                        samples = samples + 1
                    """,
                    rows,
                )
                if timestamp - self.last_pruned_at >= 3600:
                    cutoff = int(
                        timestamp - HISTORY_RETENTION_DAYS * 24 * 60 * 60
                    )
                    connection.execute(
                        "DELETE FROM container_metric_hourly WHERE bucket_start < ?",
                        (cutoff,),
                    )
                    self.last_pruned_at = timestamp
        except sqlite3.Error as error:
            self.error = str(error)

    def overview(self, days: int = HISTORY_RETENTION_DAYS) -> dict[str, Any]:
        if self.error:
            return {"ok": False, "error": self.error, "retentionDays": days, "metrics": []}
        cutoff = int(time.time() - min(max(days, 1), HISTORY_RETENTION_DAYS) * 86400)
        try:
            with self.lock, self.connect() as connection:
                rows = connection.execute(
                    """
                    SELECT container_name, metric, MIN(min_value), MAX(max_value),
                           SUM(samples), MIN(bucket_start), MAX(bucket_start)
                    FROM container_metric_hourly
                    WHERE bucket_start >= ?
                    GROUP BY container_name, metric
                    ORDER BY container_name, metric
                    """,
                    (cutoff,),
                ).fetchall()
            return {
                "ok": True,
                "retentionDays": HISTORY_RETENTION_DAYS,
                "metrics": [
                    {
                        "container": row[0],
                        "metric": row[1],
                        "low": row[2],
                        "high": row[3],
                        "samples": row[4],
                        "firstBucket": datetime.fromtimestamp(
                            row[5], timezone.utc
                        ).isoformat(),
                        "lastBucket": datetime.fromtimestamp(
                            row[6], timezone.utc
                        ).isoformat(),
                    }
                    for row in rows
                ],
            }
        except sqlite3.Error as error:
            return {"ok": False, "error": str(error), "retentionDays": days, "metrics": []}

    def series(
        self, container_name: str = "", hours: int = 24 * HISTORY_RETENTION_DAYS
    ) -> dict[str, Any]:
        hours = min(max(hours, 1), 24 * HISTORY_RETENTION_DAYS)
        cutoff = int(time.time() - hours * 3600)
        if self.error:
            return {"ok": False, "error": self.error, "hours": hours, "series": []}
        query = """
            SELECT bucket_start, container_name, metric, min_value, max_value,
                   last_value, samples
            FROM container_metric_hourly
            WHERE bucket_start >= ?
        """
        parameters: list[Any] = [cutoff]
        if container_name:
            query += " AND container_name = ?"
            parameters.append(container_name)
        query += " ORDER BY bucket_start, container_name, metric"
        try:
            with self.lock, self.connect() as connection:
                rows = connection.execute(query, parameters).fetchall()
            return {
                "ok": True,
                "hours": hours,
                "retentionDays": HISTORY_RETENTION_DAYS,
                "series": [
                    {
                        "bucket": datetime.fromtimestamp(
                            row[0], timezone.utc
                        ).isoformat(),
                        "container": row[1],
                        "metric": row[2],
                        "low": row[3],
                        "high": row[4],
                        "last": row[5],
                        "samples": row[6],
                    }
                    for row in rows
                ],
            }
        except sqlite3.Error as error:
            return {"ok": False, "error": str(error), "hours": hours, "series": []}


def collect_tunnel() -> dict[str, Any]:
    selected = {
        "cloudflared_tunnel_ha_connections": "connections",
        "cloudflared_tunnel_active_streams": "activeStreams",
        "cloudflared_tunnel_total_requests": "totalRequests",
        "cloudflared_tunnel_request_errors": "requestErrors",
        "cloudflared_tunnel_timer_retries": "heartbeatRetries",
    }
    totals = {output_name: 0.0 for output_name in selected.values()}
    try:
        with urllib.request.urlopen(TUNNEL_METRICS_URL, timeout=5) as response:
            for raw_line in response:
                line = raw_line.decode().strip()
                if not line or line.startswith("#"):
                    continue
                metric_name = line.split("{", 1)[0].split(" ", 1)[0]
                if metric_name in selected:
                    totals[selected[metric_name]] += float(line.rsplit(" ", 1)[-1])
        totals["ok"] = True
        return totals
    except (OSError, ValueError) as error:
        return {"ok": False, "error": str(error), **totals}


class CloudflareAnalytics:
    def __init__(self) -> None:
        self.token = os.getenv("CLOUDFLARE_API_TOKEN", "")
        self.zone_id = os.getenv("CLOUDFLARE_ZONE_ID", "")
        self.zone_name = os.getenv("CLOUDFLARE_ZONE_NAME", "unknown")
        self.hostnames = {
            value.strip()
            for value in os.getenv("CLOUDFLARE_HOSTNAMES", "").split(",")
            if value.strip()
        }
        self.lock = threading.Lock()
        self.value: dict[str, Any] = {
            "ok": False,
            "configured": bool(self.token and self.zone_id),
            "zone": self.zone_name,
            "hostnames": [],
            "error": "Cloudflare analytics is not configured",
        }

    def refresh(self) -> None:
        if not self.token or not self.zone_id:
            return
        now = datetime.now(timezone.utc)
        payload = {
            "query": CLOUDFLARE_QUERY,
            "variables": {
                "zoneTag": self.zone_id,
                "filter": {
                    "datetime_geq": (now - timedelta(hours=24))
                    .isoformat(timespec="seconds")
                    .replace("+00:00", "Z"),
                    "datetime_lt": now.isoformat(timespec="seconds").replace(
                        "+00:00", "Z"
                    ),
                    "requestSource": "eyeball",
                },
            },
        }
        request = urllib.request.Request(
            CLOUDFLARE_API_URL,
            data=json.dumps(payload).encode(),
            headers={
                "Authorization": f"Bearer {self.token}",
                "Content-Type": "application/json",
                "User-Agent": "maimons-monitor/1.0",
            },
            method="POST",
        )
        try:
            try:
                with urllib.request.urlopen(request, timeout=30) as response:
                    result = json.load(response)
            except urllib.error.HTTPError as error:
                body = error.read().decode("utf-8", errors="replace")
                ray_id = error.headers.get("cf-ray", "")
                try:
                    error_payload = json.loads(body)
                    messages = [
                        str(item.get("message", item))
                        for item in error_payload.get("errors", [])
                    ]
                    detail = "; ".join(messages) or body[:500]
                except (ValueError, AttributeError):
                    detail = body[:500]
                suffix = f" (Ray ID: {ray_id})" if ray_id else ""
                raise RuntimeError(
                    f"Cloudflare GraphQL HTTP {error.code}: {detail}{suffix}"
                ) from error
            if result.get("errors"):
                messages = [
                    str(item.get("message", item)) for item in result["errors"]
                ]
                raise RuntimeError("; ".join(messages))
            zones = result["data"]["viewer"]["zones"]
            if not zones:
                raise RuntimeError(
                    "The configured zone was not returned. Verify that the zone ID "
                    "belongs to maimons.dev and is included in the API token scope."
                )
            groups = zones[0]["traffic"]
            hostnames = []
            for group in groups:
                hostname = group["dimensions"].get("clientRequestHTTPHost") or "unknown"
                if self.hostnames and hostname not in self.hostnames:
                    continue
                hostnames.append(
                    {
                        "hostname": hostname,
                        "requests": int(group.get("count", 0)),
                        "visits": int(group.get("sum", {}).get("visits", 0)),
                        "bytes": int(
                            group.get("sum", {}).get("edgeResponseBytes", 0)
                        ),
                    }
                )
            hostnames.sort(key=lambda item: item["requests"], reverse=True)
            with self.lock:
                self.value = {
                    "ok": True,
                    "configured": True,
                    "zone": self.zone_name,
                    "hostnames": hostnames,
                    "updatedAt": now.isoformat(),
                }
        except (OSError, ValueError, KeyError, IndexError, RuntimeError) as error:
            with self.lock:
                self.value = {
                    "ok": False,
                    "configured": True,
                    "zone": self.zone_name,
                    "hostnames": [],
                    "error": str(error),
                }

    def get(self) -> dict[str, Any]:
        with self.lock:
            return dict(self.value)


analytics = CloudflareAnalytics()
history = HistoryStore(HISTORY_DB_PATH)


class RuntimeCache:
    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.refresh_lock = threading.Lock()
        self.updated_at = 0.0
        self.value: dict[str, Any] = {
            "docker": {"ok": False, "error": "Runtime metrics are loading", "containers": []},
            "tunnel": {"ok": False, "error": "Tunnel metrics are loading"},
        }

    def get(self, force: bool = False) -> dict[str, Any]:
        with self.lock:
            if not force and time.time() - self.updated_at < 10:
                return dict(self.value)
        with self.refresh_lock:
            with self.lock:
                if not force and time.time() - self.updated_at < 10:
                    return dict(self.value)
            value = {"docker": collect_docker(), "tunnel": collect_tunnel()}
            with self.lock:
                self.value = value
                self.updated_at = time.time()
                return dict(value)


runtime = RuntimeCache()


def analytics_loop() -> None:
    while True:
        analytics.refresh()
        time.sleep(300)


def history_loop() -> None:
    while True:
        snapshot = runtime.get(force=True)
        history.record(snapshot["docker"])
        time.sleep(HISTORY_SAMPLE_INTERVAL_SECONDS)


PROMETHEUS_CONTAINER_METRICS = {
    "running": ("running", "gauge", "Whether the container is running (1 or 0)."),
    "cpuPercent": ("cpu_percent", "gauge", "Container CPU utilization percentage."),
    "memoryBytes": ("memory_bytes", "gauge", "Container working-set memory in bytes."),
    "memoryLimitBytes": ("memory_limit_bytes", "gauge", "Container memory limit in bytes."),
    "memoryPercent": ("memory_percent", "gauge", "Container memory utilization percentage."),
    "rxBytes": ("network_receive_bytes_total", "counter", "Container network bytes received."),
    "txBytes": ("network_transmit_bytes_total", "counter", "Container network bytes transmitted."),
    "blockReadBytes": ("block_read_bytes_total", "counter", "Container block bytes read."),
    "blockWriteBytes": ("block_write_bytes_total", "counter", "Container block bytes written."),
    "pids": ("pids", "gauge", "Current container process count."),
}


def prometheus_label(value: object) -> str:
    return str(value).replace("\\", "\\\\").replace("\n", "\\n").replace('"', '\\"')


def prometheus_metrics() -> bytes:
    snapshot = runtime.get()
    cloudflare = analytics.get()
    lines = [
        "# HELP maimons_monitor_up Whether the monitoring collector is operational.",
        "# TYPE maimons_monitor_up gauge",
        "maimons_monitor_up 1",
    ]
    docker = snapshot["docker"]
    lines.extend(
        [
            "# HELP maimons_monitor_docker_up Whether Docker metrics collection succeeded.",
            "# TYPE maimons_monitor_docker_up gauge",
            f"maimons_monitor_docker_up {1 if docker.get('ok') else 0}",
        ]
    )
    for source_key, (metric_name, metric_type, help_text) in PROMETHEUS_CONTAINER_METRICS.items():
        full_name = f"maimons_monitor_container_{metric_name}"
        lines.extend([f"# HELP {full_name} {help_text}", f"# TYPE {full_name} {metric_type}"])
        for container in docker.get("containers", []):
            value = container.get(source_key)
            if not isinstance(value, (int, float)) or isinstance(value, bool):
                continue
            labels = (
                f'container="{prometheus_label(container.get("name", "unknown"))}",'
                f'id="{prometheus_label(container.get("id", "unknown"))}",'
                f'image="{prometheus_label(container.get("image", ""))}"'
            )
            lines.append(f"{full_name}{{{labels}}} {value}")

    tunnel = snapshot["tunnel"]
    tunnel_metrics = {
        "connections": ("connections", "gauge"),
        "activeStreams": ("active_streams", "gauge"),
        "totalRequests": ("requests_total", "counter"),
        "requestErrors": ("request_errors_total", "counter"),
        "heartbeatRetries": ("heartbeat_retries_total", "counter"),
    }
    lines.extend(
        [
            "# HELP maimons_monitor_tunnel_up Whether cloudflared metrics collection succeeded.",
            "# TYPE maimons_monitor_tunnel_up gauge",
            f"maimons_monitor_tunnel_up {1 if tunnel.get('ok') else 0}",
        ]
    )
    for source_key, (metric_name, metric_type) in tunnel_metrics.items():
        full_name = f"maimons_monitor_tunnel_{metric_name}"
        lines.append(f"# HELP {full_name} cloudflared {metric_name.replace('_', ' ')}.")
        lines.append(f"# TYPE {full_name} {metric_type}")
        lines.append(f"{full_name} {tunnel.get(source_key, 0)}")

    lines.extend(
        [
            "# HELP maimons_monitor_cloudflare_up Whether Cloudflare analytics collection succeeded.",
            "# TYPE maimons_monitor_cloudflare_up gauge",
            f"maimons_monitor_cloudflare_up {1 if cloudflare.get('ok') else 0}",
            "# HELP maimons_monitor_cloudflare_requests_24h Cloudflare edge requests in the trailing 24 hours.",
            "# TYPE maimons_monitor_cloudflare_requests_24h gauge",
            "# HELP maimons_monitor_cloudflare_visits_24h Cloudflare visits in the trailing 24 hours.",
            "# TYPE maimons_monitor_cloudflare_visits_24h gauge",
            "# HELP maimons_monitor_cloudflare_edge_response_bytes_24h Cloudflare edge response bytes in the trailing 24 hours.",
            "# TYPE maimons_monitor_cloudflare_edge_response_bytes_24h gauge",
        ]
    )
    for hostname in cloudflare.get("hostnames", []):
        label = f'hostname="{prometheus_label(hostname.get("hostname", "unknown"))}"'
        lines.append(
            f"maimons_monitor_cloudflare_requests_24h{{{label}}} {hostname.get('requests', 0)}"
        )
        lines.append(
            f"maimons_monitor_cloudflare_visits_24h{{{label}}} {hostname.get('visits', 0)}"
        )
        lines.append(
            f"maimons_monitor_cloudflare_edge_response_bytes_24h{{{label}}} {hostname.get('bytes', 0)}"
        )

    overview = history.overview()
    lines.extend(
        [
            "# HELP maimons_monitor_history_up Whether persistent history storage is operational.",
            "# TYPE maimons_monitor_history_up gauge",
            f"maimons_monitor_history_up {1 if overview.get('ok') else 0}",
            "# HELP maimons_monitor_container_history_low Lowest observed value in the retained window.",
            "# TYPE maimons_monitor_container_history_low gauge",
            "# HELP maimons_monitor_container_history_high Highest observed value in the retained window.",
            "# TYPE maimons_monitor_container_history_high gauge",
        ]
    )
    for metric in overview.get("metrics", []):
        labels = (
            f'container="{prometheus_label(metric["container"])}",'
            f'metric="{prometheus_label(metric["metric"])}",'
            f'window="{HISTORY_RETENTION_DAYS}d"'
        )
        lines.append(f"maimons_monitor_container_history_low{{{labels}}} {metric['low']}")
        lines.append(f"maimons_monitor_container_history_high{{{labels}}} {metric['high']}")
    return ("\n".join(lines) + "\n").encode()


HTML = r'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Maimons Monitor</title>
<style>
:root{color-scheme:dark;--bg:#0b1017;--panel:#121a24;--line:#223044;--text:#e9f0f7;--muted:#8998aa;--green:#45d483;--red:#ff6978;--blue:#58a6ff;--orange:#ffad45}*{box-sizing:border-box}body{margin:0;background:radial-gradient(circle at 15% 0,#132238 0,transparent 30%),var(--bg);color:var(--text);font:14px ui-sans-serif,system-ui,-apple-system,sans-serif}main{max-width:1200px;margin:auto;padding:32px 20px 60px}header{display:flex;justify-content:space-between;align-items:flex-end;margin-bottom:14px}h1{font-size:25px;margin:0 0 5px;letter-spacing:-.02em}h2{font-size:15px;margin:0 0 14px}.muted{color:var(--muted)}.loading{display:flex;align-items:center;gap:10px;border:1px solid #294260;background:#101c2b;color:#b8d7ff;border-radius:9px;padding:11px 13px;margin-bottom:18px;transition:opacity .2s}.loading.hidden{display:none}.spinner{width:14px;height:14px;border:2px solid #35516f;border-top-color:var(--blue);border-radius:50%;animation:spin .8s linear infinite}@keyframes spin{to{transform:rotate(360deg)}}.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin-bottom:24px}.card,.section{background:rgba(18,26,36,.92);border:1px solid var(--line);border-radius:12px}.card{padding:16px}.card.bad{border-color:#692b37;background:rgba(53,20,28,.94)}.card.bad .value{color:var(--red)}.label{color:var(--muted);font-size:12px}.value{font-size:27px;font-weight:650;margin-top:8px}.section{padding:18px;margin-bottom:16px;overflow:auto}.row{display:flex;gap:8px;align-items:center}.dot{width:8px;height:8px;border-radius:50%;background:var(--green)}.dot.bad{background:var(--red)}table{border-collapse:collapse;width:100%;min-width:720px}th,td{text-align:left;padding:11px 8px;border-top:1px solid var(--line)}th{color:var(--muted);font-size:11px;text-transform:uppercase;letter-spacing:.06em}code{font-family:ui-monospace,SFMono-Regular,monospace;font-size:12px;color:#b9c7d7}.bar{height:5px;background:#233044;border-radius:4px;overflow:hidden;margin-top:5px;width:110px}.bar i{display:block;height:100%;background:var(--blue);border-radius:4px}.error{color:var(--red)}.pill{padding:3px 7px;border-radius:20px;background:#153421;color:var(--green);font-size:11px}.pill.bad{background:#3a1a21;color:var(--red)}@media(max-width:760px){.grid{grid-template-columns:repeat(2,1fr)}header{align-items:flex-start;flex-direction:column;gap:8px}}</style>
</head><body><main><header><div><h1>Maimons Monitor</h1><div class="muted">Live Docker runtime and Cloudflare edge metrics.</div></div><div id="stamp" class="muted" aria-live="polite">Connecting to live metrics…</div></header>
<div class="loading" id="loading" role="status" aria-live="polite"><span class="spinner" aria-hidden="true"></span><span id="loading-text">Connecting to Docker, Tunnel, history, and Cloudflare…</span></div><div class="grid" id="cards"></div><section class="section"><h2>Containers</h2><div id="containers"><span class="muted">Waiting for the first live sample…</span></div></section><section class="section"><h2>Container high / low history — 30 days</h2><div id="history"><span class="muted">Opening history…</span></div></section><section class="section"><h2>Cloudflare edge — trailing 24 hours</h2><div id="edge"><span class="muted">Loading edge analytics…</span></div></section></main>
<script>
const fmt=n=>new Intl.NumberFormat().format(Math.round(n||0)); const bytes=n=>{if(!n)return '0 B';const u=['B','KB','MB','GB','TB'],i=Math.min(Math.floor(Math.log(n)/Math.log(1024)),4);return `${(n/1024**i).toFixed(i?1:0)} ${u[i]}`};
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const metricValue=(metric,value)=>{if(value==null)return '—';if(metric.toLowerCase().includes('bytes'))return bytes(value);if(metric.toLowerCase().includes('percent'))return `${Number(value).toFixed(1)}%`;if(metric==='running')return value?'Running':'Stopped';return fmt(value)};
function cards(d){const t=d.tunnel||{}, c=d.docker?.containers||[], running=c.filter(x=>x.state==='running').length, a=d.cloudflare?.hostnames||[], requests=a.reduce((n,x)=>n+x.requests,0), visits=a.reduce((n,x)=>n+x.visits,0), volume=a.reduce((n,x)=>n+x.bytes,0),items=[['Tunnel',t.ok?`${fmt(t.connections)} connections`:'Unavailable',!t.ok||t.connections<4],['Containers',`${running} / ${c.length} running`,running<c.length],['Tunnel traffic',`${fmt(t.totalRequests)} requests`,false],['Tunnel errors',fmt(t.requestErrors),t.requestErrors>50],['Edge requests',`${fmt(requests)} · 24h`,false],['Visits',`${fmt(visits)} · ${bytes(volume)}`,false]];return items.map(([l,v,bad])=>`<div class="card ${bad?'bad':''}"><div class="label">${l}</div><div class="value">${v}</div></div>`).join('')}
function containerTable(d){if(!d.ok)return `<div class="error">${esc(d.error)}</div>`;if(!d.containers.length)return '<div class="muted">No containers found.</div>';return `<table><thead><tr><th>Status</th><th>Container</th><th>CPU</th><th>Memory</th><th>Network</th><th>Image</th></tr></thead><tbody>${d.containers.map(x=>{const mem=x.memoryLimitBytes?x.memoryBytes/x.memoryLimitBytes*100:0;return `<tr><td><span class="pill ${x.state==='running'?'':'bad'}">${esc(x.state)}</span></td><td><strong>${esc(x.name)}</strong><div class="muted">${esc(x.status)}</div></td><td>${x.cpuPercent==null?'—':x.cpuPercent.toFixed(1)+'%'}</td><td>${x.memoryBytes==null?'—':bytes(x.memoryBytes)}<div class="bar"><i style="width:${Math.min(mem,100)}%"></i></div></td><td>${x.rxBytes==null?'—':`↓ ${bytes(x.rxBytes)} · ↑ ${bytes(x.txBytes)}`}</td><td><code>${esc(x.image)}</code></td></tr>`}).join('')}</tbody></table>`}
function historyTable(d){if(!d.ok)return `<div class="error">${esc(d.error)}</div>`;if(!d.metrics.length)return '<div class="muted">History starts collecting after deployment. Hourly low/high rollups are retained for 30 days.</div>';return `<table><thead><tr><th>Container</th><th>Metric</th><th>Low</th><th>High</th><th>Samples</th><th>Observed</th></tr></thead><tbody>${d.metrics.map(x=>`<tr><td><strong>${esc(x.container)}</strong></td><td><code>${esc(x.metric)}</code></td><td>${metricValue(x.metric,x.low)}</td><td>${metricValue(x.metric,x.high)}</td><td>${fmt(x.samples)}</td><td class="muted">${new Date(x.firstBucket).toLocaleDateString()} – ${new Date(x.lastBucket).toLocaleDateString()}</td></tr>`).join('')}</tbody></table>`}
function edgeTable(d){if(!d.configured)return '<div class="muted">Add the read-only Cloudflare analytics token and zone ID to enable edge analytics.</div>';if(!d.ok)return `<div class="error">${esc(d.error)}</div>`;if(!d.hostnames.length)return '<div class="muted">No matching hostname traffic in the last 24 hours.</div>';return `<table><thead><tr><th>Hostname</th><th>Requests</th><th>Visits</th><th>Edge volume</th></tr></thead><tbody>${d.hostnames.map(x=>`<tr><td><strong>${esc(x.hostname)}</strong></td><td>${fmt(x.requests)}</td><td>${fmt(x.visits)}</td><td>${bytes(x.bytes)}</td></tr>`).join('')}</tbody></table>`}
async function refresh(){try{const [statusResponse,historyResponse]=await Promise.all([fetch('/api/status',{cache:'no-store'}),fetch('/api/history/overview',{cache:'no-store'})]);if(!statusResponse.ok||!historyResponse.ok)throw new Error(`Live update failed (${statusResponse.status}/${historyResponse.status})`);const d=await statusResponse.json(),h=await historyResponse.json();document.querySelector('#cards').innerHTML=cards(d);document.querySelector('#containers').innerHTML=containerTable(d.docker);document.querySelector('#history').innerHTML=historyTable(h);document.querySelector('#edge').innerHTML=edgeTable(d.cloudflare);document.querySelector('#loading').classList.add('hidden');document.querySelector('#stamp').textContent=`Live · updated ${new Date(d.generatedAt).toLocaleTimeString()} · ${d.viewer||'Cloudflare Access'}`;}catch(e){document.querySelector('#loading-text').textContent=`Still waiting for live metrics: ${e}`;document.querySelector('#stamp').innerHTML='<span class="error">Live update unavailable</span>'}}refresh();setInterval(refresh,10000);
</script></body></html>'''


class Handler(BaseHTTPRequestHandler):
    def send_body(self, status: int, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        request_url = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(request_url.query)
        if request_url.path == "/":
            self.send_body(200, HTML.encode(), "text/html; charset=utf-8")
        elif request_url.path == "/healthz":
            if history.error:
                self.send_body(
                    503,
                    b'{"ok":false,"history":false}\n',
                    "application/json",
                )
            else:
                self.send_body(
                    200,
                    b'{"ok":true,"history":true}\n',
                    "application/json",
                )
        elif request_url.path == "/metrics":
            self.send_body(
                200,
                prometheus_metrics(),
                "text/plain; version=0.0.4; charset=utf-8",
            )
        elif request_url.path == "/api/history/overview":
            self.send_body(
                200,
                json.dumps(history.overview(), separators=(",", ":")).encode(),
                "application/json",
            )
        elif request_url.path == "/api/history":
            try:
                hours = int(query.get("hours", [str(24 * HISTORY_RETENTION_DAYS)])[0])
            except ValueError:
                self.send_body(400, b'{"error":"hours must be an integer"}\n', "application/json")
                return
            container_name = query.get("container", [""])[0]
            self.send_body(
                200,
                json.dumps(
                    history.series(container_name=container_name, hours=hours),
                    separators=(",", ":"),
                ).encode(),
                "application/json",
            )
        elif request_url.path == "/api/status":
            snapshot = runtime.get()
            payload = {
                "generatedAt": datetime.now(timezone.utc).isoformat(),
                "viewer": self.headers.get(
                    "Cf-Access-Authenticated-User-Email", ""
                ),
                "docker": snapshot["docker"],
                "tunnel": snapshot["tunnel"],
                "cloudflare": analytics.get(),
            }
            self.send_body(
                200,
                json.dumps(payload, separators=(",", ":")).encode(),
                "application/json",
            )
        elif request_url.path == "/api/logs":
            service = query.get("service", [""])[0]
            try:
                tail = int(query.get("tail", ["100"])[0])
            except ValueError:
                tail = 100
            if not service:
                self.send_body(
                    400,
                    json.dumps({"error": "service parameter required"}).encode(),
                    "application/json",
                )
            else:
                logs = get_container_logs(service, tail=tail)
                self.send_body(
                    200,
                    json.dumps({"service": service, "logs": logs}).encode(),
                    "application/json",
                )
        else:
            self.send_body(404, b"not found\n", "text/plain; charset=utf-8")

    def log_message(self, format: str, *args: object) -> None:
        return


if __name__ == "__main__":
    threading.Thread(target=analytics_loop, daemon=True).start()
    threading.Thread(target=history_loop, daemon=True).start()
    ThreadingHTTPServer(("0.0.0.0", int(os.getenv("PORT", "3000"))), Handler).serve_forever()
