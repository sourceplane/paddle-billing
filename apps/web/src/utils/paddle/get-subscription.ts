'use server';

import { getCustomerId } from '@/utils/paddle/get-customer-id';
import { ErrorMessage, parseSDKResponse } from '@/utils/paddle/data-helpers';
import { getPaddleInstance } from '@/utils/paddle/get-paddle-instance';
import { isPaddleConnected, PADDLE_NOT_CONNECTED } from '@/utils/paddle/config';
import { SubscriptionDetailResponse } from '@/lib/api.types';

export async function getSubscription(subscriptionId: string): Promise<SubscriptionDetailResponse> {
  if (!isPaddleConnected()) {
    return { error: PADDLE_NOT_CONNECTED };
  }
  try {
    const customerId = await getCustomerId();
    if (customerId) {
      const subscription = await getPaddleInstance().subscriptions.get(subscriptionId, {
        include: ['next_transaction', 'recurring_transaction_details'],
      });

      if (subscription.customerId !== customerId) {
        return { error: ErrorMessage };
      }

      return { data: parseSDKResponse(subscription) };
    }
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
  } catch (e) {
    return { error: ErrorMessage };
  }
  return { error: ErrorMessage };
}
