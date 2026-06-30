"use strict";

const assert = require("node:assert/strict");
const WebSocket = require("ws");

const url = process.env.ONLINE_TEST_URL || "ws://127.0.0.1:8080/multiplayer";
const apiUrl = process.env.ACCOUNT_TEST_URL || "http://127.0.0.1:8080/api";

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

async function createAccount(label) {
  const suffix = `${Date.now()}${Math.floor(Math.random() * 1000)}`;
  const username = `${label}${suffix}`.slice(0, 18);
  const response = await fetch(`${apiUrl}/signup`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      username,
      password: "test-password",
      company: `${label} MOTORS`,
      color: "1677ff",
    }),
  });
  assert.equal(response.status, 201);
  return response.json();
}

async function join(socket, token) {
  const welcome = nextMessage(socket, (message) => message.type === "welcome");
  socket.send(JSON.stringify({
    type: "join",
    token,
  }));
  return welcome;
}

async function run() {
  const firstAccount = await createAccount("First");
  const secondAccount = await createAccount("Second");
  const first = await openSocket();
  const second = await openSocket();
  const firstWelcome = await join(first, firstAccount.token);
  const joined = nextMessage(first, (message) => message.type === "player_joined");
  const secondWelcome = await join(second, secondAccount.token);
  const secondJoined = await joined;

  assert.equal(firstWelcome.username, firstAccount.account.username);
  assert.equal(secondWelcome.username, secondAccount.account.username);
  assert.equal(secondJoined.username, secondAccount.account.username);
  assert.equal(secondWelcome.players[0].username, firstAccount.account.username);
  assert.notEqual(firstWelcome.factory_slot, secondWelcome.factory_slot);
  assert.equal(secondJoined.factory_slot, secondWelcome.factory_slot);

  const saveResponse = await fetch(`${apiUrl}/progress`, {
    method: "PUT",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${firstAccount.token}`,
    },
    body: JSON.stringify({
      progress: {
        ...firstAccount.account.progress,
        money: 54321,
        cars: [{ name: "TEST GT", quality: 4, color: "ff6333" }],
      },
    }),
  });
  assert.equal(saveResponse.status, 200);
  const sessionResponse = await fetch(`${apiUrl}/session`, {
    headers: { Authorization: `Bearer ${firstAccount.token}` },
  });
  const session = await sessionResponse.json();
  assert.equal(session.account.progress.money, 54321);
  assert.equal(session.account.progress.cars[0].name, "TEST GT");

  const left = nextMessage(first, (message) => (
    message.type === "player_left" && message.id === secondWelcome.id
  ));
  second.close();
  await left;
  first.close();
  console.log("SERVER_ACCOUNT_PRESENCE_PASS");
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
