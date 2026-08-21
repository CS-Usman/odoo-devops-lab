# -*- coding: utf-8 -*-

from odoo import api, fields, models


class DevopsMonitorSnapshot(models.Model):
    _name = "devops.monitor.snapshot"
    _description = "DevOps Server Monitor Snapshot"
    _order = "collected_at desc, id desc"
    _rec_name = "display_name"

    display_name = fields.Char(compute="_compute_display_name", store=True)
    collected_at = fields.Datetime(
        string="Collected At",
        default=fields.Datetime.now,
        required=True,
        index=True,
    )
    hostname = fields.Char(string="Hostname")

    # Overall
    overall_status = fields.Selection(
        [
            ("ok", "Healthy"),
            ("warning", "Warning"),
            ("critical", "Critical"),
            ("unknown", "Unknown"),
        ],
        string="Overall Status",
        default="unknown",
        index=True,
    )

    # Host / CPU / RAM / Load
    host_status = fields.Selection(
        [("ok", "OK"), ("warning", "Warning"), ("critical", "Critical"), ("unknown", "Unknown")],
        string="Host Status",
    )
    cpu_percent = fields.Float(string="CPU %")
    cpu_count = fields.Integer(string="CPU Cores")
    memory_total_gb = fields.Float(string="RAM Total (GB)")
    memory_used_gb = fields.Float(string="RAM Used (GB)")
    memory_percent = fields.Float(string="RAM %")
    load_1 = fields.Float(string="Load 1m")
    load_5 = fields.Float(string="Load 5m")
    load_15 = fields.Float(string="Load 15m")

    # Disk / I/O
    disk_total_gb = fields.Float(string="Disk Total (GB)")
    disk_used_gb = fields.Float(string="Disk Used (GB)")
    disk_percent = fields.Float(string="Root Disk %")
    disk_read_mb = fields.Float(string="Disk Read (MB)")
    disk_write_mb = fields.Float(string="Disk Write (MB)")

    # Network
    network_rx_mb = fields.Float(string="Network RX (MB)")
    network_tx_mb = fields.Float(string="Network TX (MB)")

    # Database
    db_status = fields.Selection(
        [
            ("ok", "OK"),
            ("warning", "Warning"),
            ("critical", "Critical"),
            ("unknown", "Unknown"),
        ],
        string="DB Status",
    )
    db_name = fields.Char(string="Database")
    db_latency_ms = fields.Float(string="DB Latency (ms)")
    db_size_mb = fields.Float(string="DB Size (MB)")
    db_connections = fields.Integer(string="DB Connections")
    db_message = fields.Char(string="DB Message")
    snapshot_count = fields.Integer(compute="_compute_snapshot_count")

    # Filestore
    filestore_status = fields.Selection(
        [("ok", "OK"), ("warning", "Warning"), ("critical", "Critical"), ("unknown", "Unknown")],
        string="Filestore Status",
    )
    filestore_path = fields.Char(string="Filestore Path")
    filestore_total_gb = fields.Float(string="Filestore Disk Total (GB)")
    filestore_used_gb = fields.Float(string="Filestore Used (GB)")
    filestore_free_gb = fields.Float(string="Filestore Free (GB)")
    filestore_percent = fields.Float(string="Filestore %")
    filestore_file_count = fields.Integer(string="Filestore Files (sampled)")

    # Docker
    docker_available = fields.Boolean(string="Docker Available")
    container_count = fields.Integer(string="Container Count")
    container_line_ids = fields.One2many(
        "devops.monitor.container.line",
        "snapshot_id",
        string="Containers",
    )

    notes = fields.Text(string="Notes")

    @api.depends("collected_at", "hostname", "overall_status")
    def _compute_display_name(self):
        for rec in self:
            ts = fields.Datetime.to_string(rec.collected_at) if rec.collected_at else ""
            rec.display_name = f"{rec.hostname or 'server'} @ {ts} [{rec.overall_status or '?'}]"

    @api.depends()
    def _compute_snapshot_count(self):
        total = self.search_count([])
        for rec in self:
            rec.snapshot_count = total

    def action_view_history(self):
        return self.env.ref("devops_server_monitor.action_devops_monitor_history").read()[0]

    def action_open_owl_dashboard(self):
        return {
            "type": "ir.actions.client",
            "tag": "devops_server_monitor.dashboard",
            "name": "Server Health Dashboard",
            "target": "current",
        }

    @api.model
    def _snapshot_io_deltas(self, snapshots, field_name):
        """Convert cumulative I/O counters into per-snapshot deltas for charts."""
        deltas = []
        previous = None
        for snapshot in snapshots:
            value = getattr(snapshot, field_name, 0.0) or 0.0
            if previous is None:
                deltas.append(0.0)
            else:
                deltas.append(round(max(value - previous, 0.0), 2))
            previous = value
        return deltas

    @api.model
    def get_dashboard_chart_data(self, limit=48):
        """Return time-series data for OWL dashboard charts."""
        snapshots = self.search([], limit=limit, order="collected_at asc")
        labels = []
        for snap in snapshots:
            if snap.collected_at:
                labels.append(fields.Datetime.to_string(snap.collected_at)[11:16])
            else:
                labels.append("")
        return {
            "labels": labels,
            "cpu": snapshots.mapped("cpu_percent"),
            "memory": snapshots.mapped("memory_percent"),
            "disk": snapshots.mapped("disk_percent"),
            "db_latency": snapshots.mapped("db_latency_ms"),
            "filestore": snapshots.mapped("filestore_percent"),
            "network_rx": self._snapshot_io_deltas(snapshots, "network_rx_mb"),
            "network_tx": self._snapshot_io_deltas(snapshots, "network_tx_mb"),
            "disk_read": self._snapshot_io_deltas(snapshots, "disk_read_mb"),
            "disk_write": self._snapshot_io_deltas(snapshots, "disk_write_mb"),
            "snapshot_count": self.search_count([]),
        }

    @api.model
    def create_snapshot_from_collector(self):
        metrics = self.env["devops.monitor.collector"].collect_all_metrics()
        container_lines = metrics.pop("container_lines", [])
        snapshot = self.create(metrics)
        if container_lines:
            self.env["devops.monitor.container.line"].create([
                {**line, "snapshot_id": snapshot.id}
                for line in container_lines
            ])
        return snapshot

    def action_collect_now(self):
        """Manual refresh: collect host/DB/docker metrics and save a new snapshot."""
        snapshot = self.create_snapshot_from_collector()
        return self.action_open_owl_dashboard()

    def action_open_dashboard(self):
        latest = self.search([], limit=1, order="id desc")
        if not latest:
            self.create_snapshot_from_collector()
        return self.action_open_owl_dashboard()

    @api.model
    def get_latest_dashboard_payload(self):
        latest = self.search([], limit=1, order="id desc")
        if not latest:
            latest = self.create_snapshot_from_collector()
        return latest._to_dashboard_dict()

    def _to_dashboard_dict(self):
        self.ensure_one()
        return {
            "id": self.id,
            "collected_at": fields.Datetime.to_string(self.collected_at),
            "hostname": self.hostname,
            "overall_status": self.overall_status,
            "host": {
                "status": self.host_status,
                "cpu_percent": self.cpu_percent,
                "cpu_count": self.cpu_count,
                "memory_percent": self.memory_percent,
                "memory_used_gb": self.memory_used_gb,
                "memory_total_gb": self.memory_total_gb,
                "load_1": self.load_1,
                "load_5": self.load_5,
                "load_15": self.load_15,
                "disk_percent": self.disk_percent,
                "disk_used_gb": self.disk_used_gb,
                "disk_total_gb": self.disk_total_gb,
                "network_rx_mb": self.network_rx_mb,
                "network_tx_mb": self.network_tx_mb,
                "disk_read_mb": self.disk_read_mb,
                "disk_write_mb": self.disk_write_mb,
            },
            "database": {
                "status": self.db_status,
                "name": self.db_name,
                "latency_ms": self.db_latency_ms,
                "size_mb": self.db_size_mb,
                "connections": self.db_connections,
                "message": self.db_message,
            },
            "filestore": {
                "status": self.filestore_status,
                "path": self.filestore_path,
                "percent": self.filestore_percent,
                "used_gb": self.filestore_used_gb,
                "free_gb": self.filestore_free_gb,
                "total_gb": self.filestore_total_gb,
                "file_count": self.filestore_file_count,
            },
            "docker": {
                "available": self.docker_available,
                "container_count": self.container_count,
                "containers": [
                    {
                        "name": line.name,
                        "cpu_percent": line.cpu_percent,
                        "memory_percent": line.memory_percent,
                        "memory_used_mb": line.memory_used_mb,
                        "network_io": line.network_io,
                        "block_io": line.block_io,
                    }
                    for line in self.container_line_ids
                ],
            },
        }
