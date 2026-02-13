#!/bin/bash
set -uo pipefail

URL="${1:-http://localhost}"
REQUESTS="${2:-100}"
PARALLEL="${3:-10}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

printf "=== Nginx Load Balancing Test ===\n"
printf "Target:      %s\n" "$URL"
printf "Requests:    %d\n" "$REQUESTS"
printf "Parallelism: %d\n\n" "$PARALLEL"

# ── Fire requests in batches ───────────────────────────────────────
printf "Sending %d requests (%d parallel)...\n" "$REQUESTS" "$PARALLEL"
for i in $(seq 1 "$REQUESTS"); do
  (
    curl -s -o "$TMPDIR/body_$i.json" \
         -w "%{http_code} %{time_total}\n" \
         "$URL/?r=$i" >> "$TMPDIR/result_$i.txt" 2>/dev/null
  ) &
  # Throttle parallelism
  if (( i % PARALLEL == 0 )); then
    wait
  fi
done
wait

# Merge results
cat "$TMPDIR"/result_*.txt > "$TMPDIR/results.txt" 2>/dev/null

# ── Parse results ──────────────────────────────────────────────────
total=$(wc -l < "$TMPDIR/results.txt")
success=$(grep -c '^200' "$TMPDIR/results.txt" || true)
errors=$((total - success))
avg_time=$(awk '{sum += $2} END {printf "%.4f", sum/NR}' "$TMPDIR/results.txt")
min_time=$(awk 'NR==1 || $2<min {min=$2} END {printf "%.4f", min}' "$TMPDIR/results.txt")
max_time=$(awk 'NR==1 || $2>max {max=$2} END {printf "%.4f", max}' "$TMPDIR/results.txt")

printf "\n── Results ─────────────────────────────────────────\n"
printf "  Total:     %d requests\n" "$total"
printf "  Success:   %d  (HTTP 200)\n" "$success"
printf "  Errors:    %d  (non-200)\n" "$errors"
printf "  Avg time:  %ss\n" "$avg_time"
printf "  Min time:  %ss\n" "$min_time"
printf "  Max time:  %ss\n" "$max_time"

# ── HTTP status breakdown ─────────────────────────────────────────
printf "\n── Status Codes ────────────────────────────────────\n"
awk '{print $1}' "$TMPDIR/results.txt" | sort | uniq -c | sort -rn | while read -r count code; do
  printf "  HTTP %s: %d\n" "$code" "$count"
done

# ── Backend distribution (from successful responses) ──────────────
printf "\n── Backend Distribution ─────────────────────────────\n"
if [ "$success" -gt 0 ]; then
  # Extract server names from all body files
  for f in "$TMPDIR"/body_*.json; do
    jq -r '.server // empty' "$f" 2>/dev/null
  done | grep -v '^$' | sort | uniq -c | sort -rn | while read -r count name; do
    pct=$((count * 100 / success))
    bar=$(printf '%*s' $((pct / 2)) '' | tr ' ' '█')
    printf "  %-20s %4d reqs (%3d%%) %s\n" "$name" "$count" "$pct" "$bar"
  done
else
  printf "  (no successful responses to analyze)\n"
fi

# ── Cache verification ────────────────────────────────────────────
printf "\n── Cache Status ────────────────────────────────────\n"
printf "First request  (expect MISS): "
curl -s -D - "$URL/?cachetest=$(date +%s)" -o /dev/null 2>/dev/null | grep -io "x-cache-status: [a-z]*" || printf "(no cache header)"
printf "\n"
printf "Second request (expect HIT):  "
curl -s -D - "$URL/?cachetest=$(date +%s)" -o /dev/null 2>/dev/null | grep -io "x-cache-status: [a-z]*" || printf "(no cache header)"
printf "\n"

printf "\nDone.\n"
