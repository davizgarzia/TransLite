// Central tier configuration. This is THE file to edit when changing limits:
// tweak values below and run `npx wrangler deploy` (takes seconds).
// The app reads these limits at launch via GET /v1/config, so client-side
// pre-flight checks stay in sync automatically.

export type TierName = "free" | "pro";
export type Provider = "openai" | "anthropic";

export interface TierConfig {
  enabled: boolean;
  /// Requests with more characters are rejected before reaching the LLM.
  maxChars: number;
  /// Translations per device per UTC day. null = unlimited.
  dailyQuota: number | null;
  provider: Provider;
  model: string;
  maxTokens: number;
}

export const TIERS: Record<TierName, TierConfig> = {
  free: {
    enabled: true,
    maxChars: 1000,
    dailyQuota: 25,
    provider: "openai",
    model: "gpt-4o-mini",
    maxTokens: 2048,
  },
  // Subscription tier. Flip `enabled` once LemonSqueezy validation
  // is implemented in license.ts (see TODO there).
  pro: {
    enabled: false,
    maxChars: 10000,
    dailyQuota: 500,
    provider: "openai",
    model: "gpt-4o-mini",
    maxTokens: 8192,
  },
};

// Allowlists mirroring the app's enums (AppViewModel.swift). Requests are
// rejected if they don't match — free-form values must never be interpolated
// into the prompts, since the prompt runs on our API key.
export const TARGET_LANGUAGES = new Set([
  "English", "Spanish", "French", "German", "Italian", "Portuguese",
  "Dutch", "Polish", "Turkish", "Russian", "Arabic", "Hindi",
  "Chinese", "Japanese", "Korean", "Vietnamese", "Thai", "Indonesian",
]);

export const TONES: Record<string, string> = {
  original: "Preserve the original tone",
  formal: "Use a formal, professional tone",
  casual: "Use a casual, relaxed tone",
  concise: "Be direct and brief, remove unnecessary words",
};
