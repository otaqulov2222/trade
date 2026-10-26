const form = document.querySelector("#connect-form");
const startButton = document.querySelector("#start");
const stopButton = document.querySelector("#stop");
const settingsModal = document.querySelector("#settings-modal");

function openSettings() {
  settingsModal.hidden = false;
  document.body.style.overflow = "hidden";
}

function closeSettings() {
  settingsModal.hidden = true;
  document.body.style.overflow = "";
}

function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>"']/g, (char) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    "\"": "&quot;",
    "'": "&#39;",
  }[char]));
}

function money(value) {
  if (value === undefined || value === null || Number.isNaN(Number(value))) return "—";
  return Number(value).toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function signed(value) {
  const num = Number(value) || 0;
  const text = money(Math.abs(num));
  return num > 0 ? `+${text}` : num < 0 ? `-${text}` : text;
}

const WORDS = {
  RANGING: "Yonlama",
  WAIT: "Kutilmoqda",
  NO_TRADE: "Savdo yo'q",
  BUY: "BUY",
  SELL: "SELL",
  STRADDLE: "Straddle",
  BUY_STOP: "BUY STOP",
  SELL_STOP: "SELL STOP",
  DATA_UNAVAILABLE: "Ma'lumot yo'q",
  TRENDING_UP: "Yuqori trend",
  TRENDING_DOWN: "Pastki trend",
  HIGH_VOLATILITY: "Yuqori tebranish",
  LOW_LIQUIDITY: "Past likvidlik",
  UNCERTAIN: "Noaniq",
  BREAKOUT_CANDIDATE: "Sinish nomzodi",
  SQUEEZE: "Siqilish",
  flat: "tekis",
  up: "yuqori",
  down: "past",
  none: "yo'q",
  normal: "oddiy",
  invalid: "yaroqsiz",
  compressed: "siqilgan",
  expanded: "kengaygan",
  weak_setup: "zaif setup",
  ok: "ok",
  robot_stopped: "Saydirasulov to'xtagan",
  signal_not_actionable: "signal savdoga yaramaydi",
  volume_zero: "hajm nol",
  position_already_open: "pozitsiya allaqachon ochiq",
  position_cap: "3 ta bitim chegarasi",
  daily_loss: "kunlik zarar chegarasi",
  hard_drawdown: "cho'qqidan pasayish",
  account_not_connected: "hisob ulanmagan",
  session_closed: "sessiya yopiq",
  spread_wide: "spred keng",
  min_lot: "minimal lot sig'maydi",
  running: "ishlayapti",
};

function uz(value) {
  if (value === undefined || value === null || value === "") return "—";
  return WORDS[value] || String(value);
}

function pill(node, text, kind) {
  node.className = "pill " + (kind || "");
  node.replaceChildren();
  const dot = document.createElement("i");
  dot.className = "dot";
  node.append(dot, document.createTextNode(text));
}

function setMoney(id, value, withSign) {
  const node = document.querySelector(id);
  const num = Number(value) || 0;
  node.textContent = withSign ? signed(num) : money(Math.abs(num));
}

function renderDay(day) {
  const data = day || {};
  setMoney("#day-profit", data.day_profit || 0, true);
  document.querySelector("#day-loss").textContent = money(data.day_loss || 0);
  setMoney("#day-net", data.day_net || 0, true);
  setMoney("#day-float", data.floating || 0, true);

  const buy = document.querySelector("#side-buy");
  const sell = document.querySelector("#side-sell");
  const pending = document.querySelector("#side-pending");
  buy.textContent = `BUY ${data.buy_open || 0}`;
  sell.textContent = `SELL ${data.sell_open || 0}`;
  pending.textContent = `STOP ${data.pending || 0}`;
  buy.className = `tag buy${data.buy_open ? "" : " off"}`;
  sell.className = `tag sell${data.sell_open ? "" : " off"}`;
  pending.className = `tag pending${data.pending ? "" : " off"}`;
}

function renderGuard(risk, day) {
  const cool = Number(risk && risk.cooldown_left) || 0;
  const consec = Number(risk && risk.consec_losses) || 0;
  const closed = Number(day && day.closed_trades) || 0;
  const node = document.querySelector("#day-guard");
  const sub = document.querySelector("#day-closed");
  if (cool > 0) node.textContent = `${cool}s pauza`;
  else if (consec > 0) node.textContent = `${consec} ta minus ketma-ket`;
  else node.textContent = "tayyor";
  sub.textContent = `Yopilgan: ${closed}`;
}

function renderRisk(risk) {
  const data = risk || {};
  const cool = Number(data.cooldown_left) || 0;
  const box = document.querySelector("#limits");
  box.innerHTML = `
    <li class="risk-item"><span>Kirish masofasi</span><strong>${escapeHtml(data.distance == null ? "—" : Number(data.distance).toFixed(2))}</strong></li>
    <li class="risk-item"><span>Qattiq stop</span><strong>${escapeHtml(data.hedge == null ? "—" : Number(data.hedge).toFixed(2))}</strong></li>
    <li class="risk-item"><span>Take profit</span><strong>${escapeHtml(data.take_profit == null ? "—" : Number(data.take_profit).toFixed(2))}</strong></li>
    <li class="risk-item"><span>Break-even</span><strong>${escapeHtml(data.break_even == null ? "—" : Number(data.break_even).toFixed(2))}</strong></li>
    <li class="risk-item"><span>Lot swing</span><strong>${escapeHtml(data.lot_swing == null ? "0.05" : Number(data.lot_swing).toFixed(2))}</strong></li>
    <li class="risk-item"><span>Lot M1</span><strong>${escapeHtml(data.lot_scalp == null ? "0.01" : Number(data.lot_scalp).toFixed(2))}</strong></li>
    <li class="risk-item"><span>Lot tavan</span><strong>${escapeHtml(data.lot_cap == null ? "—" : Number(data.lot_cap).toFixed(2))}</strong></li>
    <li class="risk-item"><span>Signal daraja</span><strong>${escapeHtml(data.grade || "skip")}</strong></li>
    <li class="risk-item"><span>Teskari masofa</span><strong>${escapeHtml(data.reverse_distance == null ? "—" : Number(data.reverse_distance).toFixed(2))}</strong></li>
    <li class="risk-item"><span>Kunlik zarar</span><strong>${escapeHtml(String(data.daily_loss_percent ?? "—"))}%</strong></li>
    <li class="risk-item"><span>Ketma-ket zarar</span><strong>${escapeHtml(`${data.consec_losses ?? 0} / ${data.max_consec_losses ?? 2}`)}</strong></li>
    <li class="risk-item"><span>Sessiya bitimlari</span><strong>${escapeHtml(`${data.session_trades ?? 0} / ${data.max_daily_trades ?? 20}`)}</strong></li>
    <li class="risk-item"><span>Pauza</span><strong>${escapeHtml(cool > 0 ? `${cool}s` : "yo'q")}</strong></li>
    <li class="risk-item"><span>Pro stack</span><strong>${escapeHtml(`${data.pro_buy ?? 0} / ${data.pro_sell ?? 0}`)}</strong></li>
    <li class="risk-note">Lot 0.01 / 0.05 / 0.50 / 1.00 faqat equity va signal kuchiga qarab. $1k da 0.50–1.00 ochilmaydi. CPI/PPI/NFP/FOMC oldidan yangi bitim yo'q.</li>
  `;
}

function tradeCard(item) {
  const isBuy = item.type === "BUY" || item.type === "BUY_STOP";
  const isSell = item.type === "SELL" || item.type === "SELL_STOP";
  const kind = [isBuy ? "buy" : "", isSell ? "sell" : "", item.pending ? "pending" : ""].filter(Boolean).join(" ") || "pending";
  const comment = String(item.comment || "");
  const vol = Number(item.volume) || 0;
  let owner = item.owner === "qolda" ? "Qo'lda" : "Saydirasulov";
  if (item.owner !== "qolda") {
    if (comment.includes("swing") || vol >= 0.045) owner = "Swing 0.05";
    else if (item.pending || comment.includes("rev")) owner = "Teskari";
    else owner = "M1 0.01";
  }
  const profit = Number(item.profit) || 0;
  const hasStop = Number(item.sl) > 0;
  const stopLabel = item.pending ? "Buyruq" : "Stop";
  const stopValue = item.pending
    ? money(item.price_open)
    : hasStop
      ? money(item.sl)
      : "qo'yilmoqda";
  const status = item.pending
    ? "Kutilmoqda"
    : hasStop
      ? "Himoyalangan"
      : "Stop kutilmoqda";
  return `
    <article class="trade ${kind}">
      <div class="trade-top">
        <span class="kind">${escapeHtml(uz(item.type))}</span>
        <span class="owner">${escapeHtml(owner)}</span>
      </div>
      <div class="trade-grid">
        <div><span>Lot</span><strong>${escapeHtml(Number(item.volume).toFixed(2))}</strong></div>
        <div><span>${item.pending ? "Buyruq" : "Ochilish"}</span><strong>${escapeHtml(money(item.price_open))}</strong></div>
        <div><span>${stopLabel}</span><strong class="${hasStop || item.pending ? "" : "warn-text"}">${escapeHtml(stopValue)}</strong></div>
        <div><span>${item.pending ? "Holat" : "Foyda"}</span><strong class="${item.pending ? "" : "pnl"}">${escapeHtml(item.pending ? status : signed(profit))}</strong></div>
      </div>
      ${item.pending ? "" : `<p class="trade-status">${escapeHtml(status)}</p>`}
    </article>
  `;
}

function render(state) {
  pill(
    document.querySelector("#pill-terminal"),
    state.mt5_available ? "Terminal tayyor" : "Terminal yo'q",
    state.mt5_available ? "live" : "warn"
  );
  pill(
    document.querySelector("#pill-account"),
    state.connected ? "Hisob ulangan" : "Hisob ulanmagan",
    state.connected ? "live" : "idle"
  );
  pill(
    document.querySelector("#pill-robot"),
    state.running ? "Saydirasulov ishlayapti" : "Saydirasulov to'xtagan",
    state.running ? "live" : "idle"
  );

  startButton.disabled = !state.connected || state.running;
  stopButton.disabled = !state.running;

  renderDay(state.day);
  renderGuard(state.risk, state.day);
  renderRisk(state.risk);

  const account = state.account || {};
  document.querySelector("#acc-login").textContent = account.login || "—";
  document.querySelector("#acc-server").textContent = account.server || "—";
  document.querySelector("#acc-symbol").textContent = state.symbol || "—";
  document.querySelector("#acc-balance").textContent = money(account.balance);
  document.querySelector("#acc-equity").textContent = money(account.equity);
  document.querySelector("#acc-margin").textContent = money(account.margin_free);
  const facts = document.querySelector("#account-facts");
  const rows = [
    ["Login", account.login],
    ["Server", account.server],
    ["Ism", account.name],
    ["Valyuta", account.currency],
    ["Balans", money(account.balance)],
    ["Sof kapital", money(account.equity)],
    ["Bo'sh marja", money(account.margin_free)],
    ["Savdo", account.trade_allowed ? "ruxsat" : account.login ? "o'chiq" : "—"],
  ];
  facts.innerHTML = rows
    .map(([label, value]) => `<div><dt>${escapeHtml(label)}</dt><dd>${escapeHtml(value)}</dd></div>`)
    .join("");

  const analysis = state.analysis || {};
  const signal = analysis.signal;
  document.querySelector("#headline-regime").textContent = uz(analysis.regime);
  const signalNode = document.querySelector("#headline-signal");
  signalNode.textContent = signal ? uz(signal) : "";
  signalNode.className = `sig${signal === "BUY" ? " buy" : signal === "SELL" ? " sell" : ""}`;
  document.querySelector("#message").textContent = uz(state.message || "");
  const metrics = [
    ["Yo'nalish", uz(analysis.direction)],
    ["Tebranish", uz(analysis.volatility)],
    ["Spred", analysis.spread_points == null ? "—" : Number(analysis.spread_points).toFixed(1)],
    ["Sessiya", analysis.session_open ? "ochiq" : "yopiq"],
    ["Masofa", analysis.atr == null ? "—" : Number(analysis.atr).toFixed(2)],
    ["Hajm", analysis.volume == null ? "—" : Number(analysis.volume).toFixed(2)],
    ["Ball", `${analysis.buy_score || 0} / ${analysis.sell_score || 0}`],
    ["Pro", `${analysis.pro_buy || 0} / ${analysis.pro_sell || 0}`],
    ["Holat", uz(analysis.gate)],
    ["Daraja", analysis.grade || "skip"],
  ];
  document.querySelector("#metrics").innerHTML = metrics
    .map(([label, value]) => `<div class="metric"><span>${escapeHtml(label)}</span><strong>${escapeHtml(value)}</strong></div>`)
    .join("");
  document.querySelector("#votes").innerHTML = (analysis.votes || [])
    .map((vote) => {
      const mark = vote.pro ? " ★" : "";
      const tone = vote.direction === "up" ? "up" : vote.direction === "down" ? "down" : "flat";
      return `<div class="vote ${tone}"><span>${escapeHtml(vote.name)}${mark}</span><strong>${escapeHtml(uz(vote.direction))}</strong></div>`;
    })
    .join("");

  const positions = state.positions || [];
  const positionBox = document.querySelector("#positions");
  const posCount = document.querySelector("#pos-count");
  if (posCount) posCount.textContent = String(positions.length);
  if (!positions.length) {
    positionBox.className = "positions empty";
    positionBox.textContent = "Hozircha yo'q";
  } else {
    positionBox.className = "positions";
    positionBox.innerHTML = positions.map(tradeCard).join("");
  }
  document.querySelector("#journal").innerHTML = (state.journal || [])
    .map((line) => `<li>${escapeHtml(line)}</li>`)
    .join("");
  renderNews(state.news || {}, analysis);
}

function renderNews(news, analysis) {
  const status = document.querySelector("#news-status");
  const list = document.querySelector("#news-list");
  if (!status || !list) return;
  const sources = (news.sources || []).join(" + ") || "kutilmoqda";
  if (news.block) status.textContent = news.reason || "Yangilik. Yangi bitim yopiq";
  else if (news.nearby) status.textContent = `Yaqin yangilik. Lot kichraytirildi. Manba: ${sources}`;
  else if (news.checked) status.textContent = `Kalendar ulangan (${sources}). CPI/PPI/NFP/FOMC hisobga olinadi.`;
  else status.textContent = "Yangilik kalendari yuklanmoqda…";
  const events = news.events || analysis.news_events || [];
  list.innerHTML = events
    .slice(0, 6)
    .map((row) => {
      const mins = Number(row.minutes);
      const when = Number.isFinite(mins)
        ? (mins >= 0 ? `${mins} daqiqa` : `${Math.abs(mins)} daqiqa oldin`)
        : "";
      const tone = row.impact === "High" ? "high" : "";
      return `<li class="${tone}"><span><strong>${escapeHtml(row.currency || "")}</strong> ${escapeHtml(row.title || "")}</span><em>${escapeHtml(row.impact || "")} ${escapeHtml(when)}</em></li>`;
    })
    .join("");
}

async function post(url, payload) {
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload || {}),
  });
  const data = await response.json();
  if (data.state) render(data.state);
  if (!response.ok) document.querySelector("#message").textContent = data.message || "So'rov rad etildi";
  return data;
}

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  const formData = new FormData(form);
  const data = await post("/api/connect", {
    login: formData.get("login"),
    server: formData.get("server"),
    password: formData.get("password"),
    symbol: formData.get("symbol"),
  });
  form.password.value = "";
  if (data && data.ok) closeSettings();
});

document.querySelector("#disconnect").addEventListener("click", () => post("/api/disconnect"));
document.querySelector("#open-settings").addEventListener("click", openSettings);
document.querySelector("#close-settings").addEventListener("click", closeSettings);
settingsModal.querySelectorAll("[data-close-settings]").forEach((node) => {
  node.addEventListener("click", closeSettings);
});
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && !settingsModal.hidden) closeSettings();
});
startButton.addEventListener("click", () => post("/api/start"));
stopButton.addEventListener("click", () => post("/api/stop"));

async function refresh() {
  const response = await fetch("/api/state");
  render(await response.json());
}

function tickClock() {
  const node = document.querySelector("#clock");
  if (!node) return;
  node.textContent = new Date().toLocaleTimeString("uz-UZ", { hour12: false });
}

refresh();
tickClock();
setInterval(refresh, 2000);
setInterval(tickClock, 1000);
