# Claude DeepSeek Gateway Site

This is the English-first Vercel landing page for Claude DeepSeek Gateway.

## Local Development

```bash
pnpm install
pnpm dev
```

## Verification

```bash
pnpm lint
pnpm build
```

## Vercel

Use Vercel Git Integration for automatic deployments from GitHub.

Connect the Vercel project to this repository:

```text
Repository: JUNERDD/claude-deepseek-gateway
Production Branch: main
```

Configure the Vercel project with this directory as the root:

```text
Root Directory: site
Build Command: pnpm build
Install Command: pnpm install --frozen-lockfile
Output Directory: .next
```

With Git Integration enabled:

- Pushes to `main` create production deployments.
- Pull requests and non-production branches create preview deployments.

The linked production URL is:

```text
https://claude-deepseek-gateway.vercel.app
```

The Vercel CLI can help connect the current project to Git Integration:

```bash
pnpm dlx vercel@latest login
pnpm dlx vercel@latest link --project claude-deepseek-gateway
pnpm dlx vercel@latest git connect
pnpm dlx vercel@latest git ls
```

GitHub App authorization may still open in the browser if Vercel does not already have repository access.

The site intentionally does not include custom analytics scripts or cookies.
