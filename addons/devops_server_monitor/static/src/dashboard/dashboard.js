/** @odoo-module **/

import { registry } from "@web/core/registry";
import { Component, onWillStart, useState } from "@odoo/owl";
import { useService } from "@web/core/utils/hooks";
import { DevopsMiniChart } from "./mini_chart";

const STATUS_CLASS = {
    ok: "devops-status-ok",
    warning: "devops-status-warning",
    critical: "devops-status-critical",
    unknown: "devops-status-unknown",
};

const CHART_COLORS = {
    cpu: "#0d6efd",
    memory: "#6610f2",
    disk: "#fd7e14",
    db: "#198754",
    networkRx: "#20c997",
    networkTx: "#0dcaf0",
    diskRead: "#6f42c1",
    diskWrite: "#d63384",
    filestore: "#ffc107",
};

export class DevopsMonitorDashboard extends Component {
    static components = { DevopsMiniChart };

    chartColors = CHART_COLORS;

    setup() {
        this.orm = useService("orm");
        this.action = useService("action");
        this.notification = useService("notification");
        this.state = useState({
            loading: true,
            refreshing: false,
            data: null,
            charts: null,
        });
        onWillStart(() => this.loadData());
    }

    get statusClass() {
        const status = this.state.data?.overall_status || "unknown";
        return STATUS_CLASS[status] || STATUS_CLASS.unknown;
    }

    get memoryDonutSegments() {
        return this.utilizationSegments(this.state.data?.host?.memory_percent, CHART_COLORS.memory);
    }

    get diskDonutSegments() {
        return this.utilizationSegments(this.state.data?.host?.disk_percent, CHART_COLORS.disk);
    }

    get cpuDonutSegments() {
        return this.utilizationSegments(this.state.data?.host?.cpu_percent, CHART_COLORS.cpu);
    }

    get filestoreDonutSegments() {
        return this.utilizationSegments(this.state.data?.filestore?.percent, CHART_COLORS.filestore);
    }

    get resourceMixSegments() {
        const host = this.state.data?.host || {};
        return [
            { value: host.cpu_percent || 0, color: CHART_COLORS.cpu, label: "CPU" },
            { value: host.memory_percent || 0, color: CHART_COLORS.memory, label: "Memory" },
            { value: host.disk_percent || 0, color: CHART_COLORS.disk, label: "Disk" },
        ];
    }

    get diskIoSeries() {
        const charts = this.state.charts || {};
        return [
            {
                values: charts.disk_read || [],
                color: CHART_COLORS.diskRead,
                label: "Read",
            },
            {
                values: charts.disk_write || [],
                color: CHART_COLORS.diskWrite,
                label: "Write",
                dotted: true,
            },
        ];
    }

    utilizationSegments(percent, usedColor, freeColor = "#e9ecef") {
        const used = Math.min(Math.max(Number(percent) || 0, 0), 100);
        return [
            { value: used, color: usedColor, label: "Used" },
            { value: 100 - used, color: freeColor, label: "Free" },
        ];
    }

    formatPercent(value) {
        return `${(value || 0).toFixed(1)}%`;
    }

    formatMb(value) {
        return `${(value || 0).toFixed(2)} MB`;
    }

    async loadData() {
        this.state.loading = !this.state.data;
        try {
            let payload = await this.orm.call(
                "devops.monitor.snapshot",
                "get_latest_dashboard_payload",
                []
            );
            const charts = await this.orm.call(
                "devops.monitor.snapshot",
                "get_dashboard_chart_data",
                []
            );
            this.state.data = payload;
            this.state.charts = charts;
        } finally {
            this.state.loading = false;
            this.state.refreshing = false;
        }
    }

    async onRefreshMetrics() {
        this.state.refreshing = true;
        try {
            await this.orm.call(
                "devops.monitor.snapshot",
                "create_snapshot_from_collector",
                []
            );
            this.notification.add("Metrics collected and saved to history.", {
                type: "success",
            });
            await this.loadData();
        } catch (error) {
            this.notification.add("Failed to collect metrics.", { type: "danger" });
            this.state.refreshing = false;
            throw error;
        }
    }

    async openHistory() {
        this.action.doAction("devops_server_monitor.action_devops_monitor_history");
    }
}

DevopsMonitorDashboard.template = "devops_server_monitor.Dashboard";

registry.category("actions").add("devops_server_monitor.dashboard", DevopsMonitorDashboard);
