import { TIERS, TARGET_LANGUAGES, TONES } from "./config";
import { ApiError } from "./errors";
import { resolveTier } from "./license";
import {
  TRANSLATE_SYSTEM_PROMPT,
  IMPROVE_SYSTEM_PROMPT,
  translateUserPrompt,
  improveUserPrompt,
} from "./prompts";
import { callProvider, type Env } from "./providers";
import { usedToday, recordUsage } from "./quota";

// Requests bigger than this are dropped before JSON parsing —
// no tier allows anywhere near this much text.
const MAX_BODY_BYTES = 64 * 1024;

const DEVICE_ID_PATTERN = /^[A-Za-z0-9-]{8,64}$/;

interface RequestBody {
  text?: string;
  target_language?: string;
  tone?: string;
  device_id?: string;
  license_key?: string;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    try {
      if (request.method === "GET" && url.pathname === "/v1/config") {
        return handleConfig();
      }
      if (request.method === "POST" && (url.pathname === "/v1/translate" || url.pathname === "/v1/improve")) {
        return await handleCompletion(request, env, url.pathname === "/v1/translate");
      }
      throw new ApiError(404, "not_found", "Not found");
    } catch (error) {
      if (error instanceof ApiError) return error.toResponse();
      console.error("Unhandled error:", error);
      return new ApiError(500, "internal_error", "Internal error").toResponse();
    }
  },
} satisfies ExportedHandler<Env>;

// Exposes each enabled tier's limits so the app can mirror them in its
// pre-flight checks without hardcoding values in two places.
function handleConfig(): Response {
  const tiers: Record<string, { max_chars: number; daily_quota: number | null; target_languages: string[] | null }> = {};
  for (const [name, tier] of Object.entries(TIERS)) {
    if (tier.enabled) {
      tiers[name] = {
        max_chars: tier.maxChars,
        daily_quota: tier.dailyQuota,
        target_languages: tier.allowedTargets,
      };
    }
  }
  return Response.json({ tiers }, { headers: { "Cache-Control": "max-age=3600" } });
}

async function handleCompletion(request: Request, env: Env, isTranslate: boolean): Promise<Response> {
  const body = await parseBody(request);

  const text = typeof body.text === "string" ? body.text : "";
  if (!text.trim()) {
    throw new ApiError(400, "invalid_request", "Missing text");
  }

  const deviceId = body.device_id ?? "";
  if (!DEVICE_ID_PATTERN.test(deviceId)) {
    throw new ApiError(400, "invalid_request", "Missing or invalid device_id");
  }

  const tierName = await resolveTier(env, body.license_key);
  const tier = TIERS[tierName];

  // Cheapest checks first; nothing below this line runs on oversized input.
  if (text.length > tier.maxChars) {
    throw new ApiError(413, "text_too_long", `Text too long (max ${tier.maxChars} characters)`);
  }

  let systemPrompt: string;
  let userPrompt: string;
  if (isTranslate) {
    const targetLanguage = body.target_language ?? "";
    if (!TARGET_LANGUAGES.has(targetLanguage)) {
      throw new ApiError(400, "invalid_request", "Unsupported target_language");
    }
    if (tier.allowedTargets && !tier.allowedTargets.includes(targetLanguage)) {
      throw new ApiError(
        403,
        "language_not_allowed",
        `Your plan only translates to ${tier.allowedTargets.join(", ")}`,
      );
    }
    const toneInstruction = TONES[body.tone ?? "original"];
    if (!toneInstruction) {
      throw new ApiError(400, "invalid_request", "Unsupported tone");
    }
    systemPrompt = TRANSLATE_SYSTEM_PROMPT;
    userPrompt = translateUserPrompt(text, targetLanguage, toneInstruction);
  } else {
    systemPrompt = IMPROVE_SYSTEM_PROMPT;
    userPrompt = improveUserPrompt(text);
  }

  let used = 0;
  if (tier.dailyQuota !== null) {
    used = await usedToday(env.QUOTA, deviceId);
    if (used >= tier.dailyQuota) {
      throw new ApiError(429, "quota_exceeded", "Daily limit reached");
    }
  }

  const result = await callProvider(env, tier, systemPrompt, userPrompt);

  const headers: Record<string, string> = { "X-Tier": tierName };
  if (tier.dailyQuota !== null) {
    await recordUsage(env.QUOTA, deviceId, used);
    headers["X-Quota-Limit"] = String(tier.dailyQuota);
    headers["X-Quota-Remaining"] = String(Math.max(0, tier.dailyQuota - used - 1));
  }

  return Response.json({ text: result }, { headers });
}

async function parseBody(request: Request): Promise<RequestBody> {
  const contentLength = parseInt(request.headers.get("Content-Length") ?? "0", 10);
  if (contentLength > MAX_BODY_BYTES) {
    throw new ApiError(413, "text_too_long", "Request too large");
  }
  const raw = await request.text();
  if (raw.length > MAX_BODY_BYTES) {
    throw new ApiError(413, "text_too_long", "Request too large");
  }
  try {
    return JSON.parse(raw) as RequestBody;
  } catch {
    throw new ApiError(400, "invalid_request", "Invalid JSON body");
  }
}
