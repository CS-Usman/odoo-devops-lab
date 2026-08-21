# -*- coding: utf-8 -*-
{
    "name": "DevOps Server Monitor",
    "version": "1.2.4",
    "category": "Tools",
    "summary": "Server health dashboard: CPU, RAM, disk, I/O, DB, filestore, Docker containers",
    "description": """
DevOps lab monitoring module for Odoo deployments.

Collects and displays host metrics (CPU, memory, load, disk, network and disk I/O),
PostgreSQL health, Odoo filestore usage, and Docker container stats when available.
Includes JSON endpoints for CI/CD smoke tests and external monitoring.
    """,
    "author": "DevOps Lab",
    "depends": ["base", "web"],
    "data": [
        "security/devops_monitor_security.xml",
        "security/ir.model.access.csv",
        "data/ir_cron.xml",
        "views/monitor_snapshot_views.xml",
        "views/monitor_menus.xml",
    ],
    "external_dependencies": {
        "python": [],
    },
    "installable": True,
    "application": True,
    "license": "LGPL-3",
    "assets": {
        "web.assets_backend": [
            "devops_server_monitor/static/src/dashboard/dashboard.scss",
            "devops_server_monitor/static/src/dashboard/chart_utils.js",
            "devops_server_monitor/static/src/dashboard/mini_chart.js",
            "devops_server_monitor/static/src/dashboard/dashboard.xml",
            "devops_server_monitor/static/src/dashboard/dashboard.js",
        ],
    },
}
