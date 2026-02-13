# 🔄 Nginx Load Balancing Lab

A hands-on lab to learn and experiment with Nginx load balancing strategies, failover, caching, and HTTPS/TLS — all running in Docker containers.

## Architecture

```
                    ┌─────────────────────────┐
                    │      Client / Browser   │
                    └────────┬───────┬────────┘
                             │       │
                         :80 │       │ :443
                             ▼       ▼
                    ┌─────────────────────────┐
                    │     Nginx Reverse Proxy  │
                    │  ┌───────────────────┐  │
                    │  │  Load Balancer     │  │
                    │  │  Rate Limiter      │  │
                    │  │  Proxy Cache       │  │
                    │  │  TLS Termination   │  │
                    │  └───────────────────┘  │
                    └────┬──────┬──────┬──────┘
                         │      │      │
                    ┌────┴─┐ ┌─┴────┐ ┌┴─────┐
                    │ BE 1 │ │ BE 2 │ │ BE 3 │
                    │:3000 │ │:3000 │ │:3000 │
                    └──────┘ └──────┘ └──────┘
```

## Quick Start

```bash
# 1. Generate TLS certificates
bash certs/generate-certs.sh

# 2. Build and start
docker compose up --build -d

# 3. Verify
docker compose ps           # Should show 3 healthy backends + nginx
curl http://localhost/       # JSON response from a backend
curl -k https://localhost/   # Same, over HTTPS

# 4. Open the dashboard
# http://localhost/dashboard/
```

## Endpoints

| Endpoint | Method | Description |
|---|---|---|
| `/` | GET | Returns JSON with server name, hostname, request count, timestamp |
| `/health` | GET | Health check — `{ status: "healthy" }` |
| `/stats` | GET | Detailed stats — uptime, memory, request count |
| `/slow` | GET | Delayed response (2s) — test timeout handling |
| `/crash` | POST | Kills the backend process — test failover |
| `/dashboard/` | GET | Interactive monitoring dashboard |
| `/nginx-status` | GET | Nginx stub_status metrics |

## Load Balancing Strategies

The lab includes 4 ready-to-use Nginx configs in the `nginx/` directory:

| Config | Strategy | Best For |
|---|---|---|
| `nginx.conf` | `least_conn` | General use (default) |
| `nginx-least-conn.conf` | `least_conn` | Same as default, standalone |
| `nginx-ip-hash.conf` | `ip_hash` | Sticky sessions |
| `nginx-weighted.conf` | `weighted` | Heterogeneous backends |

### Switching strategies

Edit the volume mount in `docker-compose.yaml`:

```yaml
volumes:
  - ./nginx/nginx-ip-hash.conf:/etc/nginx/nginx.conf:ro   # ← change this line
```

Then restart:

```bash
docker compose down && docker compose up -d
```

> **Note:** The weighted config (`nginx-weighted.conf`) requires individually named backends
> instead of `deploy.replicas`. See the comments in that file.

## Testing

### Load test script

```bash
# Default: 100 requests, 10 parallel
bash test-load.sh

# Custom: 200 requests, 20 parallel, to HTTPS
bash test-load.sh https://localhost 200 20
```

The script outputs:
- Response time stats (avg/min/max)
- HTTP status code breakdown
- Backend distribution with visual bars
- Cache verification (MISS → HIT)

### Manual testing

```bash
# Test load balancing — observe different hostnames
for i in $(seq 1 6); do curl -s "http://localhost/?r=$i" | jq -c '{server,hostname}'; done

# Test caching
curl -v http://localhost/ 2>&1 | grep X-Cache-Status   # MISS
curl -v http://localhost/ 2>&1 | grep X-Cache-Status   # HIT

# Test HTTPS
curl -k -v https://localhost/ 2>&1 | grep subject
```

## Failover Demo

Step-by-step guide to test Nginx failover with `max_fails` / `fail_timeout`:

```bash
# 1. Start the lab
docker compose up --build -d

# 2. Confirm 3 healthy backends
docker compose ps

# 3. Crash a backend
curl -X POST http://localhost/crash

# 4. Watch Docker restart it (check every 2 seconds)
watch -n 2 docker compose ps

# 5. Alternatively, use the dashboard
#    http://localhost/dashboard/ — click "Crash This Backend"
```

What to observe:
- Nginx detects the failure via `max_fails=3` and stops routing to the dead backend
- Docker's `restart: unless-stopped` restarts the container
- After `fail_timeout=30s`, Nginx re-adds the recovered backend
- During failure, remaining backends handle all traffic seamlessly

## HTTPS / TLS

The lab includes self-signed certificates for localhost.

```bash
# Generate certificates (one-time)
bash certs/generate-certs.sh

# Test HTTPS
curl -k https://localhost/

# Optionally trust the CA system-wide (Linux)
sudo cp certs/ca.crt /usr/local/share/ca-certificates/lab-ca.crt
sudo update-ca-certificates
```

Generated files:
- `certs/ca.crt` / `certs/ca.key` — Certificate Authority
- `certs/server.crt` / `certs/server.key` — Server certificate (SAN: localhost, 127.0.0.1)

## Dashboard

Access the interactive dashboard at **http://localhost/dashboard/**

Features:
- **Live backend status** — healthy/dead indicators, uptime, request count, memory usage
- **Crash buttons** — simulate backend failures from the UI
- **Request distribution chart** — visualize load balancing in real-time
- **Nginx metrics** — active connections, accepts, handled requests
- **Auto-refresh** every 2 seconds

## Project Structure

```
nginx-load-balancing-lab/
├── server.js                    # Node.js backend server
├── Dockerfile                   # Backend Docker image
├── docker-compose.yaml          # Orchestration (3 replicas + nginx)
├── package.json
├── test-load.sh                 # Load testing script
├── .dockerignore
├── nginx/
│   ├── nginx.conf               # Default config (least_conn + HTTPS)
│   ├── nginx-least-conn.conf    # Standalone least_conn
│   ├── nginx-ip-hash.conf       # Sticky sessions
│   └── nginx-weighted.conf      # Weighted distribution
├── dashboard/
│   └── index.html               # Interactive monitoring UI
├── certs/
│   ├── generate-certs.sh        # TLS cert generator
│   └── .gitignore               # Ignores generated cert files
└── README.md
```

## Cleanup

```bash
docker compose down             # Stop and remove containers
docker compose down --volumes   # Also remove volumes
docker compose down --rmi all   # Also remove built images
```
