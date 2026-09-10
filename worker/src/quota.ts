// Daily per-device quota backed by Workers KV. Keys expire on their own,
// so there is nothing to clean up. KV is eventually consistent: a burst of
// parallel requests can slightly overshoot the quota, which is acceptable —
// the per-request character cap keeps the worst case bounded.

const TWO_DAYS_SECONDS = 2 * 24 * 60 * 60;

function quotaKey(deviceId: string): string {
  const day = new Date().toISOString().slice(0, 10); // UTC YYYY-MM-DD
  return `quota:${deviceId}:${day}`;
}

export async function usedToday(kv: KVNamespace, deviceId: string): Promise<number> {
  const raw = await kv.get(quotaKey(deviceId));
  return raw ? parseInt(raw, 10) || 0 : 0;
}

/// Called only after a successful LLM response, so failed requests
/// don't consume the user's quota.
export async function recordUsage(kv: KVNamespace, deviceId: string, used: number): Promise<void> {
  await kv.put(quotaKey(deviceId), String(used + 1), { expirationTtl: TWO_DAYS_SECONDS });
}
