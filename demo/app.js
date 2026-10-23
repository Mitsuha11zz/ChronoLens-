const byId = (id) => document.getElementById(id);

const ui = {
  sample: byId("sample-select"),
  file: byId("file-input"),
  dropzone: byId("dropzone"),
  input: byId("jsonl-input"),
  lineCount: byId("line-count"),
  sourceName: byId("source-name"),
  tolerance: byId("tolerance-input"),
  reference: byId("reference-input"),
  analyze: byId("analyze-button"),
  export: byId("export-button"),
  empty: byId("empty-state"),
  view: byId("report-view"),
  verdict: byId("verdict"),
  verdictEyebrow: byId("verdict-eyebrow"),
  verdictTitle: byId("verdict-title"),
  verdictCopy: byId("verdict-copy"),
  verdictMark: byId("verdict-mark"),
  metrics: byId("metric-strip"),
  components: byId("component-grid"),
  timeline: byId("timeline-stack"),
  evidence: byId("evidence-list"),
  inspector: byId("event-inspector"),
  events: byId("event-list"),
  raw: byId("raw-json"),
  toast: byId("toast"),
};

const state = {
  report: null,
  selectedEventId: null,
  toastTimer: null,
};

function element(tag, className = "", text = null) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== null) node.textContent = String(text);
  return node;
}

function showToast(message, kind = "") {
  ui.toast.textContent = message;
  ui.toast.className = `toast is-visible ${kind}`.trim();
  clearTimeout(state.toastTimer);
  state.toastTimer = setTimeout(() => {
    ui.toast.className = "toast";
  }, 3600);
}

function updateLineCount() {
  const value = ui.input.value;
  const rows = value.length === 0 ? 0 : value.replace(/\n$/, "").split(/\r\n|\r|\n/).length;
  ui.lineCount.textContent = `${rows.toLocaleString("zh-CN")} 行`;
}

async function loadSample(sampleId) {
  try {
    const response = await fetch(`/api/sample?id=${encodeURIComponent(sampleId)}`);
    const result = await response.json();
    if (!response.ok) throw new Error(result.error || "样例读取失败");
    ui.input.value = result.jsonl;
    ui.sourceName.textContent = `内置样例 · ${result.label}`;
    updateLineCount();
  } catch (error) {
    showToast(error.message || "无法载入内置样例。", "is-error");
  }
}

function acceptFile(file) {
  if (!file) return;
  if (file.size > 8 * 1024 * 1024) {
    showToast("文件超过 8 MiB 输入上限。", "is-error");
    return;
  }
  file.text().then((text) => {
    ui.input.value = text;
    ui.sourceName.textContent = `本地文件 · ${file.name}`;
    ui.sample.value = "";
    updateLineCount();
  }).catch(() => showToast("文件读取失败。", "is-error"));
}

function formatInteger(value) {
  if (value === null || value === undefined) return "—";
  const raw = String(value);
  const sign = raw.startsWith("-") ? "−" : "";
  const digits = sign ? raw.slice(1) : raw;
  return sign + digits.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

function formatBound(bound, side) {
  if (!bound || bound.kind === "unbounded") return side === "lower" ? "−∞" : "+∞";
  return `${formatInteger(bound.value_us)} µs`;
}

function formatOffset(value) {
  if (value === null || value === undefined) return "—";
  return `${formatInteger(value)} µs`;
}

function statusPresentation(report) {
  if (report.has_conflicts === true) {
    const partial = report.summary?.failed_components > 0;
    return {
      theme: "conflict",
      eyebrow: partial ? "CONFLICT FOUND · PARTIAL READOUT" : "CONSTRAINT CONFLICT",
      title: partial ? "已找到冲突，部分分量未完成。" : "这组时间约束无法同时成立。",
      copy: "负环给出了可复核的矛盾证据。它说明当前假设不兼容，但不会自动判断根因。",
      mark: "×",
    };
  }
  switch (report.status) {
    case "feasible":
      return {
        theme: "feasible",
        eyebrow: "CONSTRAINT SPACE / FEASIBLE",
        title: "存在可行的固定偏移。",
        copy: "求解器返回了一组代表解，并计算每个时钟相对参考时钟的边际范围。",
        mark: "✓",
      };
    case "no_constraints":
      return {
        theme: "incomplete",
        eyebrow: "NO CONSTRAINTS",
        title: "目前没有足够的消息约束。",
        copy: "事件已读取，但没有唯一的一发一收消息对；检查消息标识或补充关联记录。",
        mark: "·",
      };
    case "input_invalid":
      return {
        theme: "incomplete",
        eyebrow: "INPUT / INVALID",
        title: "输入需要先修正。",
        copy: "诊断保留了可用事件预览和字段错误；修正 JSONL 后可以重新运行。",
        mark: "!",
      };
    case "input_limited":
      return {
        theme: "incomplete",
        eyebrow: "INPUT / LIMITED",
        title: "输入扫描触及资源限制。",
        copy: "当前数据不完整，不能据此给出完整的偏移结论。",
        mark: "!",
      };
    case "analysis_incomplete":
    case "pipeline_failed":
      return {
        theme: "incomplete",
        eyebrow: "ANALYSIS / INCOMPLETE",
        title: "分析没有完整结束。",
        copy: "查看各分量状态和阶段错误。未完成的计算不会被解释为无冲突。",
        mark: "…",
      };
    default:
      return {
        theme: "incomplete",
        eyebrow: "DIAGNOSTIC READOUT",
        title: "结果已返回。",
        copy: "检查输入质量、分量状态与报告证据。",
        mark: "·",
      };
  }
}

function renderVerdict(report) {
  const presentation = statusPresentation(report);
  ui.verdict.className = `verdict theme-${presentation.theme}`;
  ui.verdictEyebrow.textContent = presentation.eyebrow;
  ui.verdictTitle.textContent = presentation.title;
  ui.verdictCopy.textContent = presentation.copy;
  ui.verdictMark.textContent = presentation.mark;
}

function renderMetrics(report) {
  ui.metrics.replaceChildren();
  const coverage = report.coverage || {};
  const summary = report.summary || {};
  const stats = summary.stats || {};
  const input = report.input || {};
  const metrics = [
    { label: "输入事件", value: input.accepted_event_count ?? report.events?.length ?? 0, unit: "条" },
    { label: "唯一配对", value: coverage.paired_groups ?? 0, unit: "组" },
    { label: "约束分量", value: summary.component_count ?? report.components?.length ?? 0, unit: "个" },
    { label: "分析约束", value: stats.constraint_count ?? 0, unit: "条" },
  ];
  for (const metric of metrics) {
    const card = element("div", "metric-card");
    card.append(element("span", "metric-label", metric.label));
    const value = element("strong", "metric-value", formatInteger(metric.value));
    value.append(element("small", "metric-unit", metric.unit));
    card.append(value);
    ui.metrics.append(card);
  }

  if (coverage.unresolved_groups > 0 || coverage.log_completeness === "unknown") {
    const note = element("p", "coverage-note");
    if (coverage.unresolved_groups > 0) {
      note.append(element("span", "coverage-alert", `${coverage.unresolved_groups} 组未解决`));
    }
    if (coverage.log_completeness === "unknown") {
      note.append(element("span", "coverage-unknown", "日志完整性未知"));
    }
    ui.metrics.append(note);
  }
}

function componentTitle(component) {
  switch (component.status) {
    case "feasible": return "可行";
    case "infeasible": return "冲突";
    case "failed": return "未完成";
    default: return component.status || "未知";
  }
}

function renderComponents(report) {
  ui.components.replaceChildren();
  const components = report.components || [];
  if (components.length === 0) {
    ui.components.append(element("div", "section-empty", "报告中没有可展示的分量。"));
    return;
  }

  for (const component of components) {
    const card = element("article", `component-card status-${component.status || "unknown"}`);
    const head = element("div", "component-card-head");
    const identity = element("div", "component-identity");
    identity.append(element("span", "component-number", `COMP / ${String(component.component_id ?? "?").padStart(2, "0")}`));
    identity.append(element("strong", "component-reference", component.reference_clock ? `参考 ${component.reference_clock}` : "参考坐标未指定"));
    head.append(identity);
    head.append(element("span", `status-pill status-pill-${component.status || "unknown"}`, componentTitle(component)));
    card.append(head);

    const clocks = component.clock_ids || [];
    const intervals = component.intervals || [];
    const offsets = new Map((component.offsets || []).map((offset) => [offset.clock_id, offset.offset_us]));
    if (intervals.length > 0) {
      const table = element("div", "interval-table");
      const header = element("div", "interval-row interval-head");
      header.append(element("span", "", "时钟"));
      header.append(element("span", "", "偏移范围"));
      header.append(element("span", "", "代表解"));
      table.append(header);
      for (const interval of intervals) {
        const row = element("div", "interval-row");
        row.append(element("span", "clock-name", interval.clock_id));
        row.append(element("span", "interval-value", `${formatBound(interval.lower, "lower")}  —  ${formatBound(interval.upper, "upper")}`));
        row.append(element("span", "offset-value", formatOffset(offsets.get(interval.clock_id))));
        table.append(row);
      }
      card.append(table);
    } else {
      card.append(element("p", "component-note", `${clocks.length} 个时钟 · ${component.stats?.constraint_count ?? 0} 条约束`));
    }

    if (component.status === "infeasible" && component.cycle) {
      const cycleNote = element(
        "div",
        "cycle-summary",
        `负环权重 ${formatOffset(component.cycle.total_weight_us)} · ${component.cycle.constraint_indices?.length ?? 0} 条边`,
      );
      card.append(cycleNote);
    } else if (component.status === "failed" && component.error) {
      card.append(element("p", "component-error", JSON.stringify(component.error)));
    }

    ui.components.append(card);
  }
}

function offsetFor(component, clockId) {
  return (component.offsets || []).find((offset) => offset.clock_id === clockId)?.offset_us;
}

function renderTimeline(report) {
  ui.timeline.replaceChildren();
  const events = report.events || [];
  const feasible = (report.components || []).filter(
    (component) => component.status === "feasible" && Array.isArray(component.offsets),
  );
  if (feasible.length === 0) {
    ui.timeline.append(element("div", "section-empty", "没有完整可行分量，因此不绘制代表时间线。"));
    return;
  }

  for (const component of feasible) {
    const componentEvents = events.filter((event) => component.clock_ids?.includes(event.clock_id));
    const card = element("article", "timeline-card");
    const head = element("div", "timeline-card-head");
    head.append(element("strong", "timeline-component", `分量 ${String(component.component_id).padStart(2, "0")}`));
    head.append(element("span", "timeline-reference", `坐标原点 · ${component.reference_clock}`));
    card.append(head);
    if (componentEvents.length === 0) {
      card.append(element("p", "component-note", "此分量没有事件行可绘制。"));
      ui.timeline.append(card);
      continue;
    }

    const withModelTime = [];
    for (const event of componentEvents) {
      const offset = offsetFor(component, event.clock_id);
      if (offset === undefined) continue;
      try {
        withModelTime.push({ event, modelTime: BigInt(event.ts_us) + BigInt(offset) });
      } catch {
        // Invalid or preview-only timestamps stay visible in the raw event table.
      }
    }
    if (withModelTime.length === 0) {
      card.append(element("p", "component-note", "没有可用于代表时间线的有效事件时间戳。"));
      ui.timeline.append(card);
      continue;
    }

    withModelTime.sort((left, right) => left.modelTime < right.modelTime ? -1 : left.modelTime > right.modelTime ? 1 : 0);
    const minTime = withModelTime[0].modelTime;
    const maxTime = withModelTime[withModelTime.length - 1].modelTime;
    const span = maxTime - minTime;
    const lanes = element("div", "timeline-lanes");
    const markerLimit = 160;
    const visibleItems = withModelTime.length <= markerLimit
      ? withModelTime
      : Array.from({ length: markerLimit }, (_, index) =>
        withModelTime[Math.round(index * (withModelTime.length - 1) / (markerLimit - 1))],
      );

    for (const clockId of component.clock_ids || []) {
      const laneEvents = visibleItems.filter((item) => item.event.clock_id === clockId);
      const allLaneEvents = withModelTime.filter((item) => item.event.clock_id === clockId);
      const lane = element("div", "time-lane");
      const laneHead = element("div", "lane-head");
      laneHead.append(element("strong", "lane-clock", clockId));
      laneHead.append(element("span", "lane-offset", `代表偏移 ${formatOffset(offsetFor(component, clockId))}`));
      lane.append(laneHead);
      const track = element("div", "timeline-track");
      track.setAttribute("role", "group");
      track.setAttribute("aria-label", `${clockId} 时钟的代表时间事件`);

      for (const item of laneEvents) {
        const scaled = span === 0n ? 5000n : ((item.modelTime - minTime) * 10000n) / span;
        const position = Math.max(0, Math.min(100, Number(scaled) / 100));
        const marker = element("button", `event-marker kind-${item.event.kind || "unknown"}`);
        marker.type = "button";
        marker.dataset.eventId = item.event.event_id;
        marker.style.left = `${position}%`;
        marker.setAttribute("aria-label", `${item.event.event_id}, ${item.event.kind}, 原始时间 ${formatOffset(item.event.ts_us)}`);
        marker.title = `${item.event.event_id} · ${item.event.kind} · 原始 ${formatOffset(item.event.ts_us)}`;
        marker.addEventListener("click", () => selectEvent(item.event.event_id, true));
        track.append(marker);
      }
      lane.append(track);
      const axis = element("div", "lane-axis");
      axis.append(element("span", "", `${laneEvents.length} / ${allLaneEvents.length} 条事件`));
      axis.append(element("span", "", `代表坐标 ${formatOffset(minTime)}  →  ${formatOffset(maxTime)}`));
      lane.append(axis);
      lanes.append(lane);
    }
    card.append(lanes);
    if (withModelTime.length > markerLimit) {
      card.append(element("p", "timeline-cap", `时间线均匀抽样显示 ${markerLimit} / ${withModelTime.length} 条事件；完整记录保留在事件表与 JSON 导出中。`));
    }
    ui.timeline.append(card);
  }
}

function eventChip(eventId, label = eventId) {
  const button = element("button", "evidence-event-chip", label);
  button.type = "button";
  button.addEventListener("click", () => selectEvent(eventId, true));
  return button;
}

function renderEvidence(report) {
  ui.evidence.replaceChildren();
  const conflicts = (report.components || []).filter(
    (component) => component.status === "infeasible" && component.cycle,
  );
  const constraints = new Map((report.constraints || []).map((constraint) => [constraint.index, constraint]));
  if (conflicts.length === 0) {
    const copy = report.has_conflicts === null
      ? "当前没有已知负环，但分析未完整结束；不能据此判定无冲突。"
      : "没有发现负环见证。冲突检查覆盖范围以报告状态为准。";
    ui.evidence.append(element("div", "section-empty", copy));
    return;
  }

  for (const component of conflicts) {
    const card = element("article", "evidence-card");
    const head = element("div", "evidence-card-head");
    const label = element("span", "evidence-label", `COMP / ${String(component.component_id).padStart(2, "0")} · NEGATIVE CYCLE`);
    head.append(label);
    head.append(element("strong", "evidence-weight", formatOffset(component.cycle.total_weight_us)));
    card.append(head);

    const edges = element("div", "cycle-edges");
    for (const index of component.cycle.constraint_indices || []) {
      const edge = constraints.get(index);
      if (!edge) continue;
      const row = element("div", "cycle-edge");
      const statement = `offset(${edge.left_clock}) − offset(${edge.right_clock}) ≤ ${formatInteger(edge.upper_bound_us)} µs`;
      row.append(element("code", "edge-equation", statement));
      const origin = edge.origin || {};
      const evidence = edge.evidence || {};
      const sources = element("div", "edge-sources");
      if (origin.kind === "message" || evidence.kind === "message") {
        const sendId = origin.send_event_id || evidence.send_event_id;
        const receiveId = origin.receive_event_id || evidence.receive_event_id;
        if (sendId) sources.append(eventChip(sendId, `↗ ${sendId}`));
        if (receiveId) sources.append(eventChip(receiveId, `↘ ${receiveId}`));
        if (evidence.key) {
          const key = evidence.key;
          sources.append(element("span", "message-key", `${key.trace_id} / ${key.message_id} / #${key.attempt}`));
        }
      } else if (evidence.prior?.label) {
        sources.append(element("span", "message-key", `先验 · ${evidence.prior.label}`));
      }
      sources.append(element("span", "edge-index", `边 ${index}`));
      row.append(sources);
      edges.append(row);
    }
    card.append(edges);
    card.append(element("p", "evidence-foot", "该环证明约束集合不可同时满足；它不保证是最小冲突，也不单独确定根因。"));
    ui.evidence.append(card);
  }
}

function selectedEventMarkup(event) {
  ui.inspector.replaceChildren();
  if (!event) {
    ui.inspector.append(element("span", "inspector-placeholder", "选择一条事件或证据查看字段"));
    return;
  }
  const head = element("div", "inspector-head");
  head.append(element("span", `kind-token kind-${event.kind || "unknown"}`, event.kind || "event"));
  head.append(element("strong", "inspector-id", event.event_id));
  ui.inspector.append(head);
  const fields = element("div", "inspector-fields");
  const source = event.source || {};
  const entries = [
    ["clock_id", event.clock_id],
    ["timestamp", formatOffset(event.ts_us)],
    ["trace_id", event.trace_id],
    ["message_id", event.message_id],
    ["attempt", event.attempt],
    ["source", source.path ? `${source.path}${source.line ? `:${source.line}` : ""}` : "未提供"],
  ];
  for (const [label, value] of entries) {
    const item = element("div", "inspector-field");
    item.append(element("span", "inspector-key", label));
    item.append(element("span", "inspector-value", value ?? "—"));
    fields.append(item);
  }
  ui.inspector.append(fields);
}

function selectEvent(eventId, scrollToEvent = false) {
  state.selectedEventId = eventId;
  const event = (state.report?.events || []).find((item) => item.event_id === eventId);
  selectedEventMarkup(event);
  for (const node of document.querySelectorAll("[data-event-id]")) {
    node.classList.toggle("is-selected", node.dataset.eventId === eventId);
  }
  if (scrollToEvent) {
    const row = [...document.querySelectorAll("[data-event-id]")].find(
      (node) => node.dataset.eventId === eventId && node.classList.contains("event-row"),
    );
    row?.scrollIntoView({ behavior: "smooth", block: "center" });
  }
}

function renderEvents(report) {
  ui.events.replaceChildren();
  const events = [...(report.events || [])];
  if (events.length === 0) {
    ui.events.append(element("div", "section-empty", "没有保留可展示的事件记录。"));
    return;
  }
  events.sort((left, right) => {
    const clock = String(left.clock_id).localeCompare(String(right.clock_id));
    if (clock !== 0) return clock;
    const lineLeft = left.source?.line ?? 0;
    const lineRight = right.source?.line ?? 0;
    return lineLeft - lineRight;
  });

  const maximumRows = 240;
  for (const event of events.slice(0, maximumRows)) {
    const row = element("button", "event-row");
    row.type = "button";
    row.dataset.eventId = event.event_id;
    row.addEventListener("click", () => selectEvent(event.event_id));
    row.append(element("span", `event-kind kind-${event.kind || "unknown"}`, event.kind || "?"));
    row.append(element("span", "event-clock", event.clock_id));
    row.append(element("span", "event-name", event.event_id));
    row.append(element("span", "event-time", formatOffset(event.ts_us)));
    row.append(element("span", "event-source", event.source?.line ? `L${event.source.line}` : "—"));
    ui.events.append(row);
  }
  if (events.length > maximumRows) {
    ui.events.append(element("p", "event-cap", `显示前 ${maximumRows} / ${events.length} 条事件；完整数据保留在 JSON 导出中。`));
  }
  if (state.selectedEventId) selectEvent(state.selectedEventId);
}

function renderReport(report) {
  state.report = report;
  state.selectedEventId = null;
  ui.empty.hidden = true;
  ui.view.hidden = false;
  renderVerdict(report);
  renderMetrics(report);
  renderComponents(report);
  renderTimeline(report);
  renderEvidence(report);
  renderEvents(report);
  selectedEventMarkup(null);
  ui.raw.textContent = JSON.stringify(report, null, 2);
  ui.export.disabled = false;
}

async function runAnalysis() {
  const jsonl = ui.input.value;
  if (!jsonl.trim()) {
    showToast("先载入或粘贴 JSONL 事件。", "is-error");
    ui.input.focus();
    return;
  }
  const tolerance = ui.tolerance.value || "0";
  if (!/^(0|[1-9][0-9]*)$/.test(tolerance)) {
    showToast("关系容差需要是非负整数。", "is-error");
    ui.tolerance.focus();
    return;
  }

  ui.analyze.disabled = true;
  ui.analyze.classList.add("is-running");
  ui.analyze.querySelector(".button-label").textContent = "分析中…";
  ui.analyze.querySelector(".button-glyph").textContent = "◌";
  try {
    const response = await fetch("/api/analyze", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        jsonl,
        relation_tolerance_us: tolerance,
        reference_clock: ui.reference.value.trim(),
      }),
    });
    const result = await response.json();
    if (!response.ok) throw new Error(result.error || "分析请求失败");
    renderReport(result.report);
    const status = result.report.has_conflicts === true
      ? "分析完成：发现约束冲突。"
      : result.report.has_conflicts === false
        ? "分析完成：当前模型下未发现冲突。"
        : "分析返回，但结果不完整。";
    showToast(status, result.report.has_conflicts === true ? "is-warning" : "");
  } catch (error) {
    showToast(error.message || "本机分析失败。", "is-error");
  } finally {
    ui.analyze.disabled = false;
    ui.analyze.classList.remove("is-running");
    ui.analyze.querySelector(".button-label").textContent = "运行约束分析";
    ui.analyze.querySelector(".button-glyph").textContent = "↗";
  }
}

function exportReport() {
  if (!state.report) return;
  const blob = new Blob([`${JSON.stringify(state.report, null, 2)}\n`], {
    type: "application/json;charset=utf-8",
  });
  const url = URL.createObjectURL(blob);
  const anchor = element("a");
  anchor.href = url;
  anchor.download = "chronolens-diagnostic.json";
  document.body.append(anchor);
  anchor.click();
  anchor.remove();
  URL.revokeObjectURL(url);
}

ui.sample.addEventListener("change", () => {
  if (ui.sample.value) loadSample(ui.sample.value);
});
ui.file.addEventListener("change", () => acceptFile(ui.file.files?.[0]));
ui.input.addEventListener("input", updateLineCount);
ui.analyze.addEventListener("click", runAnalysis);
ui.export.addEventListener("click", exportReport);
ui.input.addEventListener("keydown", (event) => {
  if ((event.ctrlKey || event.metaKey) && event.key === "Enter") runAnalysis();
});
ui.dropzone.addEventListener("dragover", (event) => {
  event.preventDefault();
  ui.dropzone.classList.add("is-dragging");
});
ui.dropzone.addEventListener("dragleave", () => ui.dropzone.classList.remove("is-dragging"));
ui.dropzone.addEventListener("drop", (event) => {
  event.preventDefault();
  ui.dropzone.classList.remove("is-dragging");
  acceptFile(event.dataTransfer?.files?.[0]);
});

updateLineCount();
loadSample(ui.sample.value);
