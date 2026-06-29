"use strict";

const http = require("node:http");
const path = require("node:path");
const fs = require("node:fs");
const { WebSocketServer, WebSocket } = require("ws");

const port = Number(process.env.PORT || 8080);
const webRoot = path.join(__dirname, "web");
const maxPlayers = 64;
const players = new Map();
let nextPlayerId = 1;

const contentTypes = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".wasm": "application/wasm",
  ".pck": "application/octet-stream",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".json": "application/json; charset=utf-8",
};

function sendJson(socket, value) {
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
    company: player.company,
    color: player.color,
    state: player.state,
  };
}

const server = http.createServer((request, response) => {
  const requestUrl = new URL(request.url, `http://${request.headers.host || "localhost"}`);
  if (requestUrl.pathname === "/health") {
    response.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
    response.end(JSON.stringify({ ok: true, players: players.size }));
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
    company: "ONLINE MOTORS",
    color: "1677ff",
    state: null,
  };
  players.set(player.id, player);

  socket.on("message", (data, isBinary) => {
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
      player.company = String(message.company || "ONLINE MOTORS").trim().slice(0, 32) || "ONLINE MOTORS";
      player.color = /^[0-9a-fA-F]{6,8}$/.test(String(message.color || ""))
        ? String(message.color)
        : "1677ff";
      player.joined = true;
      const existingPlayers = [...players.values()]
        .filter((other) => other.joined && other.id !== player.id)
        .map(publicPlayer);
      sendJson(socket, { type: "welcome", id: player.id, players: existingPlayers });
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

  socket.on("close", () => {
    players.delete(player.id);
    if (player.joined) {
      broadcast({ type: "player_left", id: player.id });
    }
  });

  socket.on("error", () => {
    socket.close();
  });
});

server.listen(port, "0.0.0.0", () => {
  console.log(`Car Company Empire online server listening on port ${port}`);
});
