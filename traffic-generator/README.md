# traffic-generator

Synthetic user traffic for the BPA-Demo web shop. Runs continuously,
cycling through the full demo user roster (shuffled once per pass) so the
`trouble`, `empty_basket`, and `locked` use cases (see the root
`CLAUDE.md`'s "Demo use cases" section) all get exercised regularly, not
just by chance — useful for keeping the DX O2 agents reporting live data
without a human clicking through the app.

## What it does

For each user in turn: logs in, performs a random number of random shop
actions (browse the listing with occasional filters, view a product,
add to basket, view the basket, or complete a checkout), then logs out.
The `admin` account also occasionally visits the admin diagnostic pages
(`/admin`, `/info`, `/db`, `/dxo2`).

Login failures (the `locked` use case blocks it) and empty-basket
checkout attempts are expected, tolerated outcomes, not errors — the
generator logs them and moves on to the next user.

`generator.py` uses only the Python standard library (`urllib`,
`http.cookiejar`) — no `pip install`, no dependency layer.

## Configuration

All via environment variables (see `generator.py`'s top for the exact
defaults):

| Variable | Default | Meaning |
|---|---|---|
| `TARGET_URL` | `http://apachephp:8080` | Base URL of the app (the Compose service name; override for other deployments) |
| `MIN_ACTION_DELAY_SECS` / `MAX_ACTION_DELAY_SECS` | `1` / `4` | Pause between actions within one session |
| `MIN_SESSION_DELAY_SECS` / `MAX_SESSION_DELAY_SECS` | `2` / `8` | Pause between one user's session and the next |
| `MIN_ACTIONS_PER_SESSION` / `MAX_ACTIONS_PER_SESSION` | `3` / `9` | Random action count per login session |
| `REQUEST_TIMEOUT_SECS` | `15` | Per-request timeout (the `trouble` use case can take several hundred ms) |
| `STARTUP_WAIT_TIMEOUT_SECS` | `120` | How long to wait for `/health` to respond before giving up at startup |
| `LOG_LEVEL` | `INFO` | Set to `DEBUG` to log every request |

## Running standalone (outside Compose)

```bash
docker build -t traffic-generator traffic-generator/
docker run --rm -e TARGET_URL=http://localhost:8080 traffic-generator
```
