'use server';

import { getCustomerId } from '@/utils/paddle/get-customer-id';
import { getPaddleInstance } from '@/utils/paddle/get-paddle-instance';
import { isPaddleConnected, PADDLE_NOT_CONNECTED } from '@/utils/paddle/config';
import { SubscriptionResponse } from '@/lib/api.types';
import { getErrorMessage } from '@/utils/paddle/data-helpers';

export async function getSubscriptions(): Promise<SubscriptionResponse> {
  if (!isPaddleConnected()) {
    return { error: PADDLE_NOT_CONNECTED, data: [], hasMore: false, totalRecords: 0 };
  }
  try {
    const customerId = await getCustomerId();
    if (customerId) {
      const subscriptionCollection = getPaddleInstance().subscriptions.list({ customerId: [customerId], perPage: 20 });
      const subscriptions = await subscriptionCollection.next();
      return {
        data: subscriptions,
        hasMore: subscriptionCollection.hasMore,
        totalRecords: subscriptionCollection.estimatedTotal,
      };
    }
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
  } catch (e) {
    return getErrorMessage();
  }
  return getErrorMessage();
}
