import { Toggle } from '@/components/shared/toggle/toggle';
import { PriceCards } from '@/components/home/pricing/price-cards';
import { useEffect, useState } from 'react';
import { BillingFrequency, IBillingFrequency } from '@/constants/billing-frequency';
import { initializePaddle, Paddle } from '@paddle/paddle-js';
import { usePaddlePrices } from '@/hooks/usePaddlePrices';
import { paddleClientConfig } from '@/utils/paddle/config';
import { PaddleNotConnected } from '@/components/shared/paddle-not-connected/paddle-not-connected';

interface Props {
  country: string;
}

export function Pricing({ country }: Props) {
  const [frequency, setFrequency] = useState<IBillingFrequency>(BillingFrequency[0]);
  const [paddle, setPaddle] = useState<Paddle | undefined>(undefined);

  const { prices, loading } = usePaddlePrices(paddle, country);
  // Until the owner connects Paddle there is no client-side token, so no
  // prices to fetch: the plans show without them, and a notice says why.
  const paddleConfig = paddleClientConfig();

  useEffect(() => {
    const config = paddleClientConfig();
    if (config) {
      initializePaddle({
        token: config.token,
        environment: config.environment,
      }).then((paddle) => {
        if (paddle) {
          setPaddle(paddle);
        }
      });
    }
  }, []);

  return (
    <div className="mx-auto max-w-7xl relative px-[32px] flex flex-col items-center justify-between">
      <Toggle frequency={frequency} setFrequency={setFrequency} />
      {!paddleConfig && <PaddleNotConnected what={'show prices and take payments'} className={'mb-8'} />}
      <PriceCards frequency={frequency} loading={paddleConfig ? loading : false} priceMap={prices} />
    </div>
  );
}
