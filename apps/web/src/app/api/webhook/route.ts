import { NextRequest } from 'next/server';
import { ProcessWebhook } from '@/utils/paddle/process-webhook';
import { getWebhookVerifier } from '@/utils/paddle/get-paddle-instance';
import { PADDLE_NOT_CONNECTED, paddleWebhookSecret } from '@/utils/paddle/config';

const webhookProcessor = new ProcessWebhook();

export async function POST(request: NextRequest) {
  // Until the owner sets the notification destination's secret (README,
  // "Connecting Paddle") there is nothing to verify a delivery against: say
  // so with a 503, which Paddle retries, rather than a 500.
  const privateKey = paddleWebhookSecret();
  if (!privateKey) {
    return Response.json({ error: PADDLE_NOT_CONNECTED }, { status: 503 });
  }

  const signature = request.headers.get('paddle-signature') || '';
  const rawRequestBody = await request.text();
  if (!signature || !rawRequestBody) {
    return Response.json({ error: 'Missing signature from header' }, { status: 400 });
  }

  // A signature that does not verify (forged, tampered with, or stale) is the
  // sender's fault: 400, not upstream's 500, so it is never retried as ours.
  let eventData;
  try {
    eventData = await getWebhookVerifier().unmarshal(rawRequestBody, privateKey, signature);
  } catch (e) {
    console.log(e);
    return Response.json({ error: 'Invalid signature' }, { status: 400 });
  }

  try {
    const eventName = eventData?.eventType ?? 'Unknown event';
    if (eventData) {
      await webhookProcessor.processEvent(eventData);
    }
    return Response.json({ status: 200, eventName });
  } catch (e) {
    console.log(e);
    return Response.json({ error: 'Internal server error' }, { status: 500 });
  }
}
