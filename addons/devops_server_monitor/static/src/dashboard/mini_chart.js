/** @odoo-module **/

import { Component } from "@odoo/owl";
import {
    chartAreaPath,
    chartBars,
    chartDonutSegments,
    chartDualLinePaths,
    chartLinePath,
} from "./chart_utils";

export class DevopsMiniChart extends Component {
    static template = "devops_server_monitor.MiniChart";
    static props = {
        type: String,
        values: { optional: true },
        color: { type: String, optional: true },
        fillColor: { type: String, optional: true },
        segments: { optional: true },
        series: { optional: true },
        extraClass: { type: String, optional: true },
        size: { type: String, optional: true },
    };

    get viewBox() {
        return this.props.size === "sm" ? "0 0 64 64" : "0 0 280 72";
    }

    get chartSvgClass() {
        const classes = ["devops-sparkline"];
        if (this.props.size === "sm") {
            classes.push("devops-chart-sm");
        }
        if (this.props.extraClass) {
            classes.push(this.props.extraClass);
        }
        return classes.join(" ");
    }

    get linePath() {
        return chartLinePath(this.props.values);
    }

    get areaPath() {
        return chartAreaPath(this.props.values);
    }

    get bars() {
        return chartBars(this.props.values);
    }

    get dualLines() {
        return chartDualLinePaths(this.props.series || []);
    }

    get donutSegments() {
        if (this.props.size === "sm") {
            return chartDonutSegments(this.props.segments || [], 32, 32, 24, 14);
        }
        return chartDonutSegments(this.props.segments || [], 140, 36, 30, 18);
    }
}
