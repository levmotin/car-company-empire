"use strict";

const assert = require("node:assert/strict");
const WebSocket = require("ws");

const url = process.env.ONLINE_TEST_URL || "ws://127.0.0.1:8080/multiplayer";

function openSocket() {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(url);
    socket.once("open", () => resolve(socket));
    socket.once("error", reject);
  });
}

function nextMessage(socket, predicate, timeoutMs = 5000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      socket.off("message", handler);
      reject(new Error("Timed out waiting for presence message."));
    }, timeoutMs);
    function handler(data) {
      const message = JSON.parse(data.toString("utf8"));
      if (predicate(message)) {
        clearTimeout(timer);
        socket.off("message", handler);
        resolve(message);
      }
    }
    socket.on("message", handler);
  });
}

async function join(socket, username, company) {
  const welcome = nextMessage(socket, (message) => message.type === "welcome");
  socket.send(JSON.stringify({
    type: "join",
    username,
    company,
    color: "1677ff",
  }));
  return welcome;
}

async function run() {
  const first = await openSocket();
  const second = await openSocket();
  const firstWelcome = await join(first, "PresenceDriver", "FIRST MOTORS");
  const joined = nextMessage(first, (message) => message.type === "player_joined");
  const secondWelcome = await join(second, "PresenceDriver", "SECOND MOTORS");
  const secondJoined = await joined;

  assert.equal(firstWelcome.username, "PresenceDriver");
  assert.equal(secondWelcome.username, "PresenceDriver_2");
  assert.equal(secondJoined.username, "PresenceDriver_2");
  assert.equal(secondWelcome.players[0].username, "PresenceDriver");

  const left = nextMessage(first, (message) => (
    message.type === "player_left" && message.id === secondWelcome.id
  ));
  second.close();
  await left;
  first.close();
  console.log("SERVER_PRESENCE_PASS");
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
