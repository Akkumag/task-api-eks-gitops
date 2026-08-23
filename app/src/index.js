const express = require("express");
const client = require("prom-client");

const app = express();
app.use(express.json());

const PORT = process.env.PORT || 3000;

// --- Prometheus metrics ---
const register = new client.Registry();
client.collectDefaultMetrics({ register });

const httpRequestDuration = new client.Histogram({
  name: "http_request_duration_seconds",
  help: "Duration of HTTP requests in seconds",
  labelNames: ["method", "route", "status_code"],
});
register.registerMetric(httpRequestDuration);

const tasksCreatedTotal = new client.Counter({
  name: "tasks_created_total",
  help: "Total number of tasks created",
});
register.registerMetric(tasksCreatedTotal);

app.use((req, res, next) => {
  const end = httpRequestDuration.startTimer();
  res.on("finish", () => {
    end({ method: req.method, route: req.path, status_code: res.statusCode });
  });
  next();
});

// --- In-memory store (portfolio demo — not persistent, that's a documented tradeoff) ---
let tasks = [];
let nextId = 1;

app.get("/healthz", (req, res) => res.json({ status: "ok" }));
app.get("/readyz", (req, res) => res.json({ status: "ready" }));

app.get("/metrics", async (req, res) => {
  res.set("Content-Type", register.contentType);
  res.end(await register.metrics());
});

app.get("/tasks", (req, res) => res.json(tasks));

app.post("/tasks", (req, res) => {
  const { title } = req.body || {};
  if (!title || typeof title !== "string") {
    return res.status(400).json({ error: "title is required" });
  }
  const task = { id: nextId++, title, done: false, createdAt: new Date().toISOString() };
  tasks.push(task);
  tasksCreatedTotal.inc();
  res.status(201).json(task);
});

app.patch("/tasks/:id", (req, res) => {
  const task = tasks.find((t) => t.id === Number(req.params.id));
  if (!task) return res.status(404).json({ error: "not found" });
  if (typeof req.body.done === "boolean") task.done = req.body.done;
  res.json(task);
});

app.delete("/tasks/:id", (req, res) => {
  const before = tasks.length;
  tasks = tasks.filter((t) => t.id !== Number(req.params.id));
  if (tasks.length === before) return res.status(404).json({ error: "not found" });
  res.status(204).end();
});

app.listen(PORT, () => {
  console.log(`task-api listening on port ${PORT}`);
});
