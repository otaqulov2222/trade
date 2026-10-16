const form = document.querySelector("#connect-form");
const startButton = document.querySelector("#start");
const stopButton = document.querySelector("#stop");

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
  return Number(value).toLocaleString("en-US", { maximumFractionDigits: 2 });
}

const WORDS = {
  RANGING: "Yonlama",
  WAIT: "Kutilmoqda",
  NO_TRADE: "Savdo yo'q",
  BUY: "Xarid",
  SELL: "Sotuv",
  DATA_UNAVAILABLE: "Ma'lumot yo'q",
  TRENDING_UP: "Yuqori trend",
  TRENDING_DOWN: "Pastki trend",
  HIGH_VOLATILITY: "Yuqori tebranish",
  LOW_LIQUIDITY: "Past likvidlik",
  UNCERTAIN: "Noaniq",
  BREAKOUT_CANDIDATE: "Sinish nomzodi",
  flat: "tekis",
  up: "yuqori",
  down: "past",
  none: "yo'q",
  normal: "oddiy",
  invalid: "yaroqsiz",
  compressed: "siqilgan",
  expanded: "kengaygan",
  robot_stopped: "robot to'xtagan",
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
  "Trend H1/M15/M5": "H1, M15, M5 trend",
  "Structure BOS/FVG": "Struktura",
  "Liquidity sweep": "Likvidlik",
  "Fibonacci value": "Fibonachchi",
};

function uz(value) {
  if (value === undefined || value === null || value === "") return "—";
  return WORDS[value] || String(value);
}

function pill(node, text, kind) {
  node.textContent = text;
  node.className = "pill " + (kind || "");
}

function render(state) {
  pill(
    document.querySelector("#pill-terminal"),
    state.mt5_available ? "Terminal tayyor" : "Terminal yo'q",
    state.mt5_available ? "ok" : "warn"
  );
  pill(
    document.querySelector("#pill-account"),
    state.connected ? "Hisob ulangan" : "Hisob ulanmagan",
    state.connected ? "ok" : ""
  );
  pill(
    document.querySelector("#pill-robot"),
    state.running ? "Robot ishlayapti" : "Robot to'xtagan",
    state.running ? "ok" : "bad"
  );

  startButton.disabled = !state.connected || state.running;
  stopButton.disabled = !state.running;

  const account = state.account || {};
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
  document.querySelector("#headline").textContent = `${uz(analysis.regime)} · ${uz(analysis.signal)}`;
  document.querySelector("#message").textContent = uz(state.message || "");
  const metrics = [
    ["Yo'nalish", uz(analysis.direction)],
    ["Tebranish", uz(analysis.volatility)],
    ["Spred", analysis.spread_points == null ? "—" : Number(analysis.spread_points).toFixed(1)],
    ["Sessiya", analysis.session_open ? "ochiq" : "yopiq"],
    ["O'rtacha tebranish", analysis.atr == null ? "—" : Number(analysis.atr).toFixed(2)],
    ["Hajm", analysis.volume == null ? "—" : Number(analysis.volume).toFixed(2)],
    ["Ball", `${analysis.buy_score || 0} / ${analysis.sell_score || 0}`],
    ["Holat", uz(analysis.gate)],
  ];
  document.querySelector("#metrics").innerHTML = metrics
    .map(([label, value]) => `<div class="metric"><span>${escapeHtml(label)}</span><strong>${escapeHtml(value)}</strong></div>`)
    .join("");
  document.querySelector("#votes").innerHTML = (analysis.votes || [])
    .map((vote) => `<div class="vote"><span>${escapeHtml(uz(vote.name))}</span><strong>${escapeHtml(uz(vote.direction))}</strong></div>`)
    .join("");

  const positions = state.positions || [];
  const positionBox = document.querySelector("#positions");
  if (!positions.length) positionBox.textContent = "Hozircha yo'q";
  else {
    positionBox.innerHTML = positions
      .map((item) => `${escapeHtml(item.owner === "qolda" ? "Qo'lda" : "Robot")} ${escapeHtml(uz(item.type))} ${escapeHtml(item.volume)} @ ${escapeHtml(item.price_open)}, foyda ${escapeHtml(money(item.profit))}`)
      .join("<br>");
  }
  document.querySelector("#journal").innerHTML = (state.journal || []).map((line) => `<li>${escapeHtml(line)}</li>`).join("");
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
  await post("/api/connect", {
    login: formData.get("login"),
    server: formData.get("server"),
    password: formData.get("password"),
    symbol: formData.get("symbol"),
  });
  form.password.value = "";
});

document.querySelector("#disconnect").addEventListener("click", () => post("/api/disconnect"));
startButton.addEventListener("click", () => post("/api/start"));
stopButton.addEventListener("click", () => post("/api/stop"));

async function refresh() {
  const response = await fetch("/api/state");
  render(await response.json());
}

refresh();
setInterval(refresh, 2000);
