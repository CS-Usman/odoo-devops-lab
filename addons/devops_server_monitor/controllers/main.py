# -*- coding: utf-8 -*-

import json

from odoo import http
from odoo.http import request


class DevopsMonitorController(http.Controller):

    @http.route("/devops/health", auth="public", methods=["GET"], csrf=False)
    def health(self):
        """Lightweight health check for CI/CD and uptime monitors."""
        try:
            request.env.cr.execute("SELECT 1")
            db_ok = True
        except Exception:
            db_ok = False
        status = "ok" if db_ok else "critical"
        payload = {
            "status": status,
            "database": "ok" if db_ok else "error",
        }
        code = 200 if db_ok else 503
        return request.make_json_response(payload, status=code)

    @http.route("/devops/metrics", auth="public", methods=["GET"], csrf=False)
    def metrics(self):
        """Full JSON metrics payload for external monitoring / CI smoke tests."""
        Snapshot = request.env["devops.monitor.snapshot"].sudo()
        payload = Snapshot.get_latest_dashboard_payload()
        overall = payload.get("overall_status", "unknown")
        code = 200 if overall in ("ok", "warning") else 503
        return request.make_json_response(payload, status=code)

    @http.route("/devops/metrics/live", auth="user", methods=["GET"], csrf=False)
    def metrics_live(self):
        """Fresh metrics collection without persisting (admin UI refresh)."""
        Collector = request.env["devops.monitor.collector"].sudo()
        metrics = Collector.collect_all_metrics()
        metrics.pop("container_lines", None)
        metrics["collected_at"] = str(metrics.get("collected_at"))
        return request.make_json_response(metrics)
