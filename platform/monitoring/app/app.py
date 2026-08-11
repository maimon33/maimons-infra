#!/usr/bin/env python3
"""Tiny read-only dashboard for Docker and Cloudflare health."""

from __future__ import annotations

import json
import os
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
CLOUDFLARE_QUERY = """
query ZoneTraffic($zoneTag: string, $filter: filter) {
  viewer {
    zones(filter: {zoneTag: $zoneTag}) {
      traffic: httpRequestsAdaptiveGroups(limit: 1000, filter: $filter) {
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
        "memoryLimitBytes": memory.get("limit", 0),
        "rxBytes": rx_bytes,
        "txBytes": tx_bytes,
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
                    }
                )
        results.sort(key=lambda item: (item["state"] != "running", item["name"]))
        return {"ok": True, "containers": results}
    except (OSError, ValueError, KeyError) as error:
        return {"ok": False, "error": str(error), "containers": []}


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
            with urllib.request.urlopen(request, timeout=30) as response:
                result = json.load(response)
            if result.get("errors"):
                raise RuntimeError(str(result["errors"]))
            groups = result["data"]["viewer"]["zones"][0]["traffic"]
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


def demo_status(kind: str) -> dict[str, Any]:
    """Return stable example data for visual review without infrastructure."""
    incident = kind == "incident"
    containers = [
        {
            "id": "17d6ab126d8f",
            "name": "mosar-app",
            "image": "123456789.dkr.ecr.eu-central-1.amazonaws.com/mosar:8f31a2c",
            "state": "running",
            "status": "Up 9 days (healthy)",
            "cpuPercent": 6.4,
            "memoryBytes": 482344960,
            "memoryLimitBytes": 2147483648,
            "rxBytes": 940572671,
            "txBytes": 3156214012,
        },
        {
            "id": "38e3c46aa7c1",
            "name": "mosar-worker",
            "image": "123456789.dkr.ecr.eu-central-1.amazonaws.com/mosar:8f31a2c",
            "state": "running",
            "status": "Up 9 days",
            "cpuPercent": 2.1,
            "memoryBytes": 218103808,
            "memoryLimitBytes": 1073741824,
            "rxBytes": 182935611,
            "txBytes": 284109348,
        },
        {
            "id": "b31c1c952d72",
            "name": "platform-monitoring",
            "image": "maimons-monitor:8f31a2c",
            "state": "running",
            "status": "Up 4 hours (healthy)",
            "cpuPercent": 0.3,
            "memoryBytes": 32715571,
            "memoryLimitBytes": 536870912,
            "rxBytes": 28733102,
            "txBytes": 8440119,
        },
    ]
    if incident:
        containers[0].update(
            {
                "state": "exited",
                "status": "Exited (137) 3 minutes ago",
                "cpuPercent": None,
                "memoryBytes": None,
                "memoryLimitBytes": None,
                "rxBytes": None,
                "txBytes": None,
            }
        )
        containers[1].update(
            {
                "cpuPercent": 87.2,
                "memoryBytes": 1009317314,
            }
        )

    return {
        "demo": kind,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "viewer": "operator@example.com",
        "docker": {"ok": True, "containers": containers},
        "tunnel": {
            "ok": True,
            "connections": 2 if incident else 4,
            "activeStreams": 3 if incident else 18,
            "totalRequests": 184021,
            "requestErrors": 327 if incident else 12,
            "heartbeatRetries": 41 if incident else 0,
        },
        "cloudflare": {
            "ok": True,
            "configured": True,
            "zone": "maimons.dev",
            "updatedAt": datetime.now(timezone.utc).isoformat(),
            "hostnames": [
                {
                    "hostname": "mosar.maimons.dev",
                    "requests": 82741,
                    "visits": 6390,
                    "bytes": 4831838208,
                },
                {
                    "hostname": "monitor.maimons.dev",
                    "requests": 1934,
                    "visits": 124,
                    "bytes": 84211734,
                },
            ],
        },
    }


def analytics_loop() -> None:
    while True:
        analytics.refresh()
        time.sleep(300)


HTML = r'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Maimons Monitor</title>
<style>
:root{color-scheme:dark;--bg:#0b1017;--panel:#121a24;--line:#223044;--text:#e9f0f7;--muted:#8998aa;--green:#45d483;--red:#ff6978;--blue:#58a6ff;--orange:#ffad45}*{box-sizing:border-box}body{margin:0;background:radial-gradient(circle at 15% 0,#132238 0,transparent 30%),var(--bg);color:var(--text);font:14px ui-sans-serif,system-ui,-apple-system,sans-serif}main{max-width:1200px;margin:auto;padding:32px 20px 60px}header{display:flex;justify-content:space-between;align-items:flex-end;margin-bottom:14px}h1{font-size:25px;margin:0 0 5px;letter-spacing:-.02em}h2{font-size:15px;margin:0 0 14px}.muted{color:var(--muted)}nav{display:flex;gap:6px;margin-bottom:20px}nav a{color:var(--muted);text-decoration:none;border:1px solid var(--line);border-radius:7px;padding:6px 9px;font-size:12px}nav a:hover,nav a.active{color:var(--text);border-color:#3d5472;background:#172234}.demo{display:none;border:1px solid #59441c;background:#2a2112;color:#ffd17a;border-radius:9px;padding:9px 12px;margin-bottom:14px}.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin-bottom:24px}.card,.section{background:rgba(18,26,36,.92);border:1px solid var(--line);border-radius:12px}.card{padding:16px}.card.bad{border-color:#692b37;background:rgba(53,20,28,.94)}.card.bad .value{color:var(--red)}.label{color:var(--muted);font-size:12px}.value{font-size:27px;font-weight:650;margin-top:8px}.section{padding:18px;margin-bottom:16px;overflow:auto}.row{display:flex;gap:8px;align-items:center}.dot{width:8px;height:8px;border-radius:50%;background:var(--green)}.dot.bad{background:var(--red)}table{border-collapse:collapse;width:100%;min-width:720px}th,td{text-align:left;padding:11px 8px;border-top:1px solid var(--line)}th{color:var(--muted);font-size:11px;text-transform:uppercase;letter-spacing:.06em}code{font-family:ui-monospace,SFMono-Regular,monospace;font-size:12px;color:#b9c7d7}.bar{height:5px;background:#233044;border-radius:4px;overflow:hidden;margin-top:5px;width:110px}.bar i{display:block;height:100%;background:var(--blue);border-radius:4px}.error{color:var(--red)}.pill{padding:3px 7px;border-radius:20px;background:#153421;color:var(--green);font-size:11px}.pill.bad{background:#3a1a21;color:var(--red)}@media(max-width:760px){.grid{grid-template-columns:repeat(2,1fr)}header{align-items:flex-start;flex-direction:column;gap:8px}}</style>
</head><body><main><header><div><h1>Maimons Monitor</h1><div class="muted">Docker runtime and Cloudflare edge, without the control-plane clutter.</div></div><div id="stamp" class="muted">Loading…</div></header>
<nav><a href="/">Live</a><a href="/?demo=healthy">Healthy example</a><a href="/?demo=incident">Incident example</a></nav><div class="demo" id="demo"></div><div class="grid" id="cards"></div><section class="section"><h2>Containers</h2><div id="containers"></div></section><section class="section"><h2>Cloudflare edge — trailing 24 hours</h2><div id="edge"></div></section></main>
<script>
const demo=new URLSearchParams(location.search).get('demo');document.querySelectorAll('nav a').forEach(a=>{if(a.href===location.href)a.classList.add('active')});if(demo){const banner=document.querySelector('#demo');banner.style.display='block';banner.textContent=`Example data · ${demo==='incident'?'Degraded incident state':'Healthy platform state'}`}
const fmt=n=>new Intl.NumberFormat().format(Math.round(n||0)); const bytes=n=>{if(!n)return '0 B';const u=['B','KB','MB','GB','TB'],i=Math.min(Math.floor(Math.log(n)/Math.log(1024)),4);return `${(n/1024**i).toFixed(i?1:0)} ${u[i]}`};
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function cards(d){const t=d.tunnel||{}, c=d.docker?.containers||[], running=c.filter(x=>x.state==='running').length, a=d.cloudflare?.hostnames||[], requests=a.reduce((n,x)=>n+x.requests,0), visits=a.reduce((n,x)=>n+x.visits,0), volume=a.reduce((n,x)=>n+x.bytes,0),items=[['Tunnel',t.ok?`${fmt(t.connections)} connections`:'Unavailable',!t.ok||t.connections<4],['Containers',`${running} / ${c.length} running`,running<c.length],['Tunnel traffic',`${fmt(t.totalRequests)} requests`,false],['Tunnel errors',fmt(t.requestErrors),t.requestErrors>50],['Edge requests',`${fmt(requests)} · 24h`,false],['Visits',`${fmt(visits)} · ${bytes(volume)}`,false]];return items.map(([l,v,bad])=>`<div class="card ${bad?'bad':''}"><div class="label">${l}</div><div class="value">${v}</div></div>`).join('')}
function containerTable(d){if(!d.ok)return `<div class="error">${esc(d.error)}</div>`;if(!d.containers.length)return '<div class="muted">No containers found.</div>';return `<table><thead><tr><th>Status</th><th>Container</th><th>CPU</th><th>Memory</th><th>Network</th><th>Image</th></tr></thead><tbody>${d.containers.map(x=>{const mem=x.memoryLimitBytes?x.memoryBytes/x.memoryLimitBytes*100:0;return `<tr><td><span class="pill ${x.state==='running'?'':'bad'}">${esc(x.state)}</span></td><td><strong>${esc(x.name)}</strong><div class="muted">${esc(x.status)}</div></td><td>${x.cpuPercent==null?'—':x.cpuPercent.toFixed(1)+'%'}</td><td>${x.memoryBytes==null?'—':bytes(x.memoryBytes)}<div class="bar"><i style="width:${Math.min(mem,100)}%"></i></div></td><td>${x.rxBytes==null?'—':`↓ ${bytes(x.rxBytes)} · ↑ ${bytes(x.txBytes)}`}</td><td><code>${esc(x.image)}</code></td></tr>`}).join('')}</tbody></table>`}
function edgeTable(d){if(!d.configured)return '<div class="muted">Add the read-only Cloudflare analytics token and zone ID to enable edge analytics.</div>';if(!d.ok)return `<div class="error">${esc(d.error)}</div>`;if(!d.hostnames.length)return '<div class="muted">No matching hostname traffic in the last 24 hours.</div>';return `<table><thead><tr><th>Hostname</th><th>Requests</th><th>Visits</th><th>Edge volume</th></tr></thead><tbody>${d.hostnames.map(x=>`<tr><td><strong>${esc(x.hostname)}</strong></td><td>${fmt(x.requests)}</td><td>${fmt(x.visits)}</td><td>${bytes(x.bytes)}</td></tr>`).join('')}</tbody></table>`}
async function refresh(){try{const endpoint=demo?`/api/status?demo=${encodeURIComponent(demo)}`:'/api/status',r=await fetch(endpoint,{cache:'no-store'}),d=await r.json();document.querySelector('#cards').innerHTML=cards(d);document.querySelector('#containers').innerHTML=containerTable(d.docker);document.querySelector('#edge').innerHTML=edgeTable(d.cloudflare);document.querySelector('#stamp').textContent=`Updated ${new Date(d.generatedAt).toLocaleTimeString()} · ${d.viewer||'Cloudflare Access'}`;}catch(e){document.querySelector('#stamp').innerHTML=`<span class="error">${esc(e)}</span>`}}refresh();if(!demo)setInterval(refresh,10000);
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
            self.send_body(200, b'{"ok":true}\n', "application/json")
        elif request_url.path == "/api/status":
            demo = query.get("demo", [""])[0]
            if demo in {"healthy", "incident"}:
                payload = demo_status(demo)
            else:
                payload = {
                    "generatedAt": datetime.now(timezone.utc).isoformat(),
                    "viewer": self.headers.get(
                        "Cf-Access-Authenticated-User-Email", ""
                    ),
                    "docker": collect_docker(),
                    "tunnel": collect_tunnel(),
                    "cloudflare": analytics.get(),
                }
            self.send_body(
                200,
                json.dumps(payload, separators=(",", ":")).encode(),
                "application/json",
            )
        else:
            self.send_body(404, b"not found\n", "text/plain; charset=utf-8")

    def log_message(self, format: str, *args: object) -> None:
        return


if __name__ == "__main__":
    threading.Thread(target=analytics_loop, daemon=True).start()
    ThreadingHTTPServer(("0.0.0.0", int(os.getenv("PORT", "3000"))), Handler).serve_forever()
