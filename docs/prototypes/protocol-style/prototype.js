"use strict";

// This prototype only changes in-memory fixtures. No filesystem, network,
// persistent preferences, or application services are connected.
const icons = {
  folder: '<path d="M2.5 5.5h5l1.5 2h12v11a1 1 0 0 1-1 1h-17a1 1 0 0 1-1-1z"/>',
  file: '<path d="M6 2.5h8l4 4v15H6z"/><path d="M14 2.5v5h4"/>',
  code: '<path d="M6 2.5h8l4 4v15H6z"/><path d="m10 11-2 2.5 2 2.5m4-5 2 2.5-2 2.5M14 2.5v5h4"/>',
  archive: '<path d="M6 2.5h12v19H6zM11 3v3h3v3h-3v3h3v3h-3v3h3"/>',
  image: '<rect x="3" y="3" width="18" height="18" rx="1"/><circle cx="8" cy="8" r="1.5"/><path d="m3 17 6-5 4 4 3-3 5 5"/>',
  up: '<path d="m7 8 5-5 5 5M12 3v13a4 4 0 0 0 4 4h4"/>',
  right: '<path d="m9 5 7 7-7 7"/>',
  search: '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/>',
  sort: '<path d="M4 5h11M4 10h8M4 15h5m9-9v15m-3-3 3 3 3-3"/>',
  plus: '<path d="M12 4v16M4 12h16"/>',
  close: '<path d="m6 6 12 12M6 18 18 6"/>',
  keyboard: '<rect x="2" y="5" width="20" height="14" rx="1"/><path d="M5 8h1m3 0h1m3 0h1m3 0h1M5 11h1m3 0h1m3 0h1m3 0h1M6 15h12"/>',
  terminal: '<rect x="2" y="4" width="20" height="16" rx="1"/><path d="m6 9 3 3-3 3m6 0h5"/>',
  copy: '<path d="M8 8h12v13H8zM16 8V3H3v13h5"/>',
  panel: '<rect x="2" y="4" width="20" height="16" rx="1"/><path d="M12 4v16"/>',
  eye: '<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12"/><circle cx="12" cy="12" r="3"/>',
};

function icon(name) {
  return `<svg viewBox="0 0 24 24" aria-hidden="true">${icons[name] ?? icons.file}</svg>`;
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (character) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  })[character]);
}

const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];
const home = "/Users/demo";
const project = `${home}/Projects/ferryx`;
const downloads = `${home}/Downloads`;
const releases = `${downloads}/Release`;
const folder = (name, date = "08 ноя, 16:04") => ({ name, kind: "folder", size: "Папка", date, permissions: "rwxr-xr-x" });
const file = (name, size, date = "08 ноя, 16:11", kind = "file") => ({ name, kind, size, date, permissions: "rw-r--r--" });

const folders = new Map([
  [home, [folder("Desktop"), folder("Documents"), folder("Downloads"), folder("Projects")]],
  [`${home}/Projects`, [folder("ferryx"), folder("linkview"), folder("playground")]],
  [project, [
    folder("brand"), folder("docs"), folder("lib"), folder("linux"),
    folder("macos"), folder("packages"), folder("rust"), folder("rust_builder"),
    folder("test"), folder("tools"), folder("windows"),
    file("analysis_options.yaml", "1,4 КБ", undefined, "code"),
    file("ARCHITECTURE.md", "84 КБ"), file("CLAUDE.md", "16 КБ"),
    file("flutter_rust_bridge.yaml", "192 Б", undefined, "code"),
    file("Makefile", "5,3 КБ", undefined, "code"),
    file("pubspec.lock", "32 КБ"), file("pubspec.yaml", "2,1 КБ", undefined, "code"),
    file("README.md", "18 КБ"),
  ]],
  [`${project}/docs`, [folder("prototypes"), folder("screenshots")]],
  [`${project}/docs/screenshots`, [file("ferryx-macos.png", "238 КБ", undefined, "image")]],
  [`${project}/brand`, [folder("proposals"), folder("variants"), file("ferryx-256.png", "28 КБ", undefined, "image"), file("ferryx-macos.svg", "6,2 КБ", undefined, "image"), file("README.md", "4,8 КБ")]],
  [`${project}/lib`, [folder("app"), file("main.dart", "284 Б", undefined, "code")]],
  [`${project}/packages`, [folder("component_library"), folder("domain_models"), folder("features"), folder("file_repository"), folder("operations_service"), folder("preferences_service"), folder("shortcuts")]],
  [`${project}/rust`, [folder("crates"), folder("vendor"), file("Cargo.lock", "108 КБ"), file("Cargo.toml", "4,7 КБ", undefined, "code")]],
  [downloads, [folder("Assets"), folder("Documents"), folder("Release"), file("design-notes.md", "3,8 КБ"), file("reference.png", "412 КБ", undefined, "image")]],
  [releases, [
    folder("assets"), folder("checksums"), folder("screenshots"),
    file("Ferryx-0.1.0.dmg", "42,6 МБ", "08 ноя, 16:30", "archive"),
    file("ferryx-icons.zip", "1,8 МБ", "08 ноя, 15:42", "archive"),
    file("ferryx-macos.png", "238 КБ", "08 ноя, 16:11", "image"),
    file("ferryx-symbol.svg", "2,4 КБ", "08 ноя, 15:20", "image"),
    file("release-notes.md", "2,6 КБ", "08 ноя, 16:24"),
    file("SHA256SUMS", "168 Б", "08 ноя, 16:31"),
  ]],
]);

function newTab(path, cursor = "..") {
  return { path, cursor, selected: new Set(), descending: false };
}

const state = {
  active: "left",
  left: { tabs: [newTab(project, "README.md"), newTab(`${project}/docs`)], index: 0 },
  right: { tabs: [newTab(releases, "Ferryx-0.1.0.dmg"), newTab(downloads)], index: 0 },
  prefix: false,
  prefixTimer: null,
  toastTimer: null,
  pendingAction: null,
  copying: false,
  paletteIndex: 0,
};

const tabFor = (side = state.active) => state[side].tabs[state[side].index];
const opposite = (side = state.active) => side === "left" ? "right" : "left";
const basename = (path) => path.split("/").filter(Boolean).at(-1) ?? "/";
const parentPath = (path) => path.slice(0, path.lastIndexOf("/")) || "/";

function entriesFor(side) {
  const tab = tabFor(side);
  const entries = [...(folders.get(tab.path) ?? [])].sort((a, b) => {
    if (a.kind === "folder" && b.kind !== "folder") return -1;
    if (b.kind === "folder" && a.kind !== "folder") return 1;
    return a.name.localeCompare(b.name, "ru", { numeric: true }) * (tab.descending ? -1 : 1);
  });
  return [{ name: "..", kind: "parent", size: "", date: "", permissions: "" }, ...entries];
}

function targetsFor(side = state.active) {
  const tab = tabFor(side);
  return entriesFor(side).filter((entry) => entry.kind !== "parent" &&
    (tab.selected.size ? tab.selected.has(entry.name) : entry.name === tab.cursor));
}

function renderPane(side) {
  const pane = state[side];
  const tab = tabFor(side);
  const entries = entriesFor(side);
  if (!entries.some((entry) => entry.name === tab.cursor)) tab.cursor = "..";
  const parts = tab.path.split("/").filter(Boolean);
  const start = Math.max(0, parts.length - 2);
  $(`[data-breadcrumb="${side}"]`).innerHTML = parts.slice(start).map((part, index) => {
    const path = `/${parts.slice(0, start + index + 1).join("/")}`;
    return `${index ? icon("right") : ""}<button class="${index === parts.length - start - 1 ? "crumb-current" : ""}" data-action="navigate" data-side="${side}" data-path="${escapeHtml(path)}" title="${escapeHtml(path)}">${escapeHtml(part)}</button>`;
  }).join("");
  $(`[data-tabs="${side}"]`).innerHTML = pane.tabs.map((item, index) => `
    <div class="tab" role="tab" aria-selected="${index === pane.index}" data-tab="${index}" data-side="${side}" tabindex="${index === pane.index ? 0 : -1}">
      <button class="tab-label" tabindex="-1" data-action="tab" data-side="${side}" data-index="${index}" title="${escapeHtml(item.path)}">${icon("folder")}<span>${escapeHtml(basename(item.path))}</span></button>
      <button class="tab-close" data-action="close-tab" data-side="${side}" data-index="${index}" aria-label="Закрыть вкладку ${escapeHtml(basename(item.path))}">${icon("close")}</button>
    </div>`).join("") + `<button class="new-tab" data-action="new-tab" data-side="${side}" title="Новая вкладка" aria-label="Новая вкладка в ${side === "left" ? "левой" : "правой"} панели">${icon("plus")}</button>`;

  const list = $(`[data-list="${side}"]`);
  list.innerHTML = entries.map((entry, index) => `
    <div id="${side}-row-${index}" class="file-row${entry.kind === "parent" ? " parent-row" : ""}${tab.cursor === entry.name ? " is-cursor" : ""}${tab.selected.has(entry.name) ? " is-selected" : ""}" data-name="${escapeHtml(entry.name)}" data-kind="${entry.kind}" role="row" aria-selected="${tab.selected.has(entry.name)}">
      <div class="file-name" role="gridcell">${icon(entry.kind === "parent" ? "up" : entry.kind)}<span>${escapeHtml(entry.name)}</span>${tab.selected.has(entry.name) ? '<i class="selected-marker" aria-hidden="true"></i>' : ""}</div>
      <span class="file-meta size-column" role="gridcell">${escapeHtml(entry.size)}</span>
      <span class="file-meta date-column" role="gridcell">${escapeHtml(entry.date)}</span>
      <span class="file-meta permissions-column" role="gridcell">${escapeHtml(entry.permissions)}</span>
    </div>`).join("") + (entries.length === 1 ? '<div class="file-empty">В этой демопапке пока нет файлов</div>' : "");
  list.setAttribute("aria-activedescendant", `${side}-row-${entries.findIndex((entry) => entry.name === tab.cursor)}`);
  $(`[data-sort-indicator="${side}"]`).textContent = tab.descending ? "↓" : "↑";
  renderStatus(side);
  renderHints();
}

function renderStatus(side) {
  const tab = tabFor(side);
  const count = folders.get(tab.path)?.length ?? 0;
  $(`[data-status="${side}"]`).innerHTML = `<span class="mode-badge">NORMAL</span><span class="status-name">${tab.selected.size ? `Выбрано: ${tab.selected.size}` : escapeHtml(tab.cursor === ".." ? basename(tab.path) : tab.cursor)}</span><span class="status-count">${count} элементов <span aria-hidden="true">·</span> 121 ГБ свободно</span>`;
}

// Preserve row elements during selection so a double-click stays on the same
// target and cursor movement does not recreate an entire table.
function updateRows(side) {
  const tab = tabFor(side);
  const list = $(`[data-list="${side}"]`);
  for (const row of list.querySelectorAll(".file-row")) {
    const selected = tab.selected.has(row.dataset.name);
    const current = tab.cursor === row.dataset.name;
    row.classList.toggle("is-selected", selected);
    row.classList.toggle("is-cursor", current);
    row.setAttribute("aria-selected", String(selected));
    if (current) list.setAttribute("aria-activedescendant", row.id);
    const marker = row.querySelector(".selected-marker");
    if (selected && !marker) {
      const element = document.createElement("i");
      element.className = "selected-marker";
      element.setAttribute("aria-hidden", "true");
      row.querySelector(".file-name").append(element);
    } else if (!selected) marker?.remove();
  }
  renderStatus(side);
  renderHints();
}

function activate(side, focus = true) {
  state.active = side;
  $$(".pane").forEach((pane) => pane.classList.toggle("active", pane.dataset.pane === side));
  if (focus) $(`[data-list="${side}"]`).focus({ preventScroll: true });
  renderHints();
}

function renderHints() {
  const hasSelection = tabFor().selected.size > 0;
  const hints = hasSelection
    ? [["F5", "Копировать", "copy"], ["Space", "Отметить", "mark"], ["Esc", "Снять выделение", "clear-selection"], ["Tab", "Другая панель", "switch-panel"]]
    : [["gT", "Предыдущая вкладка", "previous-tab"], ["gt", "Следующая вкладка", "next-tab"], ["Tab", "Другая панель", "switch-panel"], ["F3", "Просмотр", "view"], ["F5", "Копировать", "copy"]];
  $("#hint-group").innerHTML = hints.filter(([, , action]) => !action.endsWith("-tab") || state[state.active].tabs.length > 1)
    .map(([keys, label, action]) => `<button class="hint" data-action="${action}" title="${label}"><kbd>${keys}</kbd>${label}</button>`).join("");
  fitHints();
}

function fitHints() {
  const group = $("#hint-group");
  const gap = Number.parseFloat(getComputedStyle(group).columnGap);
  const children = [...group.children];
  children.forEach((child) => { child.hidden = false; });
  let used = 0;
  let fits = true;
  for (const child of children) {
    used += child.getBoundingClientRect().width + (used ? gap : 0);
    fits = fits && used <= group.clientWidth;
    child.hidden = !fits;
  }
}

function navigate(path, side = state.active) {
  activate(side, false);
  const current = tabFor(side);
  if (!folders.has(path)) folders.set(path, []);
  current.path = path;
  current.cursor = "..";
  current.selected.clear();
  renderPane(side);
  $(`[data-list="${side}"]`).scrollTop = 0;
  activate(side);
}

function goParent(side = state.active) {
  const path = tabFor(side).path;
  const parent = parentPath(path);
  if (!folders.has(parent)) folders.set(parent, [folder(basename(path))]);
  navigate(parent, side);
  tabFor(side).cursor = basename(path);
  updateRows(side);
}

function switchTab(delta, side = state.active) {
  const pane = state[side];
  pane.index = (pane.index + delta + pane.tabs.length) % pane.tabs.length;
  renderPane(side);
  activate(side);
}

function markCursor() {
  const tab = tabFor();
  if (tab.cursor === "..") return;
  if (tab.selected.has(tab.cursor)) tab.selected.delete(tab.cursor);
  else tab.selected.add(tab.cursor);
  updateRows(state.active);
}

function showNotice(message) {
  clearTimeout(state.toastTimer);
  $("#toast").textContent = message;
  $("#toast").hidden = false;
  state.toastTimer = setTimeout(() => { $("#toast").hidden = true; }, 2400);
}

function showDialog(title, html, confirm = null) {
  state.pendingAction = confirm;
  $("#action-title").textContent = title;
  $("#action-body").innerHTML = html;
  $("#action-confirm").hidden = !confirm;
  $("#action-dialog").returnValue = "";
  $("#action-dialog").showModal();
}

function showCopy() {
  const targets = targetsFor();
  if (!targets.length) return showNotice("Сначала выберите файл или папку");
  if (state.copying) return showNotice("Демонстрация копирования уже запущена");
  const destination = tabFor(opposite()).path;
  if (destination === tabFor().path) return showNotice("Откройте другую папку в противоположной панели");
  showDialog("Копировать в другую панель", `<p>${targets.length === 1 ? escapeHtml(targets[0].name) : `Выбрано элементов: ${targets.length}`}</p><p class="muted">Папка назначения</p><code class="destination">${escapeHtml(destination)}</code>`, () => simulateCopy(targets, destination));
}

function simulateCopy(targets, destination) {
  state.copying = true;
  $("#operations").hidden = false;
  $("#operation-label").textContent = `Копирование: ${targets.length} → ${basename(destination)}`;
  let progress = 0;
  $("#operation-progress").value = 0;
  $("#operation-percent").textContent = "0%";
  const timer = setInterval(() => {
    progress = Math.min(100, progress + 20);
    $("#operation-progress").value = progress;
    $("#operation-percent").textContent = `${progress}%`;
    if (progress < 100) return;
    clearInterval(timer);
    const contents = folders.get(destination) ?? [];
    for (const entry of targets) {
      let name = entry.name;
      let suffix = 1;
      while (contents.some((other) => other.name === name)) name = `${entry.name} (копия ${suffix++})`;
      contents.push({ ...entry, name });
    }
    folders.set(destination, contents);
    for (const side of ["left", "right"]) if (tabFor(side).path === destination) renderPane(side);
    state.copying = false;
    $("#operations").hidden = true;
    showNotice("Готово — копия добавлена в демопапку");
  }, 160);
}

function showViewer() {
  const entry = entriesFor(state.active).find((item) => item.name === tabFor().cursor);
  if (!entry || entry.kind === "parent") return goParent();
  if (entry.kind === "folder") return navigate(`${tabFor().path}/${entry.name}`);
  const text = entry.name.endsWith(".md")
    ? `# Ferryx\n\nA dual-pane file manager for the desktop.\nBuilt for the keyboard.\n\n## Interface\n\nTwo panels. Tabs. Clear focus.\nThe file list stays at 13 px / 22 px.\n\n## Stack\n\nFlutter · Dart · Rust`
    : `${entry.name}\n\nРазмер: ${entry.size}\nИзменён: ${entry.date}\nПрава: ${entry.permissions}\n\nДемонстрация встроенного просмотра.`;
  showDialog(entry.name, `<pre class="preview-code">${escapeHtml(text)}</pre>`);
}

function showShortcuts() {
  const shortcuts = [
    ["Другой вариант оформления", "Кнопки A / B / C"],
    ["Другая панель из списка файлов", "Tab"],
    ["Следующая / предыдущая вкладка", "gt / gT"],
    ["Переместить курсор", "↑ / ↓"],
    ["Отметить файл отдельно от курсора", "Space"],
    ["Открыть папку / просмотреть файл", "Enter / F3"],
    ["Копировать в демопапку", "F5"],
    ["Палитра команд", "⌘P / Ctrl+P"],
    ["Выйти из списка к кнопкам", "Shift+Tab"],
  ];
  showDialog("Сочетания в прототипе", shortcuts.map(([label, keys]) => `<div class="shortcut-row"><span>${label}</span><kbd>${keys}</kbd></div>`).join(""));
}

const commands = [
  { label: "Копировать в другую панель", keys: "F5", icon: "copy", action: "copy", alias: "copy" },
  { label: "Просмотреть файл", keys: "F3", icon: "eye", action: "view", alias: "view preview" },
  { label: "Новая вкладка", keys: "⌘T", icon: "plus", action: "new-tab", alias: "new tab" },
  { label: "Следующая вкладка", keys: "gt", icon: "folder", action: "next-tab", alias: "next tab" },
  { label: "Перейти в другую панель", keys: "Tab", icon: "panel", action: "switch-panel", alias: "switch panel" },
  { label: "Изменить направление сортировки", keys: "⌃⌘1", icon: "sort", action: "sort", alias: "sort name" },
  { label: "Показать / скрыть терминал", keys: "⌃`", icon: "terminal", action: "terminal", alias: "terminal" },
  { label: "Сочетания клавиш", keys: "⌘/", icon: "keyboard", action: "shortcuts", alias: "shortcuts help" },
];

function matchingCommands() {
  const query = $("#command-query").value.trim().toLocaleLowerCase();
  return commands.filter((command) => `${command.label} ${command.alias}`.toLocaleLowerCase().includes(query));
}

function renderCommands() {
  const matches = matchingCommands();
  state.paletteIndex = Math.max(0, Math.min(state.paletteIndex, matches.length - 1));
  $("#palette-results").innerHTML = matches.length ? matches.map((command, index) => `<button class="palette-result${index === state.paletteIndex ? " is-current" : ""}" data-command="${command.action}">${icon(command.icon)}<span>${command.label}</span><kbd>${escapeHtml(command.keys)}</kbd></button>`).join("") : '<div class="file-empty">Команда не найдена</div>';
}

function openPalette() {
  $("#command-query").value = "";
  state.paletteIndex = 0;
  $("#palette-scope").textContent = `${state.active === "left" ? "Левая" : "Правая"} панель · ${tabFor().path.replace(home, "~")}`;
  renderCommands();
  $("#palette").showModal();
  $("#command-query").focus();
}

function runAction(action, side = state.active, data = {}) {
  if (side !== state.active) activate(side, false);
  const pane = state[side];
  switch (action) {
    case "parent": goParent(side); break;
    case "navigate": navigate(data.path, side); break;
    case "commands": openPalette(); break;
    case "next-tab": switchTab(1, side); break;
    case "previous-tab": switchTab(-1, side); break;
    case "switch-panel": activate(opposite()); break;
    case "new-tab":
      pane.tabs.push(newTab(tabFor(side).path));
      pane.index = pane.tabs.length - 1;
      renderPane(side); activate(side); break;
    case "close-tab": {
      if (pane.tabs.length === 1) return showNotice("Оставлена последняя вкладка панели");
      const index = Number(data.index);
      pane.tabs.splice(index, 1);
      if (index < pane.index) pane.index--;
      pane.index = Math.min(pane.index, pane.tabs.length - 1);
      renderPane(side); activate(side); break;
    }
    case "tab": pane.index = Number(data.index); renderPane(side); activate(side); break;
    case "sort":
    case "sort-name": tabFor(side).descending = !tabFor(side).descending; renderPane(side); break;
    case "copy": showCopy(); break;
    case "view": showViewer(); break;
    case "mark": markCursor(); break;
    case "clear-selection": tabFor().selected.clear(); updateRows(side); break;
    case "terminal": $("#terminal").hidden = !$("#terminal").hidden; break;
    case "shortcuts": showShortcuts(); break;
  }
}

const variants = {
  blueprint: "A / Чертёж — синий моноширинный текст, тонкие контуры и прямые углы. Ближе всего к референсу.",
  balanced: "B / Баланс — цвета и линии референса, привычный шрифт файлов. Рекомендуемый вариант для ежедневной работы.",
  night: "C / Ночной — тот же компактный интерфейс на тёмном синем фоне с мягкими акцентами.",
};

function setTheme(name) {
  if (!(name in variants)) return;
  document.documentElement.dataset.theme = name;
  $$("[data-theme-choice]").forEach((button) => button.setAttribute("aria-pressed", String(button.dataset.themeChoice === name)));
  $("#variant-description").textContent = variants[name];
  const url = new URL(location.href);
  url.searchParams.set("variant", name);
  try { history.replaceState(null, "", url); } catch { /* Some file URL contexts prohibit history updates. */ }
  requestAnimationFrame(fitHints);
}

document.addEventListener("click", (event) => {
  const theme = event.target.closest("[data-theme-choice]");
  if (theme) return setTheme(theme.dataset.themeChoice);
  const command = event.target.closest("[data-command]");
  if (command) {
    $("#palette").close();
    return runAction(command.dataset.command);
  }
  const action = event.target.closest("[data-action]");
  if (action) return runAction(action.dataset.action, action.dataset.side ?? state.active, action.dataset);
  const row = event.target.closest(".file-row");
  if (!row) return;
  const side = row.closest("[data-pane]").dataset.pane;
  activate(side);
  tabFor(side).cursor = row.dataset.name;
  if (event.metaKey || event.ctrlKey || event.shiftKey) markCursor();
  else updateRows(side);
});

document.addEventListener("dblclick", (event) => {
  if (event.target.closest(".file-row")) showViewer();
});

document.addEventListener("focusin", (event) => {
  const list = event.target.closest("[data-list]");
  if (list) activate(list.dataset.list, false);
});

document.addEventListener("keydown", (event) => {
  if ($("dialog[open]")) return;
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "p") {
    event.preventDefault(); openPalette(); return;
  }
  const focusedTab = event.target.closest('[role="tab"]');
  if (focusedTab && (event.key === "Enter" || event.key === " ")) {
    event.preventDefault(); runAction("tab", focusedTab.dataset.side, { index: focusedTab.dataset.tab }); return;
  }
  if (!event.target.closest(".file-list")) return;
  const tab = tabFor();
  const entries = entriesFor(state.active);
  if (state.prefix && (event.key === "t" || event.key === "T")) {
    event.preventDefault(); state.prefix = false;
    switchTab(event.key === "T" ? -1 : 1); return;
  }
  state.prefix = false;
  if (event.key === "g" && !event.metaKey && !event.ctrlKey) {
    state.prefix = true; clearTimeout(state.prefixTimer);
    state.prefixTimer = setTimeout(() => { state.prefix = false; }, 1000);
    return;
  }
  if (event.key === "ArrowDown" || event.key === "ArrowUp" || event.key === "j" || event.key === "k") {
    event.preventDefault();
    const index = entries.findIndex((entry) => entry.name === tab.cursor);
    const delta = event.key === "ArrowDown" || event.key === "j" ? 1 : -1;
    tab.cursor = entries[Math.max(0, Math.min(entries.length - 1, index + delta))].name;
    if (event.shiftKey && tab.cursor !== "..") tab.selected.add(tab.cursor);
    updateRows(state.active);
    $(`[data-list="${state.active}"] .is-cursor`).scrollIntoView({ block: "nearest" });
  } else if (event.key === "Tab" && !event.shiftKey) {
    event.preventDefault(); activate(opposite());
  } else if (event.key === " ") {
    event.preventDefault(); markCursor();
  } else if (event.key === "Enter" || event.key === "F3") {
    event.preventDefault(); showViewer();
  } else if (event.key === "F5") {
    event.preventDefault(); showCopy();
  } else if (event.key === "Escape") {
    tab.selected.clear(); updateRows(state.active);
  } else if (event.key === "Backspace") {
    event.preventDefault(); goParent();
  }
});

$("#command-query").addEventListener("input", () => { state.paletteIndex = 0; renderCommands(); });
$("#command-query").addEventListener("keydown", (event) => {
  if (event.key === "ArrowDown" || event.key === "ArrowUp") {
    event.preventDefault();
    const count = matchingCommands().length;
    if (!count) return;
    state.paletteIndex = (state.paletteIndex + (event.key === "ArrowDown" ? 1 : -1) + count) % count;
    renderCommands();
    $(".palette-result.is-current")?.scrollIntoView({ block: "nearest" });
  } else if (event.key === "Enter") {
    event.preventDefault();
    const command = matchingCommands()[state.paletteIndex];
    if (command) { $("#palette").close(); runAction(command.action); }
  }
});

$("#action-dialog").addEventListener("close", () => {
  const callback = state.pendingAction;
  state.pendingAction = null;
  if ($("#action-dialog").returnValue === "confirm") callback?.();
  activate(state.active);
});

for (const element of $$("[data-icon]")) element.innerHTML = icon(element.dataset.icon);
const query = new URLSearchParams(location.search);
document.body.classList.toggle("capture", query.has("capture"));
renderPane("left");
renderPane("right");
setTheme(query.get("variant") ?? "balanced");
new ResizeObserver(fitHints).observe($("#hint-group"));
document.fonts.ready.then(fitHints);
activate("left");
