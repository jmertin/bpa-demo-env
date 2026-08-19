# traffic-generator

Synthetic user traffic for the BPA-Demo web shop. Runs continuously. Every
cycle gives each demo user exactly one authenticated session (shuffled
once per pass) so the `trouble`, `empty_basket`, and `locked` use cases
(see the root `CLAUDE.md`'s "Demo use cases" section) all get exercised
regularly, not just by chance, and tops that up with anonymous guest
sessions (80% of the cycle's total by default) so the overall traffic mix
looks like a real shop rather than only ever logged-in activity. A small
pool of sessions run concurrently rather than one at a time, so requests
genuinely overlap the way real traffic does — useful for keeping the DX O2
agents reporting live, *varied* data without a human clicking through the
app.

## What it does

Each cycle builds a shuffled mix of sessions: one authenticated session
per demo user, plus enough anonymous guest sessions to reach
`TRAFFIC_ANONYMOUS_RATIO` of the total. `TRAFFIC_CONCURRENT_SESSIONS`
worker threads pull from that mix and run them in parallel.

Every session (guest or authenticated) performs a random number of random
shop actions (browse the listing with occasional filters, view a product,
add to basket, view the basket, or complete a checkout — guest checkout
works too, the app accepts orders with no user id), then an authenticated
session logs out. The `admin` account also occasionally visits the admin
diagnostic pages (`?page=admin`, `?page=info`, `?page=db`, `?page=dxo2`).

Pacing between actions has a small chance (`TRAFFIC_SLOWDOWN_PROBABILITY`)
of an extra randomized delay on top, simulating an occasional slow client
or network burst, so pacing has a realistic long tail instead of a narrow
uniform range.

Login failures (the `locked` use case blocks it) and empty-basket
checkout attempts are expected, tolerated outcomes, not errors — the
generator logs them and moves on to the next session.

`generator.py` uses only the Python standard library (`urllib`,
`http.cookiejar`, `threading`, `queue`) — no `pip install`, no dependency
layer.

## Configuration

All via environment variables (see `generator.py`'s top for the exact
defaults):

| Variable | Default | Meaning |
|---|---|---|
| `TARGET_URL` | `http://apachephp:8080` | Base URL of the app (the Compose service name; override for other deployments) |
| `MIN_ACTION_DELAY_SECS` / `MAX_ACTION_DELAY_SECS` | `1` / `4` | Pause between actions within one session |
| `MIN_SESSION_DELAY_SECS` / `MAX_SESSION_DELAY_SECS` | `2` / `8` | Pause between one session ending and a worker picking up the next |
| `MIN_ACTIONS_PER_SESSION` / `MAX_ACTIONS_PER_SESSION` | `3` / `9` | Random action count per session |
| `TRAFFIC_ANONYMOUS_RATIO` | `0.8` | Fraction of each cycle's sessions that browse anonymously (no login). The remaining share is always exactly one authenticated session per demo user |
| `TRAFFIC_CONCURRENT_SESSIONS` | `3` | How many sessions run in parallel |
| `TRAFFIC_SLOWDOWN_PROBABILITY` | `0.12` | Chance a given action's pacing gets an extra "slow client" delay on top |
| `TRAFFIC_SLOWDOWN_MIN_SECS` / `TRAFFIC_SLOWDOWN_MAX_SECS` | `3` / `12` | Range for that extra delay when it happens |
| `REQUEST_TIMEOUT_SECS` | `15` | Per-request timeout (the `trouble` use case can take several hundred ms) |
| `STARTUP_WAIT_TIMEOUT_SECS` | `120` | How long to wait for `/health` to respond before giving up at startup |
| `LOG_LEVEL` | `INFO` | Set to `DEBUG` to log every request (and every simulated slowdown) |

## Running standalone (outside Compose)

```bash
docker build -t traffic-generator traffic-generator/
docker run --rm -e TARGET_URL=http://localhost:8080 traffic-generator
```
