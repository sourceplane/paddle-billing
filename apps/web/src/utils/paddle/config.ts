// Paddle is the one third party this app sells through, and nothing
// provisions it: a deployment has no Paddle keys until its owner adds them
// (README, "Connecting Paddle"). Until then no Paddle client is built — the
// pricing page shows the plans with a notice instead of prices, checkout says
// Paddle is not connected, the dashboard's subscription and payment views say
// the same, and the webhook answers 503 — while sign-up, sign-in and the
// dashboard work exactly as they do with Paddle connected. Upstream read the
// keys at module load and built a client with an undefined key; here they are
// read per call, because on Workers the environment is the request's.
//
// Names are upstream's. The two server-side ones are Worker secrets (the
// deploy pushes them from the product's Orun secrets); the two NEXT_PUBLIC_
// ones are public by design and `next build` inlines them into the browser
// bundle, so connecting Paddle is a redeploy.

export const PADDLE_NOT_CONNECTED = 'Paddle is not connected.';

export type PaddleEnvironmentName = 'sandbox' | 'production';

// An empty value — a blank line in .dev.vars — is no key.
export function paddleApiKey(): string | undefined {
  return process.env.PADDLE_API_KEY?.trim() || undefined;
}

export function paddleWebhookSecret(): string | undefined {
  return process.env.PADDLE_NOTIFICATION_WEBHOOK_SECRET?.trim() || undefined;
}

// Sandbox unless production is asked for by name (upstream's README:
// "sandbox recommended"); upstream required the variable to be set.
export function paddleEnvironment(): PaddleEnvironmentName {
  return process.env.NEXT_PUBLIC_PADDLE_ENV?.trim() === 'production' ? 'production' : 'sandbox';
}

export function isPaddleConnected(): boolean {
  return Boolean(paddleApiKey());
}

// What Paddle.js needs in the browser: the client-side token and the
// environment. The references are literal so `next build` inlines them.
export function paddleClientConfig(): { token: string; environment: PaddleEnvironmentName } | undefined {
  const token = process.env.NEXT_PUBLIC_PADDLE_CLIENT_TOKEN?.trim();
  if (!token) return undefined;
  return {
    token,
    environment: process.env.NEXT_PUBLIC_PADDLE_ENV?.trim() === 'production' ? 'production' : 'sandbox',
  };
}
