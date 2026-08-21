# -*- coding: utf-8 -*-
"""Host, database, filestore, and Docker metric collection."""

import json
import logging
import os
import re
import shutil
import subprocess
import time
from datetime import datetime

from odoo import api, models, fields, tools
_logger = logging.getLogger(__name__)

try:
    import psutil

    HAS_PSUTIL = True
except ImportError:
    HAS_PSUTIL = False


class DevopsMonitorCollector(models.AbstractModel):
    _name = "devops.monitor.collector"
    _description = "DevOps Metrics Collector"

    # -------------------------------------------------------------------------
    # Public API
    # -------------------------------------------------------------------------

    @api.model
    def collect_all_metrics(self):
        """Gather every metric bundle used by snapshots and HTTP endpoints."""
        host = self._collect_host_metrics()
        db = self._collect_db_metrics()
        filestore = self._collect_filestore_metrics()
        docker = self._collect_docker_metrics()
        overall = self._compute_overall_status(host, db, filestore, docker)
        return {
            **host,
            **db,
            **filestore,
            "docker_available": docker["docker_available"],
            "container_count": docker["container_count"],
            "container_lines": docker["container_lines"],
            "overall_status": overall,
            "hostname": self._get_hostname(),
            "collected_at": fields.Datetime.now(),
        }

    @api.model
    def cron_collect_snapshot(self):
        """Scheduled job: persist a new snapshot row."""
        MonitorSnapshot = self.env["devops.monitor.snapshot"]
        MonitorSnapshot.create_snapshot_from_collector()
        _logger.info("DevOps monitor snapshot collected on %s", self._get_hostname())
        return True

    # -------------------------------------------------------------------------
    # Host metrics
    # -------------------------------------------------------------------------

    @api.model
    def _collect_host_metrics(self):
        if HAS_PSUTIL:
            return self._collect_host_psutil()
        return self._collect_host_proc()

    @api.model
    def _collect_host_psutil(self):
        cpu_percent = psutil.cpu_percent(interval=0.5)
        mem = psutil.virtual_memory()
        disk = psutil.disk_usage("/")
        load1, load5, load15 = os.getloadavg() if hasattr(os, "getloadavg") else (0.0, 0.0, 0.0)
        net = psutil.net_io_counters()
        disk_io = psutil.disk_io_counters()
        return {
            "cpu_percent": cpu_percent,
            "cpu_count": psutil.cpu_count(logical=True) or 1,
            "memory_total_gb": self._bytes_to_gb(mem.total),
            "memory_used_gb": self._bytes_to_gb(mem.used),
            "memory_percent": mem.percent,
            "disk_total_gb": self._bytes_to_gb(disk.total),
            "disk_used_gb": self._bytes_to_gb(disk.used),
            "disk_percent": disk.percent,
            "load_1": load1,
            "load_5": load5,
            "load_15": load15,
            "network_rx_mb": self._bytes_to_mb(net.bytes_recv),
            "network_tx_mb": self._bytes_to_mb(net.bytes_sent),
            "disk_read_mb": self._bytes_to_mb(disk_io.read_bytes if disk_io else 0),
            "disk_write_mb": self._bytes_to_mb(disk_io.write_bytes if disk_io else 0),
            "host_status": self._status_from_percent(max(cpu_percent, mem.percent, disk.percent)),
        }

    @api.model
    def _collect_host_proc(self):
        """Fallback for environments without psutil (reads /proc on Linux)."""
        mem_total, mem_used, mem_percent = self._read_meminfo()
        disk = shutil.disk_usage("/")
        disk_percent = (disk.used / disk.total * 100) if disk.total else 0.0
        load1, load5, load15 = (0.0, 0.0, 0.0)
        if hasattr(os, "getloadavg"):
            load1, load5, load15 = os.getloadavg()
        rx, tx = self._read_net_dev()
        return {
            "cpu_percent": self._read_cpu_percent(),
            "cpu_count": os.cpu_count() or 1,
            "memory_total_gb": self._bytes_to_gb(mem_total),
            "memory_used_gb": self._bytes_to_gb(mem_used),
            "memory_percent": mem_percent,
            "disk_total_gb": self._bytes_to_gb(disk.total),
            "disk_used_gb": self._bytes_to_gb(disk.used),
            "disk_percent": disk_percent,
            "load_1": load1,
            "load_5": load5,
            "load_15": load15,
            "network_rx_mb": self._bytes_to_mb(rx),
            "network_tx_mb": self._bytes_to_mb(tx),
            "disk_read_mb": 0.0,
            "disk_write_mb": 0.0,
            "host_status": self._status_from_percent(max(mem_percent, disk_percent)),
        }

    # -------------------------------------------------------------------------
    # Database metrics
    # -------------------------------------------------------------------------

    @api.model
    def _collect_db_metrics(self):
        result = {
            "db_status": "unknown",
            "db_latency_ms": 0.0,
            "db_name": self.env.cr.dbname,
            "db_size_mb": 0.0,
            "db_connections": 0,
            "db_message": "",
        }
        start = time.perf_counter()
        try:
            self.env.cr.execute("SELECT 1")
            result["db_latency_ms"] = round((time.perf_counter() - start) * 1000, 2)
            result["db_status"] = "ok"
            result["db_message"] = "PostgreSQL responding"
            if self._is_postgresql():
                self.env.cr.execute(
                    "SELECT pg_database_size(current_database())"
                )
                size = self.env.cr.fetchone()[0]
                result["db_size_mb"] = round(size / (1024 * 1024), 2)
                self.env.cr.execute(
                    """
                    SELECT count(*)
                    FROM pg_stat_activity
                    WHERE datname = current_database()
                    """
                )
                result["db_connections"] = self.env.cr.fetchone()[0]
        except Exception as exc:
            result["db_status"] = "critical"
            result["db_message"] = str(exc)[:255]
            _logger.exception("Database health check failed")
        if result["db_latency_ms"] > 500 and result["db_status"] == "ok":
            result["db_status"] = "warning"
            result["db_message"] = "High database latency"
        return result

    @api.model
    def _is_postgresql(self):
        return self.env.cr._cnx.__class__.__module__.startswith("psycopg2")

    # -------------------------------------------------------------------------
    # Filestore
    # -------------------------------------------------------------------------

    @api.model
    def _collect_filestore_metrics(self):
        path = self._get_filestore_path()
        result = {
            "filestore_path": path or "",
            "filestore_total_gb": 0.0,
            "filestore_used_gb": 0.0,
            "filestore_free_gb": 0.0,
            "filestore_percent": 0.0,
            "filestore_file_count": 0,
            "filestore_status": "unknown",
        }
        if not path or not os.path.isdir(path):
            result["filestore_status"] = "warning"
            result["filestore_path"] = path or "not found"
            return result
        usage = shutil.disk_usage(path)
        result["filestore_total_gb"] = self._bytes_to_gb(usage.total)
        result["filestore_used_gb"] = self._bytes_to_gb(usage.used)
        result["filestore_free_gb"] = self._bytes_to_gb(usage.free)
        result["filestore_percent"] = (usage.used / usage.total * 100) if usage.total else 0.0
        result["filestore_file_count"] = self._count_files_limited(path, limit=5000)
        result["filestore_status"] = self._status_from_percent(result["filestore_percent"])
        return result

    @api.model
    def _get_filestore_path(self):
        dbname = self.env.cr.dbname
        data_dir = tools.config.get("data_dir")
        if not data_dir:
            return ""
        # Standard Odoo layout: data_dir/filestore/<dbname>
        candidate = os.path.join(data_dir, "filestore", dbname)
        if os.path.isdir(candidate):
            return candidate
        store = os.path.join(data_dir, "filestore")
        return store if os.path.isdir(store) else data_dir

    # -------------------------------------------------------------------------
    # Docker
    # -------------------------------------------------------------------------

    @api.model
    def _collect_docker_metrics(self):
        lines = []
        if not self._docker_available():
            return {
                "docker_available": False,
                "container_count": 0,
                "container_lines": lines,
            }
        try:
            proc = subprocess.run(
                [
                    "docker",
                    "stats",
                    "--no-stream",
                    "--format",
                    "{{json .}}",
                ],
                capture_output=True,
                text=True,
                timeout=15,
                check=False,
            )
            if proc.returncode != 0:
                _logger.warning("docker stats failed: %s", proc.stderr)
                return {
                    "docker_available": True,
                    "container_count": 0,
                    "container_lines": lines,
                }
            for row in proc.stdout.splitlines():
                row = row.strip()
                if not row:
                    continue
                try:
                    data = json.loads(row)
                except json.JSONDecodeError:
                    continue
                lines.append({
                    "name": data.get("Name", ""),
                    "container_id": (data.get("ID") or "")[:12],
                    "cpu_percent": self._parse_docker_percent(data.get("CPUPerc")),
                    "memory_used_mb": self._parse_docker_mem_mb(data.get("MemUsage")),
                    "memory_limit_mb": self._parse_docker_mem_mb(
                        data.get("MemUsage"), index=1
                    ),
                    "memory_percent": self._parse_docker_mem_percent(data.get("MemPerc")),
                    "network_io": data.get("NetIO") or "",
                    "block_io": data.get("BlockIO") or "",
                    "pids": int(data.get("PIDs") or 0),
                })
        except (subprocess.TimeoutExpired, FileNotFoundError) as exc:
            _logger.warning("Docker collection error: %s", exc)
        return {
            "docker_available": True,
            "container_count": len(lines),
            "container_lines": lines,
        }

    @api.model
    def _docker_available(self):
        try:
            proc = subprocess.run(
                ["docker", "info"],
                capture_output=True,
                timeout=5,
                check=False,
            )
            return proc.returncode == 0
        except (FileNotFoundError, subprocess.TimeoutExpired):
            return False

    # -------------------------------------------------------------------------
    # Helpers
    # -------------------------------------------------------------------------

    @api.model
    def _compute_overall_status(self, host, db, filestore, docker):
        statuses = [
            host.get("host_status", "unknown"),
            db.get("db_status", "unknown"),
            filestore.get("filestore_status", "unknown"),
        ]
        if statuses.count("critical"):
            return "critical"
        if statuses.count("warning"):
            return "warning"
        if db.get("db_status") == "ok" and host.get("host_status") == "ok":
            return "ok"
        return "unknown"

    @api.model
    def _status_from_percent(self, percent, warn=80.0, critical=90.0):
        if percent >= critical:
            return "critical"
        if percent >= warn:
            return "warning"
        return "ok"

    @api.model
    def _get_hostname(self):
        return os.uname().nodename if hasattr(os, "uname") else "localhost"

    @staticmethod
    def _bytes_to_gb(value):
        return round(value / (1024 ** 3), 2)

    @staticmethod
    def _bytes_to_mb(value):
        return round(value / (1024 ** 2), 2)

    @staticmethod
    def _parse_docker_percent(value):
        if not value:
            return 0.0
        try:
            return float(str(value).replace("%", "").strip())
        except ValueError:
            return 0.0

    @staticmethod
    def _parse_docker_mem_mb(value, index=0):
        if not value:
            return 0.0
        part = str(value).split("/")[index].strip()
        match = re.match(r"([\d.]+)\s*([KMG]?)i?B", part, re.I)
        if not match:
            return 0.0
        num, unit = float(match.group(1)), match.group(2).upper()
        factors = {"": 1 / 1024, "K": 1 / 1024, "M": 1, "G": 1024}
        return round(num * factors.get(unit, 1), 2)

    @staticmethod
    def _parse_docker_mem_percent(value):
        return DevopsMonitorCollector._parse_docker_percent(value)

    @staticmethod
    def _read_meminfo():
        total = used = 0
        try:
            with open("/proc/meminfo", encoding="utf-8") as f:
                info = {}
                for line in f:
                    key, val = line.split(":")
                    info[key.strip()] = int(val.strip().split()[0]) * 1024
            total = info.get("MemTotal", 0)
            available = info.get("MemAvailable", info.get("MemFree", 0))
            used = total - available
        except (OSError, ValueError, KeyError):
            pass
        percent = (used / total * 100) if total else 0.0
        return total, used, percent

    _prev_cpu_times = None

    @classmethod
    def _read_cpu_percent(cls):
        try:
            with open("/proc/stat", encoding="utf-8") as f:
                line = f.readline()
            parts = [int(x) for x in line.split()[1:]]
            idle = parts[3] + (parts[4] if len(parts) > 4 else 0)
            total = sum(parts)
            if cls._prev_cpu_times:
                prev_total, prev_idle = cls._prev_cpu_times
                dt = total - prev_total
                didle = idle - prev_idle
                cls._prev_cpu_times = (total, idle)
                if dt:
                    return round(100.0 * (1.0 - didle / dt), 1)
            cls._prev_cpu_times = (total, idle)
        except (OSError, ValueError, IndexError):
            pass
        return 0.0

    @staticmethod
    def _read_net_dev():
        rx = tx = 0
        try:
            with open("/proc/net/dev", encoding="utf-8") as f:
                for line in f.readlines()[2:]:
                    cols = line.split()
                    if len(cols) >= 10:
                        rx += int(cols[1])
                        tx += int(cols[9])
        except (OSError, ValueError):
            pass
        return rx, tx

    @staticmethod
    def _count_files_limited(path, limit=5000):
        count = 0
        for _root, _dirs, files in os.walk(path):
            count += len(files)
            if count >= limit:
                return limit
        return count
