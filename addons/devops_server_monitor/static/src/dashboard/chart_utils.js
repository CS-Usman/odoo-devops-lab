/** @odoo-module **/

const DEFAULT_WIDTH = 280;
const DEFAULT_HEIGHT = 72;

export function normalizeValues(values) {
    return (values || []).map((v) => Number(v) || 0);
}

export function chartLinePath(values, width = DEFAULT_WIDTH, height = DEFAULT_HEIGHT, maxValue = null) {
    const nums = normalizeValues(values);
    if (!nums.length) {
        return "";
    }
    const max = maxValue !== null ? maxValue : Math.max(...nums, 1);
    const step = nums.length > 1 ? width / (nums.length - 1) : width;
    return nums
        .map((v, i) => {
            const x = Math.round(i * step);
            const y = Math.round(height - (v / max) * (height - 8) - 4);
            return `${i === 0 ? "M" : "L"}${x},${y}`;
        })
        .join(" ");
}

export function chartDualLinePaths(series, width = DEFAULT_WIDTH, height = DEFAULT_HEIGHT) {
    const allValues = series.flatMap((s) => normalizeValues(s.values));
    const max = Math.max(...allValues, 1);
    return series.map((s) => ({
        d: chartLinePath(s.values, width, height, max),
        color: s.color,
        dotted: Boolean(s.dotted),
        label: s.label || "",
    }));
}

export function chartAreaPath(values, width = DEFAULT_WIDTH, height = DEFAULT_HEIGHT) {
    const line = chartLinePath(values, width, height);
    if (!line) {
        return "";
    }
    const nums = normalizeValues(values);
    const step = nums.length > 1 ? width / (nums.length - 1) : width;
    const lastX = Math.round((nums.length - 1) * step);
    return `${line} L${lastX},${height - 4} L0,${height - 4} Z`;
}

export function chartBars(values, width = DEFAULT_WIDTH, height = DEFAULT_HEIGHT) {
    const nums = normalizeValues(values);
    if (!nums.length) {
        return [];
    }
    const max = Math.max(...nums, 1);
    const gap = 3;
    const barWidth = Math.max((width - gap * (nums.length + 1)) / nums.length, 4);
    return nums.map((v, i) => {
        const barHeight = Math.max(((v / max) * (height - 12)), v > 0 ? 3 : 0);
        return {
            x: gap + i * (barWidth + gap),
            y: height - 4 - barHeight,
            width: barWidth,
            height: barHeight,
        };
    });
}

export function chartDonutSegments(segments, cx, cy, outerR, innerR) {
    const total = segments.reduce((sum, seg) => sum + (Number(seg.value) || 0), 0);
    if (total <= 0) {
        return [{
            d: describeArc(cx, cy, outerR, innerR, 0, 359.99),
            color: "#dee2e6",
        }];
    }
    let angle = -90;
    return segments.map((seg) => {
        const value = Number(seg.value) || 0;
        const sweep = (value / total) * 360;
        const start = angle;
        const end = angle + sweep;
        angle = end;
        return {
            d: describeArc(cx, cy, outerR, innerR, start, end),
            color: seg.color,
            label: seg.label,
        };
    });
}

function polar(cx, cy, radius, angleDeg) {
    const rad = ((angleDeg - 90) * Math.PI) / 180;
    return {
        x: cx + radius * Math.cos(rad),
        y: cy + radius * Math.sin(rad),
    };
}

function describeArc(cx, cy, outerR, innerR, startAngle, endAngle) {
    const start = polar(cx, cy, outerR, endAngle);
    const end = polar(cx, cy, outerR, startAngle);
    const innerStart = polar(cx, cy, innerR, endAngle);
    const innerEnd = polar(cx, cy, innerR, startAngle);
    const largeArc = endAngle - startAngle <= 180 ? 0 : 1;
    return [
        `M ${start.x} ${start.y}`,
        `A ${outerR} ${outerR} 0 ${largeArc} 0 ${end.x} ${end.y}`,
        `L ${innerEnd.x} ${innerEnd.y}`,
        `A ${innerR} ${innerR} 0 ${largeArc} 1 ${innerStart.x} ${innerStart.y}`,
        "Z",
    ].join(" ");
}
