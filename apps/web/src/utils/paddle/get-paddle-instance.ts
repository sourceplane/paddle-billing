import { Environment, LogLevel, Paddle, PaddleOptions } from '@paddle/paddle-node-sdk';
import { PADDLE_NOT_CONNECTED, paddleApiKey, paddleEnvironment } from '@/utils/paddle/config';

function paddleOptions(): PaddleOptions {
  return {
    environment: paddleEnvironment() === 'production' ? Environment.production : Environment.sandbox,
    logLevel: LogLevel.error,
  };
}

// A client for Paddle's API, built per call from the request's environment.
// Without PADDLE_API_KEY there is no client: callers check
// isPaddleConnected() first, and this throws rather than build one with an
// undefined key (upstream logged and carried on).
export function getPaddleInstance() {
  const apiKey = paddleApiKey();
  if (!apiKey) {
    throw new Error(`${PADDLE_NOT_CONNECTED} PADDLE_API_KEY is not set.`);
  }
  return new Paddle(apiKey, paddleOptions());
}

// The SDK's webhook verifier (`webhooks.unmarshal`: HMAC-SHA256 over
// `ts:body`, the signature's timestamp no older than five seconds) needs no
// API key — it never calls Paddle — so the webhook works once its secret is
// set, with or without the API key.
export function getWebhookVerifier() {
  return new Paddle(paddleApiKey() ?? '', paddleOptions()).webhooks;
}
