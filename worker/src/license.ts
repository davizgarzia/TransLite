import type { TierName } from "./config";
import type { Env } from "./providers";

// LemonSqueezy product that grants the pro tier (the Pro subscription).
// Keys from any other product (e.g. the BYOK lifetime license) resolve to
// free — BYOK users talk to the providers directly and never need the proxy.
const PRO_PRODUCT_IDS = new Set([
  1352278, // TransLite Pro (live)
  1352332, // TransLite Pro test-mode duplicate — REMOVE before launch
]);

// Positive verdicts are cached for a day; rejections only briefly, so a
// just-purchased key doesn't stay stuck on free.
const PRO_CACHE_TTL_SECONDS = 24 * 60 * 60;
const REJECTED_CACHE_TTL_SECONDS = 5 * 60;

interface CachedVerdict {
  tier: TierName;
}

/// Resolves which tier a request belongs to. Verdicts are cached in KV for
/// 24h so LemonSqueezy is hit at most once a day per key — meaning a
/// cancelled subscription can keep pro access for up to a day, which is an
/// accepted trade-off.
export async function resolveTier(env: Env, licenseKey: string | undefined): Promise<TierName> {
  if (!licenseKey) return "free";

  // License keys are UUIDs; reject junk before caching or calling out.
  if (!/^[A-Za-z0-9-]{8,64}$/.test(licenseKey)) return "free";

  const cacheKey = `license:${licenseKey}`;
  const cached = await env.QUOTA.get<CachedVerdict>(cacheKey, "json");
  if (cached) return cached.tier;

  const tier = await validateWithLemonSqueezy(licenseKey);
  await env.QUOTA.put(cacheKey, JSON.stringify({ tier } satisfies CachedVerdict), {
    expirationTtl: tier === "pro" ? PRO_CACHE_TTL_SECONDS : REJECTED_CACHE_TTL_SECONDS,
  });
  return tier;
}

async function validateWithLemonSqueezy(licenseKey: string): Promise<TierName> {
  try {
    const res = await fetch("https://api.lemonsqueezy.com/v1/licenses/validate", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: JSON.stringify({ license_key: licenseKey }),
    });

    if (!res.ok) return "free";

    const data = await res.json<{
      valid?: boolean;
      meta?: { product_id?: number };
    }>();

    if (data.valid === true && PRO_PRODUCT_IDS.has(data.meta?.product_id ?? -1)) {
      return "pro";
    }
    return "free";
  } catch {
    // LemonSqueezy being unreachable must not break translations;
    // fail towards the free tier.
    return "free";
  }
}
