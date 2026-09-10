import type { TierConfig } from "./config";
import { ApiError } from "./errors";

export interface Env {
  QUOTA: KVNamespace;
  OPENAI_API_KEY?: string;
  ANTHROPIC_API_KEY?: string;
}

/// Calls the tier's configured LLM and returns the raw completion text.
export async function callProvider(
  env: Env,
  tier: TierConfig,
  systemPrompt: string,
  userPrompt: string,
): Promise<string> {
  const response = tier.provider === "openai"
    ? await callOpenAI(env, tier, systemPrompt, userPrompt)
    : await callAnthropic(env, tier, systemPrompt, userPrompt);
  return response.trim();
}

async function callOpenAI(env: Env, tier: TierConfig, systemPrompt: string, userPrompt: string): Promise<string> {
  if (!env.OPENAI_API_KEY) {
    throw new ApiError(500, "server_misconfigured", "OPENAI_API_KEY secret is not set");
  }

  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${env.OPENAI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: tier.model,
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt },
      ],
      temperature: 0.1,
      max_tokens: tier.maxTokens,
    }),
  });

  if (!res.ok) throw upstreamError(res.status);

  const data = await res.json<{ choices?: { message?: { content?: string } }[] }>();
  const content = data.choices?.[0]?.message?.content;
  if (!content) throw new ApiError(502, "upstream_error", "Empty response from translation service");
  return content;
}

async function callAnthropic(env: Env, tier: TierConfig, systemPrompt: string, userPrompt: string): Promise<string> {
  if (!env.ANTHROPIC_API_KEY) {
    throw new ApiError(500, "server_misconfigured", "ANTHROPIC_API_KEY secret is not set");
  }

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": env.ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: tier.model,
      max_tokens: tier.maxTokens,
      system: systemPrompt,
      messages: [{ role: "user", content: userPrompt }],
    }),
  });

  if (!res.ok) throw upstreamError(res.status);

  const data = await res.json<{ content?: { type: string; text?: string }[] }>();
  const content = data.content?.find((block) => block.type === "text")?.text;
  if (!content) throw new ApiError(502, "upstream_error", "Empty response from translation service");
  return content;
}

// Upstream details (including auth failures on OUR key) are never forwarded
// to the client — only a generic retryable/non-retryable signal.
function upstreamError(status: number): ApiError {
  if (status === 429 || status === 529) {
    return new ApiError(429, "upstream_busy", "Translation service is busy - please try again shortly");
  }
  return new ApiError(502, "upstream_error", "Translation service error - please try again");
}
