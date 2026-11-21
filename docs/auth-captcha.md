# Stroked Auth verification

Use Cloudflare Turnstile's Free plan with Supabase Auth. Event browsing stays public and free. This does not change database grants, administrator MFA or existing sessions.

## Activation order

1. In the owner's Cloudflare account, create a Managed widget in Rest of World. Authorize `stroked.ca` and `stroked-motorsport-demo.pages.dev` only. Each hostname covers its own subdomains, including www and this project's branch previews. Leave pre-clearance disabled. Do not authorize the generic `pages.dev` domain or unrelated sites.
2. Put only the public **Site key** in `authCaptchaSiteKey` in `assets/stroked-config.js`. Never put the secret key in source, screenshots, chat or logs.
3. Deploy the frontend, verify the widget renders on the live account forms, and pass the regression suite/build. While preparing this, leave Supabase's CAPTCHA switch Off.
4. The owner copies the private **Secret key** directly into the Stroked project's Authentication → Attack Protection → CAPTCHA settings, selects Turnstile, enables protection and saves. The Supabase project is `aodywiwkhtxwlscpqnda`; do not change the separate Family Calendar project.
5. Privately test signing in with an existing account. Verify server enforcement separately: the widget alone is not server protection. Do not create member accounts, send real reset/confirmation emails or make RSVP records merely to test. Record the limits of any verification that was not performed.

All four unauthenticated Auth actions (signup, password sign-in, reset initiation, confirmation resend) send `options.captchaToken` using the pinned Supabase SDK. The client clears proofs when consumed, expired, rejected or the form closes/changes; Supabase validates the proof on the server. Authenticated password recovery continues using its recovery session without requiring a new proof. Its new password and signup both follow the already configured 12-character server minimum; existing-password login does not impose that new minimum.

## Failure and rollback

Visitors can retry a blocked script/widget from the form. No request is sent without a proof when the site key is configured. Tokens are kept only in memory, not in URL, storage, logs or a hidden response field.

If activation prevents sign-in, first disable CAPTCHA in Supabase and save, then correct or revert the frontend key/configuration. A frontend rollback to code without token support while server enforcement is On breaks sign-in. Keep the matching keys, hostname list and server setting together. Do not disable administrator MFA or weaken RLS to troubleshoot CAPTCHA.

## References

- https://supabase.com/docs/guides/auth/auth-captcha
- https://developers.cloudflare.com/turnstile/get-started/
- https://developers.cloudflare.com/turnstile/additional-configuration/hostname-management/
- https://developers.cloudflare.com/turnstile/reference/content-security-policy/
- https://developers.cloudflare.com/turnstile/plans/

The Cloudflare script must load from `https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit`; it must not be self-hosted or cached. CSP allows that provider origin only in `script-src` and `frame-src`, without broad script wildcards or inline-script exceptions.
