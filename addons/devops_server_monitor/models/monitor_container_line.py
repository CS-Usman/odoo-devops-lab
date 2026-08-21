# -*- coding: utf-8 -*-

from odoo import fields, models


class DevopsMonitorContainerLine(models.Model):
    _name = "devops.monitor.container.line"
    _description = "Docker Container Metric Line"
    _order = "cpu_percent desc, id desc"

    snapshot_id = fields.Many2one(
        "devops.monitor.snapshot",
        string="Snapshot",
        required=True,
        ondelete="cascade",
        index=True,
    )
    name = fields.Char(string="Container", required=True)
    container_id = fields.Char(string="Container ID")
    cpu_percent = fields.Float(string="CPU %")
    memory_used_mb = fields.Float(string="Memory Used (MB)")
    memory_limit_mb = fields.Float(string="Memory Limit (MB)")
    memory_percent = fields.Float(string="Memory %")
    network_io = fields.Char(string="Network I/O")
    block_io = fields.Char(string="Block I/O")
    pids = fields.Integer(string="PIDs")
