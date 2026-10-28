// eslint-config-next 16 ships flat configs; this is what `create-next-app`
// generates for Next 16 (the template, on Next 15, read the same two configs
// through FlatCompat and ran `next lint`, which Next 16 removed). The
// template's code is kept as written, so a rule that eslint-config-next 16
// brings and that the template was never written against is off, by name.
import { defineConfig, globalIgnores } from 'eslint/config';
import nextVitals from 'eslint-config-next/core-web-vitals';
import nextTs from 'eslint-config-next/typescript';

const eslintConfig = defineConfig([
  ...nextVitals,
  ...nextTs,
  {
    // The React Compiler's rules, new in eslint-config-next 16: the template's
    // hooks predate them. `setLoading(true)` at the top of usePaddlePrices'
    // effect, and checkout-contents' `useCallback(throttle(...))`.
    rules: {
      'react-hooks/set-state-in-effect': 'off',
      'react-hooks/use-memo': 'off',
    },
  },
  {
    // CommonJS config files, as the template ships them.
    files: ['*.config.js'],
    rules: { '@typescript-eslint/no-require-imports': 'off' },
  },
  globalIgnores(['.next/**', '.open-next/**', '.wrangler/**', 'out/**', 'build/**', 'next-env.d.ts']),
]);

export default eslintConfig;
