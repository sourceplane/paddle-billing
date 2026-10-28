// The product's name, written once: every page's <title>, the logo's
// alternative text and the dashboard's copy read it. A product built from this
// repository gets it rewritten to its own name at instantiation, so keep it
// literal and on one line.
// prettier-ignore
export const SITE_NAME = "AeroEdit"

// The site's own origin: the GitHub sign-in's return address and the metadata
// base for absolute links (Open Graph). Each deploy's build sets
// NEXT_PUBLIC_SITE_URL to its environment's origin (apps/web/component.yaml),
// which `next build` inlines; `next dev` falls back to localhost.
export function siteUrl(): string {
  return (process.env.NEXT_PUBLIC_SITE_URL || 'http://localhost:3000').replace(/\/+$/, '');
}
