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

Create a Vercel project with this directory as the root:

```text
Root Directory: site
Build Command: pnpm build
Install Command: pnpm install --frozen-lockfile
Output Directory: .next
```

The linked production URL is:

```text
https://claude-deepseek-gateway.vercel.app
```

CI/CD deployments are handled by `.github/workflows/vercel.yml`.

Required GitHub repository variable values:

```text
VERCEL_ORG_ID
VERCEL_PROJECT_ID
```

Required GitHub repository secret:

```text
VERCEL_TOKEN
```

The site intentionally does not include custom analytics scripts or cookies.
