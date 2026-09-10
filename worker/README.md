# TransLite API Worker

Cloudflare Worker that proxies free-tier (and soon pro-tier) translations to
the LLM providers using **our** API keys, enforcing per-tier limits server-side.
BYOK users never touch this worker — their app talks to OpenAI/Anthropic
directly, as always.

## Changing limits

Edit `src/config.ts` (character caps, daily quotas, model, max_tokens per tier)
and redeploy:

```sh
npx wrangler deploy
```

That's it — takes seconds. The app fetches `GET /v1/config` at launch, so its
pre-flight checks and error messages pick up the new limits automatically.

## First-time setup

```sh
cd worker
npm install
npx wrangler login

# 1. Create the KV namespace for daily quota counters,
#    then paste the printed id into wrangler.toml:
npx wrangler kv namespace create QUOTA

# 2. Set the provider key(s). Free tier uses OpenAI (gpt-4o-mini) by default:
npx wrangler secret put OPENAI_API_KEY
# Only needed if a tier in config.ts uses provider "anthropic":
# npx wrangler secret put ANTHROPIC_API_KEY

# 3. Deploy:
npx wrangler deploy
```

Local development (no deploy needed): put keys in `worker/.dev.vars`
(gitignored) as `OPENAI_API_KEY=sk-...` and run `npx wrangler dev`.

## API

All endpoints return JSON. Errors look like
`{ "error": { "code": "text_too_long", "message": "..." } }`.

### `GET /v1/config`

Limits of every enabled tier, for client-side pre-flight checks:

```json
{ "tiers": { "free": { "max_chars": 1000, "daily_quota": 20, "target_languages": ["English"] } } }
```

### `POST /v1/translate`

```json
{
  "text": "hola mundo",
  "target_language": "English",
  "tone": "original",
  "device_id": "<app instance id>",
  "license_key": "<optional, pro tier>"
}
```

Returns `{ "text": "hello world" }` plus `X-Quota-Limit` / `X-Quota-Remaining`
headers. `tone` is one of `original | formal | casual | concise`;
`target_language` must match the app's language list. Both are allowlisted
server-side — free-form values are rejected, never interpolated into prompts.

### `POST /v1/improve`

Same shape without `target_language`/`tone`. Returns `{ "text": "..." }`.

### Error codes the app should handle

| HTTP | code                | meaning                                    |
|------|---------------------|--------------------------------------------|
| 413  | `text_too_long`     | Over the tier's character cap              |
| 429  | `quota_exceeded`    | Daily quota used up (upsell moment)        |
| 403  | `language_not_allowed` | Target language not in the tier (free = English only) |
| 429  | `upstream_busy`     | Provider rate-limited us; retry shortly    |
| 502  | `upstream_error`    | Provider failure; retry                    |
| 400  | `invalid_request`   | Malformed body / unknown language or tone  |

## Notes

- Daily quotas are per `device_id` per UTC day, stored in KV with automatic
  expiry (no database, nothing to clean up). Failed translations don't
  consume quota.
- Someone can reset their `device_id` to dodge the free quota; the character
  cap keeps the worst case at roughly $0.01–0.07/day per identity, which is
  the accepted trade-off. For extra protection, add a Cloudflare WAF
  rate-limiting rule by IP on `/v1/*` from the dashboard (free plan includes
  one rule).
- Cost: Cloudflare free plan covers ~1,000 KV writes/day (≈ that many free
  translations/day). Past that, Workers Paid is $5/month flat.
- Subscription (week 2): implement LemonSqueezy validation in
  `src/license.ts` (TODO comment there explains it) and flip
  `TIERS.pro.enabled` in `src/config.ts`.
