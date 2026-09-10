import type { TierName } from "./config";
import type { Env } from "./providers";

/// Resolves which tier a request belongs to.
///
/// TODO(subscription): validate `licenseKey` against LemonSqueezy
/// (POST https://api.lemonsqueezy.com/v1/licenses/validate), cache the
/// verdict in KV under `license:${key}` with a 24h TTL so LemonSqueezy is
/// hit at most once a day per device, and return "pro" on success.
/// Then flip TIERS.pro.enabled in config.ts.
export async function resolveTier(_env: Env, _licenseKey: string | undefined): Promise<TierName> {
  return "free";
}
