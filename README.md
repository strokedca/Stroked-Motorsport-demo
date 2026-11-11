# Stroked Motorsports Events

V5.5 is consolidated on `v5.5-testing`. Main and live V5.4 remain on hold until explicit production deployment approval.

- [Public website](https://stroked.ca) — existing visitor address; V5.5 publication remains on hold
- [Testing website](https://v5-5-testing.stroked-motorsport-demo.pages.dev/)
- [Audit and completed testing](V55_TESTING_RELEASE.md)
- [Production deployment preparation](PRODUCTION_DEPLOYMENT.md)

Run `npm ci --ignore-scripts` and `npm test` for the eight regression checks. `npm run build:production` creates the reviewed production upload in `dist/`. Cloudflare's `npm run build` selects production only for main; other branches build against isolated testing data.

The production SQL is prepared and locally tested. Apply it only during the approved deployment sequence; do not upload the testing root configuration directly as the live site.
