"use strict";

const icons = {
  folder: '<path d="M3 7V5a1 1 0 0 1 1-1h5l2 3h9a1 1 0 0 1 1 1v11a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1Z"/>',
  file: '<path d="M14 3H5a1 1 0 0 0-1 1v16a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1V9Z"/><path d="M14 3v6h6"/>',
  code: '<path d="M14 3H5a1 1 0 0 0-1 1v16a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1V9Z"/><path d="M14 3v6h6m-10 4-2 2 2 2m4-4 2 2-2 2"/>',
  parent: '<path d="m7 8 5-5 5 5M12 3v13a4 4 0 0 0 4 4h4"/>',
  right: '<path d="m9 5 7 7-7 7"/>',
  down: '<path d="M12 4v16m-5-5 5 5 5-5"/>',
  search: '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/>',
  list: '<path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/>',
  menu: '<circle cx="5" cy="12" r=".7"/><circle cx="12" cy="12" r=".7"/><circle cx="19" cy="12" r=".7"/>',
  plus: '<path d="M12 4v16M4 12h16"/>',
};
const icon = name => `<svg viewBox="0 0 24 24" aria-hidden="true">${icons[name] ?? icons.file}</svg>`;
const escapeHtml = value => String(value).replace(/[&<>"']/g, char => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
})[char]);
const variants = {
  mint: { letter: "A", name: "Один цвет", description: "До часа — мятный фон, в течение суток — более слабый оттенок." },
  duo: { letter: "B", name: "Два цвета", description: "До часа — мятный фон, от часа до суток — сиреневый." },
  marker: { letter: "C", name: "Фон и маркер", description: "Точка у имени сохраняет признак давности на выделенной строке." },
};
const entry = (name, kind, size, age, modified = "11 ноя, 17:06") => ({ name, kind, size, age, modified });
const rows = {
  left: [
    entry("Новый проект", "folder", "Папка", 8),
    entry("Отчёт_аудита.docx", "file", "148 КБ", 17, "3 окт, 10:24"),
    entry("Презентация.pptx", "file", "7,6 МБ", 42),
    entry("Документы", "folder", "Папка", 145, "7 ноя, 12:10"),
    entry("Реестр оборудования.xlsx", "file", "62 КБ", 390),
    entry("Схема сети.pdf", "file", "824 КБ", 1300, "9 ноя, 08:44"),
    entry("English", "folder", "Папка", 4000, "30 окт, 13:33"),
    entry("Photo", "folder", "Папка", 8200, "15 окт 2024"),
    entry("notes.md", "file", "4,2 КБ", 9000, "29 окт, 21:05"),
    entry("archive.zip", "file", "12,4 МБ", 12000, "22 окт, 15:32"),
    entry("config.yaml", "code", "1,1 КБ", 14000, "18 окт, 11:20"),
    entry("README.md", "file", "8,3 КБ", 16000, "15 окт, 16:08"),
  ],
  right: [
    entry("assets", "folder", "Папка", 4),
    entry("preview.dart", "code", "5,8 КБ", 26, "6 ноя, 18:20"),
    entry("fixtures", "folder", "Папка", 110),
    entry("table_test.dart", "code", "9,2 КБ", 560),
    entry("prototype.html", "code", "6,4 КБ", 1380),
    entry("lib", "folder", "Папка", 4000, "2 ноя, 14:40"),
    entry("test", "folder", "Папка", 4000, "2 ноя, 14:40"),
    entry("Cargo.toml", "code", "1,4 КБ", 6000, "30 окт, 10:02"),
    entry("pubspec.yaml", "code", "2,3 КБ", 9000, "27 окт, 09:18"),
    entry("README.md", "file", "8,3 КБ", 12000, "21 окт, 17:20"),
  ],
};
const query = new URLSearchParams(location.search);
const state = {
  variant: Object.hasOwn(variants, query.get("variant")) ? query.get("variant") : "mint",
  theme: query.get("theme") === "dark" ? "dark" : "light",
  elapsed: [0, 2, 24].includes(Number(query.get("elapsed"))) ? Number(query.get("elapsed")) : 0,
  compare: query.has("compare"),
  active: "left",
  cursor: { left: 1, right: 4 },
  marked: { left: new Set([4]), right: new Set() },
  added: 0,
};
const parent = { name: "..", kind: "parent", size: "", age: Infinity, modified: "" };
const entries = side => [parent, ...rows[side]];
function ageGroup(row) {
  const age = row.age + state.elapsed * 60;
  if (age < 60) return "fresh";
  if (age < 1440) return "today";
  return "old";
}

function ageLabel(row) {
  if (row.kind === "parent") return "Родительская папка";
  const age = Math.max(0, row.age + state.elapsed * 60);
  if (age < 60) return `Добавлено в эту папку ${age} мин назад`;
  if (age < 1440) return `Добавлено в эту папку ${Math.floor(age / 60)} ч назад`;
  return "Добавлено в эту папку более суток назад";
}

function legend() {
  return '<span class="age-legend" aria-label="Давность добавления в папку">'
    + '<span class="legend-label">Добавлены</span>'
    + '<span class="legend-item" title="Добавлено менее часа назад"><i class="age-swatch" aria-hidden="true"></i>До 1 часа</span>'
    + '<span class="legend-item" title="Добавлено от 1 до 24 часов назад"><i class="age-swatch today" aria-hidden="true"></i>1–24 часа</span></span>';
}

function pane(side, windowId) {
  const path = side === "left" ? ["Downloads"] : ["Projects", "ferryx"];
  const label = side === "left" ? "Левая" : "Правая";
  return `<section class="pane ${state.active === side ? "active" : ""}" data-pane="${side}" aria-label="${label} файловая панель">
    <header class="pane-toolbar">
      ${side === "left" ? '<div class="traffic-lights" aria-hidden="true"><i></i><i></i><i></i></div>' : ""}
      <div class="breadcrumbs">${path.map((part, index) => `${index ? icon("right") : ""}<span class="crumb current">${part}</span>`).join("")}</div>
      <div class="toolbar-actions"><span class="sort-label">Modified ${icon("down")}</span><span class="command-button">${icon("search")}<span>Commands</span></span><span class="toolbar-icon">${icon("list")}</span><span class="toolbar-icon">${icon("menu")}</span></div>
    </header>
    <div class="tabs-bar"><div class="tab" aria-selected="true">${icon("folder")}<span>${path.at(-1)}</span></div><span class="add-tab">${icon("plus")}</span></div>
    <div class="column-head" aria-hidden="true"><span>Name</span><span class="size">Size</span><span class="modified date">Modified ${icon("down")}</span><span class="permissions">Permissions</span></div>
    <div class="file-list" tabindex="0" role="grid" aria-label="${label} панель" aria-multiselectable="true" data-list="${side}">
      ${entries(side).map((row, index) => `<div id="${windowId}-${side}-${index}" role="row" class="file-row ${row.kind === "parent" ? "parent" : ""}" data-index="${index}" data-kind="${row.kind}" data-age="${ageGroup(row)}" title="${escapeHtml(ageLabel(row))}">
        <span role="gridcell" class="file-name">${icon(row.kind)}<i class="age-marker" aria-hidden="true"></i><span class="entry-name">${escapeHtml(row.name)}</span></span>
        <span role="gridcell" class="meta size">${row.size}</span><span role="gridcell" class="meta date">${row.modified}</span><span role="gridcell" class="meta permissions">${row.kind === "parent" ? "" : row.kind === "folder" ? "rwx------" : "rw-r--r--"}</span>
      </div>`).join("")}
    </div>
    <footer class="pane-status"><span class="mode-badge">NORMAL</span>${legend()}<span class="status-count">${rows[side].length} items<span class="free-space"> · 112 GB free</span></span></footer>
  </section>`;
}

function windowMarkup(variant) {
  return `<section class="ferryx-window" data-variant="frame" data-tabs="plain" data-age-style="${variant}" aria-label="Вариант ${variants[variant].letter}">
    <div class="workspace">${pane("left", variant)}<div class="panel-divider" aria-hidden="true"></div>${pane("right", variant)}</div>
    <footer class="key-hints"><div class="hint-group"><span class="hint"><kbd>Tab</kbd> Change Panel</span><span class="hint"><kbd>Space</kbd> Select</span><span class="hint"><kbd class="typed">i</kbd> Preview</span></div><span class="hint help-hint">Shortcuts <kbd>⌘/</kbd></span></footer>
  </section>`;
}

function refreshSelection() {
  document.querySelectorAll(".pane").forEach(element => {
    const side = element.dataset.pane;
    element.classList.toggle("active", side === state.active);
    element.querySelectorAll(".file-row").forEach(row => {
      const index = Number(row.dataset.index);
      row.classList.toggle("cursor", index === state.cursor[side]);
      row.classList.toggle("marked", state.marked[side].has(index));
      row.setAttribute("aria-selected", String(state.marked[side].has(index)));
    });
    element.querySelector(".file-list").setAttribute("aria-activedescendant", `${element.closest(".ferryx-window").dataset.ageStyle}-${side}-${state.cursor[side]}`);
  });
}

function render() {
  document.documentElement.dataset.theme = state.theme;
  document.body.classList.toggle("comparison", state.compare);
  document.body.classList.toggle("detail", state.compare && query.has("detail"));
  document.body.classList.toggle("capture", query.has("capture") && !state.compare);
  document.querySelectorAll("button[data-variant]").forEach(button => button.setAttribute("aria-pressed", String(button.dataset.variant === state.variant)));
  document.querySelector("#theme").value = state.theme;
  document.querySelector("#elapsed").value = String(state.elapsed);
  document.querySelector("#description").textContent = variants[state.variant].description;
  document.querySelector("#stage").innerHTML = state.compare
    ? '<p class="comparison-intro">Давность отсчитывается от появления в текущей папке. У элементов старше суток обычный фон.</p>'
      + Object.entries(variants).map(([key, value]) => `<section class="comparison-card"><header class="comparison-caption"><span class="comparison-letter">${value.letter}</span><strong>${value.name}</strong><p>${value.description}</p></header>${windowMarkup(key)}</section>`).join("")
    : windowMarkup(state.variant);
  refreshSelection();
  const url = new URL(location.href);
  url.searchParams.set("variant", state.variant);
  url.searchParams.set("theme", state.theme);
  url.searchParams.set("elapsed", String(state.elapsed));
  if (state.compare) url.searchParams.set("compare", "1");
  else url.searchParams.delete("compare");
  try { history.replaceState(null, "", url); } catch { /* file: URL restrictions */ }
}

document.addEventListener("click", event => {
  const variant = event.target.closest("button[data-variant]");
  if (variant) {
    state.variant = variant.dataset.variant;
    state.compare = false;
    render();
    return;
  }
  const pane = event.target.closest(".pane");
  if (!pane) return;
  state.active = pane.dataset.pane;
  const row = event.target.closest(".file-row");
  if (row) state.cursor[state.active] = Number(row.dataset.index);
  refreshSelection();
  pane.querySelector(".file-list").focus({ preventScroll: true });
});
document.addEventListener("keydown", event => {
  if (!event.target.closest(".file-list")) return;
  if (event.key === "Tab") {
    event.preventDefault();
    state.active = state.active === "left" ? "right" : "left";
    refreshSelection();
    event.target.closest(".ferryx-window").querySelector(`[data-list="${state.active}"]`).focus({ preventScroll: true });
  } else if (["ArrowDown", "j", "ArrowUp", "k"].includes(event.key)) {
    event.preventDefault();
    const direction = ["ArrowDown", "j"].includes(event.key) ? 1 : -1;
    state.cursor[state.active] = Math.max(0, Math.min(rows[state.active].length, state.cursor[state.active] + direction));
    refreshSelection();
    const pane = event.target.closest(".pane");
    pane.querySelector(".file-row.cursor").scrollIntoView({ block: "nearest" });
  } else if (event.code === "Space") {
    event.preventDefault();
    const index = state.cursor[state.active];
    if (!index) return;
    const selected = state.marked[state.active];
    if (selected.has(index)) selected.delete(index);
    else selected.add(index);
    refreshSelection();
  }
});
document.querySelector("#theme").addEventListener("change", event => { state.theme = event.target.value; render(); });
document.querySelector("#elapsed").addEventListener("change", event => { state.elapsed = Number(event.target.value); render(); });
document.querySelector("#compare").addEventListener("click", () => { state.compare = !state.compare; render(); });
document.querySelector("#add-file").addEventListener("click", () => {
  state.added++;
  const name = `Новый файл ${state.added}.txt`;
  rows[state.active].unshift(entry(name, "file", "0 Б", -state.elapsed * 60));
  state.marked[state.active] = new Set([...state.marked[state.active]].map(index => index + 1));
  state.cursor[state.active] = 1;
  render();
  document.querySelector("#announcement").textContent = `${name} добавлен в активную панель`;
});

render();
