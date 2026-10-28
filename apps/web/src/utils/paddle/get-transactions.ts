'use server';

import { getCustomerId } from '@/utils/paddle/get-customer-id';
import { getErrorMessage, parseSDKResponse } from '@/utils/paddle/data-helpers';
import { getPaddleInstance } from '@/utils/paddle/get-paddle-instance';
import { isPaddleConnected, PADDLE_NOT_CONNECTED } from '@/utils/paddle/config';
import { TransactionResponse } from '@/lib/api.types';

export async function getTransactions(subscriptionId: string, after: string): Promise<TransactionResponse> {
  if (!isPaddleConnected()) {
    return { error: PADDLE_NOT_CONNECTED, data: [], hasMore: false, totalRecords: 0 };
  }
  try {
    const customerId = await getCustomerId();
    if (customerId) {
      const transactionCollection = getPaddleInstance().transactions.list({
        customerId: [customerId],
        after: after,
        perPage: 10,
        status: ['billed', 'paid', 'past_due', 'completed', 'canceled'],
        subscriptionId: subscriptionId ? [subscriptionId] : undefined,
      });
      const transactionData = await transactionCollection.next();
      return {
        data: parseSDKResponse(transactionData ?? []),
        hasMore: transactionCollection.hasMore,
        totalRecords: transactionCollection.estimatedTotal,
        error: undefined,
      };
    } else {
      return { data: [], hasMore: false, totalRecords: 0 };
    }
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
  } catch (e) {
    return getErrorMessage();
  }
}
