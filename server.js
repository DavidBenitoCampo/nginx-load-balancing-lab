// server.js
const express = require('express');
const os = require('os');
const app = express();
const port = process.env.PORT || 3000;
const serverName = process.env.SERVER_NAME || os.hostname();
const startTime = Date.now();

// Request counter for this instance
let requestCount = 0;

app.get('/', (req, res) => {
  requestCount++;
  res.json({
    server: serverName,
    hostname: os.hostname(),
    port: port,
    requests: requestCount,
    timestamp: new Date().toISOString(),
    message: `Hello from ${serverName}!`
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', server: serverName });
});

app.get('/stats', (req, res) => {
  const uptimeSeconds = Math.floor((Date.now() - startTime) / 1000);
  res.json({
    server: serverName,
    hostname: os.hostname(),
    uptime: uptimeSeconds,
    requests: requestCount,
    memory: Math.round(process.memoryUsage().rss / 1024 / 1024),
    timestamp: new Date().toISOString()
  });
});

app.get('/slow', (req, res) => {
  setTimeout(() => {
    res.json({ server: serverName, message: 'Slow response' });
  }, 2000);
});

app.post('/crash', (req, res) => {
  console.log(`${serverName} received crash request — shutting down!`);
  res.json({ server: serverName, message: 'Crashing in 500ms...' });
  setTimeout(() => process.exit(1), 500);
});

app.listen(port, '0.0.0.0', () => {
  console.log(`${serverName} running on port ${port}`);
});
