"use strict";

const http = require("node:http");
const path = require("node:path");
const fs = require("node:fs");
const crypto = require("node:crypto");
const { promisify } = require("node:util");
const { WebSocketServer, WebSocket } = require("ws");

const scrypt = promisify(crypto.scrypt);
const port = Number(process.env.PORT || 8080);
const webRoot = path.join(__dirname, "web");
const maxPlayers = 12;
const players = new Map();
const sessions = new Map();
const databaseUrl = process.env.DATABASE_URL || "";
const { Pool } = databaseUrl ? require("pg") : { Pool: null };
const googleClientId = process.env.GOOGLE_CLIENT_ID || "";
const googleClientSecret = process.env.GOOGLE_CLIENT_SECRET || "";
const publicServerUrl = process.env.PUBLIC_SERVER_URL || "https://car-company-empire-online.onrender.com";
const publicGameUrl = process.env.PUBLIC_GAME_URL || "https://car-company-empire.onrender.com";
const googleRedirectUri = `${publicServerUrl}/auth/google/callback`;
const oauthStates = new Map();
const oauthCodes = new Map();
const localDataPath = path.join(__dirname, ".data", "accounts.json");
const pool = databaseUrl
  ? new Pool({ connectionString: databaseUrl, ssl: { rejectUnauthorized: false } })
  : null;
let localAccounts = {};
let nextPlayerId = 1;

const starterProgress = Object.freeze({
  money: 25000,
  reputation: 0,
  company_level: 1,
  research: 0,
  inventory: {
    Chassis: 1,
    Engine: 1,
    Transmission: 1,
    Wheels: 1,
    Electronics: 0,
  },
  cars: [],
  total_built: 0,
  total_sales: 0,
  objective_stage: 0,
  player_position: { x: 86, y: 0.1, z: 52 },
});

const contentTypes = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".wasm": "application/wasm",
  ".pck": "application/octet-stream",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".json": "application/json; charset=utf-8",
};

function cloneStarterProgress() {
  return JSON.parse(JSON.stringify(starterProgress));
}

function cleanUsername(value) {
  return String(value || "")
    .replace(/[^a-zA-Z0-9_ -]/g, "")
    .trim()
    .slice(0, 18);
}

function cleanCompany(value) {
  return String(value || "")
    .replace(/[^\p{L}\p{N}&' ._-]/gu, "")
    .trim()
    .slice(0, 32);
}

function cleanColor(value) {
  const color = String(value || "").replace(/^#/, "");
  return /^[0-9a-fA-F]{6}$/.test(color) ? color.toLowerCase() : "1677ff";
}

function cleanNumber(value, fallback, minimum, maximum) {
  const number = Number(value);
  return Number.isFinite(number)
    ? Math.max(minimum, Math.min(maximum, Math.round(number)))
    : fallback;
}

function sanitizeProgress(value) {
  const source = value && typeof value === "object" ? value : {};
  const inventorySource = source.inventory && typeof source.inventory === "object"
    ? source.inventory
    : {};
  const positionSource = source.player_position && typeof source.player_position === "object"
    ? source.player_position
    : {};
  const carsSource = Array.isArray(source.cars) ? source.cars.slice(0, 100) : [];
  return {
    money: cleanNumber(source.money, 25000, 0, 1_000_000_000),
    reputation: cleanNumber(source.reputation, 0, 0, 10_000_000),
    company_level: cleanNumber(source.company_level, 1, 1, 1000),
    research: cleanNumber(source.research, 0, 0, 1000),
    inventory: {
      Chassis: cleanNumber(inventorySource.Chassis, 1, 0, 100000),
      Engine: cleanNumber(inventorySource.Engine, 1, 0, 100000),
      Transmission: cleanNumber(inventorySource.Transmission, 1, 0, 100000),
      Wheels: cleanNumber(inventorySource.Wheels, 1, 0, 100000),
      Electronics: cleanNumber(inventorySource.Electronics, 0, 0, 100000),
    },
    cars: carsSource.map((car, index) => {
      const item = car && typeof car === "object" ? car : {};
      return {
        name: String(item.name || `MODEL ${index + 1}`).trim().slice(0, 24),
        quality: cleanNumber(item.quality, 1, 1, 1000),
        color: cleanColor(item.color),
      };
    }),
    total_built: cleanNumber(source.total_built, 0, 0, 10_000_000),
    total_sales: cleanNumber(source.total_sales, 0, 0, 10_000_000),
    objective_stage: cleanNumber(source.objective_stage, 0, 0, 4),
    player_position: {
      x: Math.max(-1000, Math.min(1000, Number(positionSource.x) || 86)),
      y: Math.max(-10, Math.min(100, Number(positionSource.y) || 0.1)),
      z: Math.max(-1000, Math.min(1000, Number(positionSource.z) || 52)),
    },
  };
}

async function hashPassword(password) {
  const salt = crypto.randomBytes(16).toString("hex");
  const derived = await scrypt(password, salt, 64);
  return `${salt}:${Buffer.from(derived).toString("hex")}`;
}

async function verifyPassword(password, stored) {
  const [salt, expectedHex] = String(stored || "").split(":");
  if (!salt || !expectedHex) {
    return false;
  }
  const actual = Buffer.from(await scrypt(password, salt, 64));
  const expected = Buffer.from(expectedHex, "hex");
  return actual.length === expected.length && crypto.timingSafeEqual(actual, expected);
}

async function initializeStore() {
  if (pool) {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS accounts (
        id BIGSERIAL PRIMARY KEY,
        username VARCHAR(18) NOT NULL,
        username_key VARCHAR(18) UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        company VARCHAR(32) NOT NULL,
        color VARCHAR(6) NOT NULL,
        progress JSONB NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);
    await pool.query("ALTER TABLE accounts ADD COLUMN IF NOT EXISTS google_sub TEXT");
    await pool.query("ALTER TABLE accounts ADD COLUMN IF NOT EXISTS email TEXT");
    await pool.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS accounts_google_sub_unique
      ON accounts (google_sub)
      WHERE google_sub IS NOT NULL
    `);
    return;
  }
  fs.mkdirSync(path.dirname(localDataPath), { recursive: true });
  try {
    localAccounts = JSON.parse(fs.readFileSync(localDataPath, "utf8"));
  } catch {
    localAccounts = {};
  }
}

function saveLocalAccounts() {
  fs.writeFileSync(localDataPath, JSON.stringify(localAccounts, null, 2));
}

async function findAccount(username) {
  const usernameKey = cleanUsername(username).toLowerCase();
  if (pool) {
    const result = await pool.query(
      "SELECT * FROM accounts WHERE username_key = $1 LIMIT 1",
      [usernameKey],
    );
    return result.rows[0] || null;
  }
  return localAccounts[usernameKey] || null;
}

async function findGoogleAccount(googleSub) {
  if (pool) {
    const result = await pool.query(
      "SELECT * FROM accounts WHERE google_sub = $1 LIMIT 1",
      [googleSub],
    );
    return result.rows[0] || null;
  }
  return Object.values(localAccounts).find((account) => account.google_sub === googleSub) || null;
}

async function createAccount(username, passwordHash, company, color) {
  const record = {
    username,
    username_key: username.toLowerCase(),
    password_hash: passwordHash,
    company,
    color,
    progress: cloneStarterProgress(),
  };
  if (pool) {
    const result = await pool.query(
      `INSERT INTO accounts
        (username, username_key, password_hash, company, color, progress)
       VALUES ($1, $2, $3, $4, $5, $6::jsonb)
       RETURNING *`,
      [
        record.username,
        record.username_key,
        record.password_hash,
        record.company,
        record.color,
        JSON.stringify(record.progress),
      ],
    );
    return result.rows[0];
  }
  localAccounts[record.username_key] = record;
  saveLocalAccounts();
  return record;
}

async function createGoogleAccount(profile) {
  const username = cleanUsername(profile.name || String(profile.email || "").split("@")[0]) || "GOOGLE DRIVER";
  const companyBase = username.replace(/[^a-zA-Z0-9]/g, "").slice(0, 20) || "GOOGLE";
  const usernameKey = `g_${crypto.createHash("sha256").update(profile.sub).digest("hex").slice(0, 16)}`;
  const color = crypto.createHash("sha256").update(profile.sub).digest("hex").slice(0, 6);
  const record = {
    username,
    username_key: usernameKey,
    password_hash: "google-oauth",
    company: `${companyBase} MOTORS`.slice(0, 32),
    color,
    google_sub: profile.sub,
    email: String(profile.email || "").slice(0, 254),
    progress: cloneStarterProgress(),
  };
  if (pool) {
    const result = await pool.query(
      `INSERT INTO accounts
        (username, username_key, password_hash, company, color, google_sub, email, progress)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb)
       RETURNING *`,
      [
        record.username,
        record.username_key,
        record.password_hash,
        record.company,
        record.color,
        record.google_sub,
        record.email,
        JSON.stringify(record.progress),
      ],
    );
    return result.rows[0];
  }
  localAccounts[record.username_key] = record;
  saveLocalAccounts();
  return record;
}

async function updateAccountProgress(usernameKey, progress) {
  const cleanProgress = sanitizeProgress(progress);
  if (pool) {
    const result = await pool.query(
      `UPDATE accounts
       SET progress = $1::jsonb, updated_at = NOW()
       WHERE username_key = $2
       RETURNING *`,
      [JSON.stringify(cleanProgress), usernameKey],
    );
    return result.rows[0] || null;
  }
  const account = localAccounts[usernameKey];
  if (!account) {
    return null;
  }
  account.progress = cleanProgress;
  saveLocalAccounts();
  return account;
}

async function deleteAccount(usernameKey) {
  if (pool) {
    const result = await pool.query(
      "DELETE FROM accounts WHERE username_key = $1 RETURNING username_key",
      [usernameKey],
    );
    return result.rowCount > 0;
  }
  if (!localAccounts[usernameKey]) {
    return false;
  }
  delete localAccounts[usernameKey];
  saveLocalAccounts();
  return true;
}

function publicAccount(account) {
  return {
    username: account.username,
    company: account.company,
    color: account.color,
    progress: sanitizeProgress(account.progress),
  };
}

function createSession(account) {
  const token = crypto.randomBytes(32).toString("hex");
  sessions.set(token, {
    usernameKey: account.username_key,
    createdAt: Date.now(),
  });
  return token;
}

function accountKeyFromRequest(request) {
  const authorization = String(request.headers.authorization || "");
  const token = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
  return sessions.get(token)?.usernameKey || "";
}

function sendJsonResponse(response, status, value) {
  response.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Authorization, Content-Type",
    "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
    "Cache-Control": "no-store",
  });
  response.end(JSON.stringify(value));
}

function readJsonBody(request) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    request.on("data", (chunk) => {
      size += chunk.length;
      if (size > 128 * 1024) {
        reject(new Error("Request too large."));
        request.destroy();
        return;
      }
      chunks.push(chunk);
    });
    request.on("end", () => {
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}"));
      } catch {
        reject(new Error("Invalid JSON."));
      }
    });
    request.on("error", reject);
  });
}

function sendHtml(response, status, title, message) {
  response.writeHead(status, {
    "Content-Type": "text/html; charset=utf-8",
    "Cache-Control": "no-store",
  });
  response.end(`<!doctype html>
<html><head><meta charset="utf-8"><title>${title}</title></head>
<body style="font-family:system-ui;background:#07111d;color:#eef6ff;padding:48px">
<h1>${title}</h1><p>${message}</p>
<p><a style="color:#65d5ff" href="${publicGameUrl}">Return to Car Company Empire</a></p>
</body></html>`);
}

async function handleGoogleOAuth(request, response, requestUrl) {
  if (!googleClientId || !googleClientSecret) {
    sendHtml(
      response,
      503,
      "Google Sign-In is not configured",
      "The game owner must add GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET in Render.",
    );
    return;
  }

  if (requestUrl.pathname === "/auth/google") {
    const state = crypto.randomBytes(24).toString("hex");
    oauthStates.set(state, Date.now());
    const authorizationUrl = new URL("https://accounts.google.com/o/oauth2/v2/auth");
    authorizationUrl.searchParams.set("client_id", googleClientId);
    authorizationUrl.searchParams.set("redirect_uri", googleRedirectUri);
    authorizationUrl.searchParams.set("response_type", "code");
    authorizationUrl.searchParams.set("scope", "openid email profile");
    authorizationUrl.searchParams.set("state", state);
    authorizationUrl.searchParams.set("prompt", "select_account");
    response.writeHead(302, { Location: authorizationUrl.toString(), "Cache-Control": "no-store" });
    response.end();
    return;
  }

  const state = String(requestUrl.searchParams.get("state") || "");
  const issuedAt = oauthStates.get(state);
  oauthStates.delete(state);
  if (!issuedAt || Date.now() - issuedAt > 10 * 60 * 1000) {
    sendHtml(response, 400, "Google Sign-In failed", "The sign-in request expired. Please try again.");
    return;
  }
  const authorizationCode = String(requestUrl.searchParams.get("code") || "");
  if (!authorizationCode) {
    sendHtml(response, 400, "Google Sign-In canceled", "Google did not return an authorization code.");
    return;
  }

  try {
    const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        code: authorizationCode,
        client_id: googleClientId,
        client_secret: googleClientSecret,
        redirect_uri: googleRedirectUri,
        grant_type: "authorization_code",
      }),
    });
    const tokens = await tokenResponse.json();
    if (!tokenResponse.ok || !tokens.id_token) {
      throw new Error("Google token exchange failed.");
    }
    const validationResponse = await fetch(
      `https://oauth2.googleapis.com/tokeninfo?id_token=${encodeURIComponent(tokens.id_token)}`,
    );
    const profile = await validationResponse.json();
    if (
      !validationResponse.ok
      || profile.aud !== googleClientId
      || profile.iss !== "https://accounts.google.com"
      || String(profile.email_verified) !== "true"
      || !profile.sub
    ) {
      throw new Error("Google identity validation failed.");
    }
    let account = await findGoogleAccount(profile.sub);
    if (!account) {
      account = await createGoogleAccount(profile);
    }
    const exchangeCode = crypto.randomBytes(32).toString("hex");
    oauthCodes.set(exchangeCode, {
      usernameKey: account.username_key,
      createdAt: Date.now(),
    });
    const gameUrl = new URL(publicGameUrl);
    gameUrl.searchParams.set("login_code", exchangeCode);
    response.writeHead(302, { Location: gameUrl.toString(), "Cache-Control": "no-store" });
    response.end();
  } catch (error) {
    console.error("Google OAuth error:", error);
    sendHtml(response, 500, "Google Sign-In failed", "Google could not complete sign-in. Please try again.");
  }
}

async function handleApi(request, response, requestUrl) {
  if (request.method === "OPTIONS") {
    sendJsonResponse(response, 204, {});
    return;
  }
  try {
    if (requestUrl.pathname === "/api/signup" && request.method === "POST") {
      const body = await readJsonBody(request);
      const username = cleanUsername(body.username);
      const company = cleanCompany(body.company);
      const password = String(body.password || "");
      if (username.length < 3 || company.length < 2 || password.length < 6) {
        sendJsonResponse(response, 400, {
          error: "Use a 3+ character username, 2+ character company, and 6+ character password.",
        });
        return;
      }
      if (await findAccount(username)) {
        sendJsonResponse(response, 409, { error: "That username is already taken." });
        return;
      }
      const account = await createAccount(
        username,
        await hashPassword(password),
        company,
        cleanColor(body.color),
      );
      const token = createSession(account);
      sendJsonResponse(response, 201, { token, account: publicAccount(account) });
      return;
    }

    if (requestUrl.pathname === "/api/signin" && request.method === "POST") {
      const body = await readJsonBody(request);
      const account = await findAccount(body.username);
      if (!account || !(await verifyPassword(String(body.password || ""), account.password_hash))) {
        sendJsonResponse(response, 401, { error: "Incorrect username or password." });
        return;
      }
      const token = createSession(account);
      sendJsonResponse(response, 200, { token, account: publicAccount(account) });
      return;
    }

    if (requestUrl.pathname === "/api/oauth/exchange" && request.method === "POST") {
      const body = await readJsonBody(request);
      const code = String(body.code || "");
      const pending = oauthCodes.get(code);
      oauthCodes.delete(code);
      if (!pending || Date.now() - pending.createdAt > 2 * 60 * 1000) {
        sendJsonResponse(response, 401, { error: "Google sign-in expired. Please try again." });
        return;
      }
      const account = await findAccount(pending.usernameKey);
      if (!account) {
        sendJsonResponse(response, 404, { error: "Google account not found." });
        return;
      }
      const token = createSession(account);
      sendJsonResponse(response, 200, { token, account: publicAccount(account) });
      return;
    }

    if (requestUrl.pathname === "/api/session" && request.method === "GET") {
      const usernameKey = accountKeyFromRequest(request);
      const account = usernameKey ? await findAccount(usernameKey) : null;
      if (!account) {
        sendJsonResponse(response, 401, { error: "Session expired. Sign in again." });
        return;
      }
      sendJsonResponse(response, 200, { account: publicAccount(account) });
      return;
    }

    if (requestUrl.pathname === "/api/progress" && request.method === "PUT") {
      const usernameKey = accountKeyFromRequest(request);
      if (!usernameKey) {
        sendJsonResponse(response, 401, { error: "Sign in required." });
        return;
      }
      const body = await readJsonBody(request);
      const account = await updateAccountProgress(usernameKey, body.progress);
      if (!account) {
        sendJsonResponse(response, 404, { error: "Account not found." });
        return;
      }
      sendJsonResponse(response, 200, { saved: true });
      return;
    }

    if (requestUrl.pathname === "/api/account" && request.method === "DELETE") {
      const usernameKey = accountKeyFromRequest(request);
      if (!usernameKey) {
        sendJsonResponse(response, 401, { error: "Sign in required." });
        return;
      }
      const deleted = await deleteAccount(usernameKey);
      if (!deleted) {
        sendJsonResponse(response, 404, { error: "Account not found." });
        return;
      }
      for (const [token, session] of sessions) {
        if (session.usernameKey === usernameKey) {
          sessions.delete(token);
        }
      }
      sendJsonResponse(response, 200, { deleted: true });
      return;
    }

    sendJsonResponse(response, 404, { error: "API route not found." });
  } catch (error) {
    if (error.code === "23505") {
      sendJsonResponse(response, 409, { error: "That username is already taken." });
      return;
    }
    console.error("API error:", error);
    sendJsonResponse(response, 500, { error: "The account server had a problem. Try again." });
  }
}

function sendSocketJson(socket, value) {
  if (socket.readyState === WebSocket.OPEN) {
    socket.send(JSON.stringify(value));
  }
}

function broadcast(value, excludedSocket = null) {
  const payload = JSON.stringify(value);
  for (const player of players.values()) {
    if (player.socket !== excludedSocket && player.socket.readyState === WebSocket.OPEN) {
      player.socket.send(payload);
    }
  }
}

function publicPlayer(player) {
  return {
    id: player.id,
    factory_slot: player.factorySlot,
    username: player.username,
    company: player.company,
    color: player.color,
    state: player.state,
  };
}

function availableFactorySlot() {
  const used = new Set(
    [...players.values()]
      .filter((player) => player.joined)
      .map((player) => player.factorySlot),
  );
  for (let slot = 0; slot < maxPlayers; slot += 1) {
    if (!used.has(slot)) {
      return slot;
    }
  }
  return -1;
}

function removePlayer(player) {
  if (!players.delete(player.id)) {
    return;
  }
  if (player.joined) {
    broadcast({ type: "player_left", id: player.id });
  }
}

const server = http.createServer(async (request, response) => {
  const requestUrl = new URL(request.url, `http://${request.headers.host || "localhost"}`);
  if (requestUrl.pathname === "/auth/google" || requestUrl.pathname === "/auth/google/callback") {
    await handleGoogleOAuth(request, response, requestUrl);
    return;
  }
  if (requestUrl.pathname.startsWith("/api/")) {
    await handleApi(request, response, requestUrl);
    return;
  }
  if (requestUrl.pathname === "/health") {
    sendJsonResponse(response, 200, {
      ok: true,
      players: [...players.values()].filter((player) => player.joined).length,
      database: pool ? "postgres" : "local",
    });
    return;
  }

  const requestedPath = requestUrl.pathname === "/" ? "/index.html" : requestUrl.pathname;
  const decodedPath = decodeURIComponent(requestedPath);
  const filePath = path.resolve(webRoot, `.${decodedPath}`);
  if (!filePath.startsWith(`${webRoot}${path.sep}`)) {
    response.writeHead(403);
    response.end("Forbidden");
    return;
  }

  fs.stat(filePath, (statError, stats) => {
    if (statError || !stats.isFile()) {
      response.writeHead(404);
      response.end("Not found");
      return;
    }
    response.writeHead(200, {
      "Content-Type": contentTypes[path.extname(filePath)] || "application/octet-stream",
      "Content-Length": stats.size,
      "Cache-Control": path.extname(filePath) === ".html" ? "no-cache" : "public, max-age=3600",
      "Cross-Origin-Opener-Policy": "same-origin",
      "Cross-Origin-Embedder-Policy": "require-corp",
    });
    fs.createReadStream(filePath).pipe(response);
  });
});

const websocketServer = new WebSocketServer({
  noServer: true,
  maxPayload: 8 * 1024,
});

server.on("upgrade", (request, socket, head) => {
  const requestUrl = new URL(request.url, `http://${request.headers.host || "localhost"}`);
  if (requestUrl.pathname !== "/multiplayer") {
    socket.destroy();
    return;
  }
  if (players.size >= maxPlayers) {
    socket.write("HTTP/1.1 503 Service Unavailable\r\n\r\n");
    socket.destroy();
    return;
  }
  websocketServer.handleUpgrade(request, socket, head, (websocket) => {
    websocketServer.emit("connection", websocket);
  });
});

websocketServer.on("connection", (socket) => {
  const player = {
    id: nextPlayerId++,
    socket,
    joined: false,
    factorySlot: -1,
    username: "",
    company: "",
    color: "1677ff",
    state: null,
    alive: true,
  };
  players.set(player.id, player);
  const authenticationTimeout = setTimeout(() => {
    if (!player.joined) {
      socket.close(4001, "Authentication required");
    }
  }, 15000);

  socket.on("message", async (data, isBinary) => {
    if (isBinary || data.length > 8 * 1024) {
      return;
    }
    let message;
    try {
      message = JSON.parse(data.toString("utf8"));
    } catch {
      return;
    }

    if (message.type === "join" && !player.joined) {
      const session = sessions.get(String(message.token || ""));
      const account = session ? await findAccount(session.usernameKey) : null;
      if (!account) {
        sendSocketJson(socket, { type: "auth_error", error: "Session expired. Sign in again." });
        socket.close(4001, "Authentication required");
        return;
      }
      player.username = account.username;
      player.company = account.company;
      player.color = account.color;
      player.factorySlot = availableFactorySlot();
      if (player.factorySlot < 0) {
        sendSocketJson(socket, { type: "world_full", error: "Every factory plot is occupied." });
        socket.close(4002, "World full");
        return;
      }
      player.joined = true;
      clearTimeout(authenticationTimeout);
      const existingPlayers = [...players.values()]
        .filter((other) => other.joined && other.id !== player.id)
        .map(publicPlayer);
      sendSocketJson(socket, {
        type: "welcome",
        id: player.id,
        factory_slot: player.factorySlot,
        username: player.username,
        players: existingPlayers,
      });
      broadcast({ type: "player_joined", ...publicPlayer(player) }, socket);
      return;
    }

    if (message.type === "state" && player.joined) {
      const state = {
        x: Number(message.x) || 0,
        y: Number(message.y) || 0.1,
        z: Number(message.z) || 0,
        yaw: Number(message.yaw) || 0,
        moving: Boolean(message.moving),
        driving: Boolean(message.driving),
      };
      player.state = state;
      broadcast({ type: "state", id: player.id, ...state }, socket);
    }
  });

  socket.on("pong", () => {
    player.alive = true;
  });
  socket.on("close", () => {
    clearTimeout(authenticationTimeout);
    removePlayer(player);
  });
  socket.on("error", () => socket.terminate());
});

const presenceInterval = setInterval(() => {
  for (const player of players.values()) {
    if (player.socket.readyState !== WebSocket.OPEN || !player.alive) {
      player.socket.terminate();
      removePlayer(player);
      continue;
    }
    player.alive = false;
    player.socket.ping();
  }
}, 15000);
presenceInterval.unref();

const sessionCleanupInterval = setInterval(() => {
  const cutoff = Date.now() - 30 * 24 * 60 * 60 * 1000;
  for (const [token, session] of sessions) {
    if (session.createdAt < cutoff) {
      sessions.delete(token);
    }
  }
  const oauthStateCutoff = Date.now() - 10 * 60 * 1000;
  for (const [state, createdAt] of oauthStates) {
    if (createdAt < oauthStateCutoff) {
      oauthStates.delete(state);
    }
  }
  const oauthCodeCutoff = Date.now() - 2 * 60 * 1000;
  for (const [code, pending] of oauthCodes) {
    if (pending.createdAt < oauthCodeCutoff) {
      oauthCodes.delete(code);
    }
  }
}, 60 * 60 * 1000);
sessionCleanupInterval.unref();

initializeStore()
  .then(() => {
    server.listen(port, "0.0.0.0", () => {
      console.log(`Car Company Empire account and online server listening on port ${port}`);
    });
  })
  .catch((error) => {
    console.error("Could not initialize account storage:", error);
    process.exitCode = 1;
  });
