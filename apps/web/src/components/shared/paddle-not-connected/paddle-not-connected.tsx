import { cn } from '@/lib/utils';
import { PADDLE_NOT_CONNECTED } from '@/utils/paddle/config';

interface Props {
  // What needs Paddle where this notice stands ("show prices", "take payments", …).
  what: string;
  className?: string;
}

// Not upstream's. What every Paddle surface shows until the owner connects
// Paddle (README, "Connecting Paddle"): never a 500, never a spinner that
// does not stop.
export function PaddleNotConnected({ what, className }: Props) {
  return (
    <div data-paddle="not-connected" className={cn('text-center text-muted-foreground', className)}>
      <p className={'text-base font-medium text-white'}>{PADDLE_NOT_CONNECTED}</p>
      <p className={'text-sm'}>{`Connect Paddle to ${what}.`}</p>
    </div>
  );
}
