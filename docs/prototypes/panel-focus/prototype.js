"use strict";

// A visual study with in-memory fixtures. It never opens or changes real files.
const icons = {
  folder: '<path d="M2.5 5.5h5l1.5 2H21v11a1 1 0 0 1-1 1H3.5a1 1 0 0 1-1-1z"/>',
  file: '<path d="M6 2.5h8l4 4v15H6zM14 2.5v5h4"/>',
  code: '<path d="M6 2.5h8l4 4v15H6zM14 2.5v5h4m-8 3.5-2 2.5 2 2.5m4-5 2 2.5-2 2.5"/>',
  parent: '<path d="m7 8 5-5 5 5M12 3v13a4 4 0 0 0 4 4h4"/>',
  right: '<path d="m9 5 7 7-7 7"/>',
  down: '<path d="M12 4v16m-5-5 5 5 5-5"/>',
  search: '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/>',
  list: '<path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/>',
  menu: '<circle cx="5" cy="12" r=".7"/><circle cx="12" cy="12" r=".7"/><circle cx="19" cy="12" r=".7"/>',
  plus: '<path d="M12 4v16M4 12h16"/>',
};
const icon = (name) => `<svg viewBox="0 0 24 24" aria-hidden="true">${icons[name] ?? icons.file}</svg>`;
const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];
const escapeHtml = (value) => String(value).replace(/[&<>"']/g, (char) => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
})[char]);
const folder = (name, date) => ({ name, date, size: "Folder", kind: "folder", permissions: "rwx------" });
const file = (name, size, date, kind = "file") => ({ name, size, date, kind, permissions: "rw-r--r--" });
const entries = {
  left: [
    folder("English", "Oct 30, 13:33"), folder("System", "Oct 30, 13:33"),
    folder("Русский", "Oct 30, 13:33"), folder("Downloads", "Oct 30, 13:33"),
    folder("Photo", "Oct 15, 2024"), folder("screens", "Oct 30, 13:33"),
    folder("Dropbox PocketBook", "Oct 15, 2024"), folder("Notes", "May 17, 2023"),
    folder("SendToPb", "Jul 30, 13:33"), folder("My pictures", "Oct 30, 13:33"),
    folder("applications", "Jul 30, 13:39"), folder("news", "Jul 30, 13:45"),
    folder("Audio Books", "Jan 1, 2010"), folder("Music", "Jan 1, 2010"),
    file("autorun.inf", "63 B", "Jan 1, 2010"),
  ],
  right: [
    file("afrog.proto", "8.4 KB", "Nov 1, 23:15"),
    file("afrog_grpc.pb.go", "19 KB", "Nov 1, 23:15", "code"),
    file("generate.go", "408 B", "Nov 1, 23:15", "code"),
    file("afrog.pb.go", "126 KB", "Nov 1, 23:15", "code"),
  ],
};
const variants = {
  current: { letter: "", name: "Сейчас", description: "Тонкая верхняя линия, подчёркивание вкладки и текущая строка." },
  header: { letter: "A", name: "Шапка", description: "Заливка строки пути и вкладок. Линия под всей шапкой." },
  frame: { letter: "B", name: "Контур", description: "Рамка 2 px вокруг всей активной панели." },
  combined: { letter: "C", name: "Вместе", description: "Заливка шапки и рамка 2 px вокруг активной панели." },
};
const query = new URLSearchParams(location.search);
const state = {
  variant: Object.hasOwn(variants, query.get("variant")) ? query.get("variant") : "combined",
  theme: query.get("theme") === "dark" ? "dark" : "light",
  layout: query.get("layout") === "rows" ? "rows" : "columns",
  active: query.get("active") === "left" ? "left" : "right",
  empty: query.get("empty") === "1",
  compare: query.has("compare"),
  panes: {
    left: { cursor: "Photo", selected: new Set(), tab: 1, tabs: ["Downloads", "pocketbook"] },
    right: { cursor: "afrog.proto", selected: new Set(), tab: 0, tabs: ["v1"] },
  },
  prefix: false,
};
const opposite = (side) => side === "left" ? "right" : "left";
const parent = { name: "..", size: "", date: "", permissions: "", kind: "parent" };
const entriesFor = (side) => [parent, ...(state.empty ? [] : entries[side])];

function paneMarkup(side, windowId) {
  const name = side === "left" ? "Левая" : "Правая";
  const path = side === "left" ? ["Downloads", "pocketbook"] : ["Downloads", "afrog", "proto", "afrog", "v1"];
  return `<section class="pane" data-pane="${side}" aria-label="${name} файловая панель">
    <header class="pane-toolbar">
      ${side === "left" ? '<div class="traffic-lights" aria-hidden="true"><i></i><i></i><i></i></div>' : ""}
      <div class="breadcrumbs">${path.map((part, index) => `${index ? icon("right") : ""}<span class="crumb${index === path.length - 1 ? " current" : ""}">${part}</span>`).join("")}</div>
      <div class="toolbar-actions">
        <span class="sort-label">Modified ${icon("down")}</span>
        <button class="command-button" data-action="commands" title="Демонстрация фокуса: Commands">${icon("search")}<span class="control-label">Commands</span></button>
        <span class="toolbar-icon" aria-hidden="true">${icon("list")}</span>
        <span class="toolbar-icon" aria-hidden="true">${icon("menu")}</span>
      </div>
    </header>
    <div class="tabs-bar" role="tablist" aria-label="Вкладки ${name.toLowerCase()} панели"></div>
    <div class="column-head" aria-hidden="true"><span>Name</span><span class="size">Size</span><span class="date modified">Modified ${icon("down")}</span><span class="permissions">Permissions</span></div>
    <div class="file-list" data-list="${side}" tabindex="0" role="grid" aria-label="Файлы: ${name.toLowerCase()} панель" aria-multiselectable="true" id="${windowId}-${side}-list"></div>
    <footer class="pane-status"><span class="mode-badge">NORMAL</span><span class="status-name"></span><span class="status-count"></span></footer>
  </section>`;
}

function createWindow(variant, windowId) {
  const window = $("#window-template").content.firstElementChild.cloneNode(true);
  window.dataset.variant = variant;
  window.dataset.window = windowId;
  window.querySelector(".workspace").innerHTML = `${paneMarkup("left", windowId)}<div class="panel-divider" aria-hidden="true"></div>${paneMarkup("right", windowId)}`;
  return window;
}

function renderStage() {
  const stage = $("#stage");
  stage.replaceChildren();
  if (state.compare) {
    const intro = document.createElement("p");
    intro.className = "comparison-intro";
    intro.textContent = "Одинаковые файлы, шрифт и масштаб. Клик или Tab переключает активную панель одновременно во всех вариантах.";
    stage.append(intro);
    for (const name of ["header", "frame", "combined"]) {
      const variant = variants[name];
      const card = document.createElement("section");
      card.className = "comparison-card";
      card.innerHTML = `<header class="comparison-caption"><span class="comparison-letter">${variant.letter}</span><strong>${variant.name}</strong><p>${variant.description}</p></header>`;
      card.append(createWindow(name, name));
      stage.append(card);
    }
  } else {
    stage.append(createWindow(state.variant, "main"));
  }
  renderPanes();
}

function renderPanes() {
  for (const pane of $$(".pane")) {
    const side = pane.dataset.pane;
    const data = state.panes[side];
    const list = pane.querySelector(".file-list");
    const windowId = pane.closest("[data-window]").dataset.window;
    if (!entriesFor(side).some((entry) => entry.name === data.cursor)) data.cursor = "..";
    pane.querySelector(".tabs-bar").innerHTML = data.tabs.map((name, index) => `<button class="tab" role="tab" data-action="tab" data-index="${index}" aria-selected="${index === data.tab}">${icon("folder")}<span>${name}</span></button>`).join("") + `<button class="add-tab" data-action="add-tab" aria-label="Добавить демонстрационную вкладку">${icon("plus")}</button>`;
    list.innerHTML = entriesFor(side).map((entry, index) => `<div class="file-row" role="row" data-name="${escapeHtml(entry.name)}" data-kind="${entry.kind}" id="${windowId}-${side}-${index}" aria-selected="false">
      <span class="file-name" role="gridcell">${icon(entry.kind)}<span>${escapeHtml(entry.name)}</span></span>
      <span class="meta size" role="gridcell">${entry.size}</span><span class="meta date" role="gridcell">${entry.date}</span><span class="meta permissions" role="gridcell">${entry.permissions}</span>
    </div>`).join("") + (state.empty ? `<p class="empty-message">${icon("folder")}This folder is empty</p>` : "");
  }
  updateCursor();
  updateActive();
}

function updateCursor() {
  for (const pane of $$(".pane")) {
    const side = pane.dataset.pane;
    const data = state.panes[side];
    for (const row of pane.querySelectorAll(".file-row")) {
      const current = row.dataset.name === data.cursor;
      row.classList.toggle("cursor", current);
      row.classList.toggle("marked", data.selected.has(row.dataset.name));
      row.setAttribute("aria-selected", String(data.selected.has(row.dataset.name)));
      if (current) pane.querySelector(".file-list").setAttribute("aria-activedescendant", row.id);
    }
    pane.querySelector(".status-name").textContent = data.selected.size ? `${data.selected.size} selected` : data.cursor;
    pane.querySelector(".status-count").textContent = `${state.empty ? 0 : entries[side].length} items · 112 GB free`;
  }
}

function updateActive() {
  for (const pane of $$(".pane")) pane.classList.toggle("active", pane.dataset.pane === state.active);
}

function activate(side, window, focus = true) {
  const changed = state.active !== side;
  state.active = side;
  state.prefix = false;
  updateActive();
  if (focus) window.querySelector(`[data-list="${side}"]`).focus({ preventScroll: true });
  if (changed) $("#announcement").textContent = `Активна ${side === "left" ? "левая" : "правая"} панель`;
}

function applyControls() {
  const root = document.documentElement;
  root.dataset.theme = state.theme;
  root.dataset.layout = state.layout;
  root.dataset.variant = state.variant;
  document.body.classList.toggle("capture", query.has("capture") && !state.compare);
  document.body.classList.toggle("comparison", state.compare);
  for (const button of $$("[data-variant-choice]")) button.setAttribute("aria-pressed", String(button.dataset.variantChoice === state.variant));
  $("#theme").value = state.theme;
  $("#layout").value = state.layout;
  $("#empty-folder").checked = state.empty;
  const variant = variants[state.variant];
  $("#variant-description").textContent = `${variant.letter ? variant.letter + " · " : ""}${variant.name}: ${variant.description}`;
}

function saveUrl() {
  const url = new URL(location.href);
  for (const key of ["variant", "theme", "layout", "active"]) url.searchParams.set(key, state[key]);
  if (state.empty) url.searchParams.set("empty", "1");
  else url.searchParams.delete("empty");
  try { history.replaceState(null, "", url); } catch { /* file: URLs can restrict history. */ }
}

document.addEventListener("click", (event) => {
  const choice = event.target.closest("[data-variant-choice]");
  if (choice) {
    state.variant = choice.dataset.variantChoice;
    $(".ferryx-window").dataset.variant = state.variant;
    applyControls();
    saveUrl();
    return;
  }
  const pane = event.target.closest(".pane");
  if (!pane) return;
  const side = pane.dataset.pane;
  const window = pane.closest(".ferryx-window");
  activate(side, window);
  const data = state.panes[side];
  const action = event.target.closest("[data-action]");
  if (action?.dataset.action === "tab") {
    data.tab = Number(action.dataset.index);
    renderPanes();
  } else if (action?.dataset.action === "add-tab") {
    data.tabs.push(side === "left" ? "pocketbook" : "v1");
    data.tab = data.tabs.length - 1;
    renderPanes();
  }
  const row = event.target.closest(".file-row");
  if (row) {
    data.cursor = row.dataset.name;
    updateCursor();
  }
  saveUrl();
});

document.addEventListener("focusin", (event) => {
  const pane = event.target.closest(".pane");
  if (pane) activate(pane.dataset.pane, pane.closest(".ferryx-window"), false);
});

document.addEventListener("keydown", (event) => {
  if (event.metaKey || event.ctrlKey || event.altKey) return;
  const list = event.target.closest(".file-list");
  if (!list) return;
  const window = list.closest(".ferryx-window");
  const side = list.dataset.list;
  const data = state.panes[side];
  if (event.key === "Tab" && !event.shiftKey) {
    event.preventDefault();
    activate(opposite(side), window);
    saveUrl();
    return;
  }
  if (state.prefix && (event.key === "t" || event.key === "T")) {
    event.preventDefault();
    data.tab = (data.tab + (event.key === "T" ? -1 : 1) + data.tabs.length) % data.tabs.length;
    state.prefix = false;
    renderPanes();
    return;
  }
  state.prefix = event.key === "g";
  const rows = entriesFor(side);
  const index = rows.findIndex((entry) => entry.name === data.cursor);
  if (["ArrowDown", "ArrowUp", "j", "k"].includes(event.key)) {
    event.preventDefault();
    const delta = event.key === "ArrowDown" || event.key === "j" ? 1 : -1;
    data.cursor = rows[Math.max(0, Math.min(rows.length - 1, index + delta))].name;
    updateCursor();
    list.querySelector(".cursor").scrollIntoView({ block: "nearest" });
  } else if (event.key === " " && data.cursor !== "..") {
    event.preventDefault();
    if (data.selected.has(data.cursor)) data.selected.delete(data.cursor);
    else data.selected.add(data.cursor);
    updateCursor();
  } else if (event.key === "Escape") {
    data.selected.clear();
    updateCursor();
  }
});

$("#theme").addEventListener("change", (event) => {
  state.theme = event.target.value;
  applyControls();
  saveUrl();
});
$("#layout").addEventListener("change", (event) => {
  state.layout = event.target.value;
  applyControls();
  saveUrl();
});
$("#empty-folder").addEventListener("change", (event) => {
  state.empty = event.target.checked;
  state.panes.left.selected.clear();
  state.panes.right.selected.clear();
  state.panes.left.cursor = state.empty ? ".." : "Photo";
  state.panes.right.cursor = state.empty ? ".." : "afrog.proto";
  renderPanes();
  applyControls();
  saveUrl();
});
$("#compare").addEventListener("click", () => {
  const url = new URL(location.href);
  url.searchParams.set("compare", "1");
  url.searchParams.delete("capture");
  url.searchParams.set("layout", "columns");
  location.href = url.href;
});

applyControls();
renderStage();
document.fonts.ready.then(() => {
  $(".ferryx-window").querySelector(`[data-list="${state.active}"]`).focus({ preventScroll: true });
});
