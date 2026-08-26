Cloudsmith Auth
===============

Authenticate with Cloudsmith, writes token to `CLOUDSMITH_API_KEY`.
If `CLOUDSMITH_API_KEY` is a repository secret, validate it and return (no OIDC).

Usage:

```yaml
permissions:
  id-token: write   # only needed for OIDC path
  contents: read

steps:
- uses: analogdevicesinc/shared-actions/cloudsmith-auth@main
  with:
    namespace: ${{ vars.CLOUDSMITH_NAMESPACE }}
    service-slug: ${{ secrets.CLOUDSMITH_SERVICE_SLUG }}
    api-key: ${{ secrets.CLOUDSMITH_API_KEY }}
```
