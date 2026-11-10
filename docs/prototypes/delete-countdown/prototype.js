"use strict";

// Only this study's in-memory fixture is changed. No filesystem or shell access.
const icons = {
  folder: '<path d="M2.5 5.5h5l1.5 2H21v11a1 1 0 0 1-1 1H3.5a1 1 0 0 1-1-1z"/>',
  file: '<path d="M6 2.5h8l4 4v15H6zM14 2.5v5h4"/>',
  code: '<path d="M6 2.5h8l4 4v15H6zM14 2.5v5h4m-8 3.5-2 2.5 2 2.5m4-5 2 2.5-2 2.5"/>',
  parent: '<path d="m7 8 5-5 5 5M12 3v13a4 4 0 0 0 4 4h4"/>',
  right: '<path d="m9 5 7 7-7 7"/>',
  down: '<path d="M12 4v16m-5-5 5 5 5-5"/>',
  plus: '<path d="M12 4v16M4 12h16"/>',
  search: '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/>',
  menu: '<circle cx="5" cy="12" r=".7"/><circle cx="12" cy="12" r=".7"/><circle cx="19" cy="12" r=".7"/>',
  trash: '<path d="M3 6h18M9 6V3h6v3M6 6l1 15h10l1-15M10 10v7m4-7v7"/>',
  check: '<circle cx="12" cy="12" r="9"/><path d="m8 12 3 3 5-6"/>',
  undo: '<path d="m7 4-5 5 5 5M2 9h12a7 7 0 0 1 0 14"/>',
};
const icon = name => `<svg viewBox="0 0 24 24" aria-hidden="true">${icons[name] ?? icons.file}</svg>`;
const $ = selector => document.querySelector(selector);
const $$ = selector => [...document.querySelectorAll(selector)];
const escapeHtml = value => String(value).replace(/[&<>"']/g, char => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
})[char]);
const folder = name => ({ name, kind: "folder", size: "Folder", date: "Oct 30, 13:33", permissions: "rwx------" });
const file = (name, size, kind = "file") => ({ name, size, kind, date: "Nov 1, 23:15", permissions: "rw-r--r--" });
const fixtures = {
  left: ["English", "System", "Русский", "Downloads", "Photo", "screens", "Dropbox PocketBook", "Notes", "SendToPb", "My pictures", "applications", "news", "Audio Books", "Music"].map(folder),
  right: [file("afrog.proto", "8.4 KB"), file("afrog_grpc.pb.go", "19 KB", "code"), file("generate.go", "408 B", "code"), file("afrog.pb.go", "126 KB", "code")],
};
const parent = { name: "..", kind: "parent", size: "", date: "", permissions: "" };
const variants = {
  card: { letter: "A", name: "Карточка в исходной панели", description: "Внутри панели, из которой запущено удаление." },
  strip: { letter: "B", name: "Полоса внизу", description: "Широкая линия времени и заметная кнопка Cancel." },
  details: { letter: "C", name: "Карточка со списком", description: "Видны конкретные файлы, папка и время до удаления." },
};
const scenarios = {
  one: { side: "right", names: ["afrog.proto"], noun: "file", path: "~/Downloads/afrog/proto/afrog/v1" },
  three: { side: "right", names: ["afrog.proto", "afrog_grpc.pb.go", "afrog.pb.go"], noun: "files", path: "~/Downloads/afrog/proto/afrog/v1" },
  folder: { side: "left", names: ["Photo"], noun: "folder", path: "~/Downloads/pocketbook" },
};
const query = new URLSearchParams(location.search);
const state = {
  variant: Object.hasOwn(variants, query.get("variant")) ? query.get("variant") : "card",
  scenario: Object.hasOwn(scenarios, query.get("scenario")) ? query.get("scenario") : "three",
  seconds: [3, 5, 8].includes(Number(query.get("delay"))) ? Number(query.get("delay")) : 5,
  theme: query.get("theme") === "dark" ? "dark" : "light",
  phase: "preview",
  active: "right",
  batch: null,
  removed: { left: new Set(), right: new Set() },
  selected: { left: new Set(), right: new Set() },
  cursor: { left: "Photo", right: "afrog.proto" },
  remaining: 5,
  deadline: 0,
  frame: null,
  examples: query.has("examples"),
  lifecycle: query.has("lifecycle"),
};
const rowsFor = side => [parent, ...fixtures[side].filter(row => !state.removed[side].has(row.name))];
const batchLabel = () => `${state.batch.names.length} ${state.batch.noun}`;
const pending = () => state.phase === "preview" || state.phase === "waiting";

function paneMarkup(side, windowId) {
  const path = side === "left" ? ["Downloads", "pocketbook"] : ["Downloads", "afrog", "proto", "afrog", "v1"];
  return `<section class="pane" data-pane="${side}" aria-label="${side === "left" ? "Левая" : "Правая"} файловая панель">
    <header class="pane-toolbar">
      ${side === "left" ? '<div class="traffic-lights" aria-hidden="true"><i></i><i></i><i></i></div>' : ""}
      <div class="breadcrumbs">${path.map((part, index) => `${index ? icon("right") : ""}<span class="crumb${index === path.length - 1 ? " current" : ""}">${part}</span>`).join("")}</div>
      <div class="toolbar-actions"><span class="sort-label">Modified ${icon("down")}</span><span class="command-button">${icon("search")}<span class="control-label">Commands</span></span><span class="toolbar-icon">${icon("menu")}</span></div>
    </header>
    <div class="tabs-bar"><span class="tab" aria-selected="true">${icon("folder")}<span>${path.at(-1)}</span></span><span class="add-tab" aria-hidden="true">${icon("plus")}</span></div>
    <div class="column-head" aria-hidden="true"><span>Name</span><span class="size">Size</span><span class="date modified">Modified ${icon("down")}</span><span class="permissions">Permissions</span></div>
    <div class="file-list" data-list="${side}" id="${windowId}-${side}" tabindex="0" role="grid" aria-label="${side === "left" ? "Левая" : "Правая"} панель: файлы" aria-multiselectable="true"></div>
    <footer class="pane-status"><span class="mode-badge">NORMAL</span><span class="status-name"></span><span class="status-count"></span></footer>
  </section>`;
}

function createWindow(variant, windowId) {
  const window = document.createElement("section");
  window.className = "ferryx-window";
  window.dataset.variant = "frame";
  window.dataset.presentation = variant;
  window.dataset.window = windowId;
  window.setAttribute("aria-label", "Ferryx: удаление с возможностью отмены");
  window.innerHTML = `<div class="workspace">${paneMarkup("left", windowId)}<div class="panel-divider" aria-hidden="true"></div>${paneMarkup("right", windowId)}</div>
    <footer class="key-hints"><div class="hint-group"><span class="hint"><kbd class="typed">D</kbd> Move to Trash</span><span class="hint"><kbd>Esc</kbd> Cancel pending deletion</span><span class="hint"><kbd>Tab</kbd> Change Panel</span></div><span class="hint help-hint">Shortcuts <kbd>⌘/</kbd></span></footer>`;
  return window;
}

function noticeMarkup(presentation, phase = state.phase) {
  const count = batchLabel();
  if (phase === "cancelled" || phase === "done" || phase === "restored") {
    const done = phase === "done";
    const restored = phase === "restored";
    return `<div class="notice-heading"><span class="notice-icon">${icon(done ? "trash" : restored ? "undo" : "check")}</span><strong class="notice-title">${done ? `Moved ${count} to Trash` : restored ? "Restored from Trash" : "Deletion cancelled"}</strong><button class="notice-action" data-action="${done ? "undo" : "replay"}">${done ? "Undo" : "Repeat"}</button></div>
      <div class="notice-caption">${done ? "The countdown finished. Files are now in Trash." : restored ? "Files have been returned to their original location." : "All files are still in their original location."}</div>`;
  }
  const description = `<span class="countdown-label">Starts in <span data-seconds>${Math.ceil(state.remaining)}</span>s</span><span class="separator">·</span>Nothing deleted yet`;
  const line = '<div class="countdown-track" role="img" aria-label="Оставшееся время до начала удаления"><div class="countdown-line"></div></div>';
  const cancel = '<button class="notice-action" data-action="cancel" title="Cancel pending deletion · Esc">Cancel</button>';
  if (presentation === "details") {
    return `<div class="notice-heading"><span class="notice-icon">${icon("trash")}</span><strong class="notice-title">Move ${count} to Trash</strong><span class="notice-tag">Pending</span></div>
      <div class="notice-path">${escapeHtml(state.batch.path)}</div>
      <ul class="notice-files">${state.batch.names.slice(0, 3).map(name => `<li>${icon(state.batch.noun === "folder" ? "folder" : "file")}<span>${escapeHtml(name)}</span></li>`).join("")}${state.batch.names.length > 3 ? `<li>+${state.batch.names.length - 3} more</li>` : ""}</ul>
      <div class="notice-caption">${description}</div>${line}
      <div class="notice-bottom"><span class="notice-shortcut"><kbd>Esc</kbd> cancels</span>${cancel}</div>`;
  }
  if (presentation === "strip") {
    return `<div class="notice-heading"><span class="notice-icon">${icon("trash")}</span><strong class="notice-title">Move ${count} to Trash</strong><span class="notice-caption">${description}</span>${cancel}</div>${line}`;
  }
  return `<div class="notice-heading"><span class="notice-icon">${icon("trash")}</span><strong class="notice-title">Move ${count} to Trash</strong>${cancel}</div><div class="notice-caption">${description}</div>${line}`;
}

function renderStage() {
  const stage = $("#stage");
  stage.replaceChildren();
  if (state.lifecycle) {
    for (const [phase, title, caption] of [
      ["preview", "1. Идёт отсчёт → Cancel", "Файлы на месте. Cancel отменяет запланированное удаление целиком."],
      ["cancelled", "2. Нажали Cancel", "Удаление не запускалось. Файлы остались в исходной папке."],
      ["done", "3. Дождались конца → Undo", "В примере файлы уже перемещены в корзину. Undo возвращает их обратно."],
    ]) {
      const step = document.createElement("section");
      step.className = "lifecycle-step";
      step.innerHTML = `<h2>${title}</h2><div class="delete-notice" data-phase="${phase}" style="--time-left: .6">${noticeMarkup("card", phase)}</div><p>${caption}</p>`;
      stage.append(step);
    }
    return;
  }
  if (state.examples) {
    for (const [name, variant] of Object.entries(variants)) {
      const card = document.createElement("section");
      card.className = "example-card";
      card.innerHTML = `<header class="example-heading"><span class="example-letter">${variant.letter}</span><strong>${variant.name}</strong><p>${variant.description}</p></header>`;
      card.append(createWindow(name, name));
      stage.append(card);
    }
  } else {
    stage.append(createWindow(state.variant, "main"));
  }
  renderPanes();
  renderNotices();
}

function renderPanes() {
  for (const pane of $$(".pane")) {
    const side = pane.dataset.pane;
    const list = pane.querySelector(".file-list");
    const rows = rowsFor(side);
    if (!rows.some(row => row.name === state.cursor[side])) state.cursor[side] = "..";
    list.innerHTML = rows.map((row, index) => `<div class="file-row" role="row" id="${list.id}-row-${index}" data-name="${escapeHtml(row.name)}" data-kind="${row.kind}" aria-selected="false"><span class="file-name" role="gridcell">${icon(row.kind)}<span>${escapeHtml(row.name)}</span></span><span class="meta size" role="gridcell">${row.size}</span><span class="meta date" role="gridcell">${row.date}</span><span class="meta permissions" role="gridcell">${row.permissions}</span></div>`).join("");
  }
  updateSelection();
}

function updateSelection() {
  for (const pane of $$(".pane")) {
    const side = pane.dataset.pane;
    pane.classList.toggle("active", side === state.active);
    for (const row of pane.querySelectorAll(".file-row")) {
      const selected = state.selected[side].has(row.dataset.name);
      row.classList.toggle("pending-file", selected);
      row.classList.toggle("cursor", row.dataset.name === state.cursor[side]);
      row.setAttribute("aria-selected", String(selected));
      if (row.dataset.name === state.cursor[side]) pane.querySelector(".file-list").setAttribute("aria-activedescendant", row.id);
    }
    pane.querySelector(".status-name").textContent = state.selected[side].size ? `${state.selected[side].size} selected` : state.cursor[side];
    pane.querySelector(".status-count").textContent = `${rowsFor(side).length - 1} items · 112 GB free`;
  }
}

function renderNotices() {
  for (const window of $$(".ferryx-window")) {
    window.querySelector(".delete-notice")?.remove();
    const notice = document.createElement("section");
    notice.className = "delete-notice";
    notice.dataset.presentation = window.dataset.presentation;
    notice.dataset.phase = state.phase;
    notice.setAttribute("aria-label", pending() ? "Удаление ещё не началось" : "Результат действия");
    notice.innerHTML = noticeMarkup(window.dataset.presentation);
    // A batch captures its source before the countdown. Changing the active
    // panel must never move its notice or change the scheduled targets.
    const host = window.dataset.presentation === "card"
      ? window.querySelector(`[data-pane="${state.batch.side}"]`)
      : window;
    host.append(notice);
  }
  updateCountdown();
  updateControls();
}

function updateCountdown() {
  const fraction = Math.max(0, state.remaining / state.seconds);
  for (const notice of $$(".delete-notice")) notice.style.setProperty("--time-left", String(fraction));
  for (const label of $$("[data-seconds]")) label.textContent = String(Math.ceil(state.remaining));
}

function updateControls() {
  $("#play").disabled = state.phase === "waiting";
  $("#demo-state").textContent = ({
    preview: "Стоп-кадр. Нажмите D или «Проиграть отсчёт».",
    waiting: "Файлы на месте. Удаление ещё не началось.",
    cancelled: "Отменено до начала: ни один файл не удалён.",
    done: "Отсчёт завершён: файлы перемещены в демокорзину.",
    restored: "Undo: файлы возвращены из демокорзины.",
  })[state.phase];
}

function stopClock() {
  if (state.frame !== null) cancelAnimationFrame(state.frame);
  state.frame = null;
}

function restoreScenario() {
  stopClock();
  const scenario = scenarios[state.scenario];
  state.active = scenario.side;
  state.removed = { left: new Set(), right: new Set() };
  state.selected = { left: new Set(), right: new Set() };
  state.selected[scenario.side] = new Set(scenario.names);
  state.cursor = { left: "Photo", right: "afrog.proto" };
  state.cursor[scenario.side] = scenario.names[0];
  state.batch = { ...scenario, names: [...scenario.names] };
  state.remaining = state.seconds;
  state.phase = "preview";
}

function beginCountdown() {
  if (state.phase === "waiting") return;
  const side = state.active;
  const names = rowsFor(side).filter(row => row.kind !== "parent" && (state.selected[side].size ? state.selected[side].has(row.name) : row.name === state.cursor[side])).map(row => row.name);
  if (!names.length) return;
  state.batch = {
    side, names,
    noun: names.length === 1 ? (fixtures[side].find(row => row.name === names[0]).kind === "folder" ? "folder" : "file") : "files",
    path: side === "left" ? scenarios.folder.path : scenarios.three.path,
  };
  state.remaining = state.seconds;
  state.deadline = performance.now() + state.seconds * 1000;
  state.phase = "waiting";
  renderNotices();
  $("#announcement").textContent = `Удаление ${names.length} объектов начнётся через ${state.seconds} секунд. Cancel или Esc отменяет действие.`;
  function tick() {
    state.remaining = Math.max(0, (state.deadline - performance.now()) / 1000);
    if (state.remaining <= 0) {
      state.frame = null;
      // The first mutation of fixture contents happens only after the deadline.
      for (const name of state.batch.names) {
        state.removed[state.batch.side].add(name);
        state.selected[state.batch.side].delete(name);
      }
      state.phase = "done";
      renderPanes();
      renderNotices();
      $("#announcement").textContent = "Время истекло. Файлы перемещены в демокорзину. Доступен Undo.";
      return;
    }
    updateCountdown();
    state.frame = requestAnimationFrame(tick);
  }
  state.frame = requestAnimationFrame(tick);
}

function focusFiles() {
  $(`.ferryx-window [data-list="${state.active}"]`)?.focus({ preventScroll: true });
}

function cancelDeletion() {
  if (!pending()) return;
  stopClock();
  state.phase = "cancelled";
  renderNotices();
  focusFiles();
  $("#announcement").textContent = "Запланированное удаление отменено. Все файлы остались на месте.";
}

function undo() {
  if (state.phase !== "done") return;
  for (const name of state.batch.names) {
    state.removed[state.batch.side].delete(name);
    state.selected[state.batch.side].add(name);
  }
  state.active = state.batch.side;
  state.cursor[state.active] = state.batch.names[0];
  state.phase = "restored";
  renderPanes();
  renderNotices();
  focusFiles();
  $("#announcement").textContent = "Undo: файлы возвращены из демокорзины.";
}

function applyTheme() {
  document.documentElement.dataset.theme = state.theme;
  $("#theme").value = state.theme;
}

function saveUrl() {
  const url = new URL(location.href);
  url.searchParams.set("variant", state.variant);
  url.searchParams.set("scenario", state.scenario);
  url.searchParams.set("delay", String(state.seconds));
  url.searchParams.set("theme", state.theme);
  try { history.replaceState(null, "", url); } catch { /* Some file: contexts restrict history. */ }
}

document.addEventListener("click", event => {
  const variant = event.target.closest("[data-choice]");
  if (variant) {
    state.variant = variant.dataset.choice;
    restoreScenario();
    for (const button of $$("[data-choice]")) button.setAttribute("aria-pressed", String(button === variant));
    renderStage();
    saveUrl();
    return;
  }
  const action = event.target.closest("[data-action]")?.dataset.action;
  if (action === "cancel") return cancelDeletion();
  if (action === "undo") return undo();
  if (action === "replay") {
    restoreScenario();
    renderStage();
    focusFiles();
    return beginCountdown();
  }
  const pane = event.target.closest(".pane");
  if (pane) {
    state.active = pane.dataset.pane;
    const row = event.target.closest(".file-row");
    if (row) state.cursor[state.active] = row.dataset.name;
    updateSelection();
    pane.querySelector(".file-list").focus({ preventScroll: true });
  }
});

document.addEventListener("keydown", event => {
  if (event.ctrlKey || event.metaKey || event.altKey || event.target.closest("select, input")) return;
  if (event.key === "Escape" && pending()) {
    event.preventDefault();
    return cancelDeletion();
  }
  if (event.key === "D" && !event.repeat) {
    event.preventDefault();
    focusFiles();
    return beginCountdown();
  }
  const list = event.target.closest(".file-list");
  if (!list) return;
  if (event.key === "Tab" && !event.shiftKey) {
    event.preventDefault();
    state.active = state.active === "left" ? "right" : "left";
    updateSelection();
    list.closest(".ferryx-window").querySelector(`[data-list="${state.active}"]`).focus({ preventScroll: true });
  } else if (["ArrowDown", "ArrowUp", "j", "k"].includes(event.key)) {
    event.preventDefault();
    const rows = rowsFor(state.active);
    const index = rows.findIndex(row => row.name === state.cursor[state.active]);
    const delta = event.key === "ArrowDown" || event.key === "j" ? 1 : -1;
    state.cursor[state.active] = rows[Math.max(0, Math.min(rows.length - 1, index + delta))].name;
    updateSelection();
    list.querySelector(".cursor")?.scrollIntoView({ block: "nearest" });
  } else if (event.key === " " && state.cursor[state.active] !== "..") {
    event.preventDefault();
    const selection = state.selected[state.active];
    const name = state.cursor[state.active];
    if (selection.has(name)) selection.delete(name);
    else selection.add(name);
    updateSelection();
  }
});

$("#play").addEventListener("click", () => {
  if (state.phase === "done") { restoreScenario(); renderStage(); }
  focusFiles();
  beginCountdown();
});
$("#reset").addEventListener("click", () => { restoreScenario(); renderStage(); focusFiles(); });
$("#scenario").addEventListener("change", event => { state.scenario = event.target.value; restoreScenario(); renderStage(); saveUrl(); });
$("#delay").addEventListener("change", event => { state.seconds = Number(event.target.value); restoreScenario(); renderStage(); saveUrl(); });
$("#theme").addEventListener("change", event => { state.theme = event.target.value; applyTheme(); saveUrl(); });
$("#compare").addEventListener("click", () => {
  const url = new URL(location.href);
  url.searchParams.set("examples", "1");
  url.searchParams.delete("capture");
  location.href = url.href;
});

document.body.classList.toggle("examples", state.examples);
document.body.classList.toggle("lifecycle", state.lifecycle);
document.body.classList.toggle("capture", query.has("capture") && !state.examples && !state.lifecycle);
$("#scenario").value = state.scenario;
$("#delay").value = String(state.seconds);
for (const button of $$("[data-choice]")) button.setAttribute("aria-pressed", String(button.dataset.choice === state.variant));
applyTheme();
restoreScenario();
if (state.lifecycle || state.examples) state.remaining = state.seconds * .6;
renderStage();
if (!state.examples && !state.lifecycle) document.fonts.ready.then(focusFiles);
window.addEventListener("pagehide", stopClock);
