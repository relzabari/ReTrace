# Session logout

`POST /api/v1/auth/logout?scope=local|global` requires a Bearer access token.

- `local` is the explicit default: Supabase revokes refresh tokens for the current session only. This is a session (browser profile/app installation), not all browsers or sessions on a physical device.
- `global` revokes refresh tokens for all sessions of the authenticated account, including the caller. The caller cannot provide a target account ID. The server forwards the caller's token with the publishable API key; no admin key is used.
- Only Supabase's documented 204 response is reported as success. Invalid/expired credentials return 401, rate limiting returns 429, and unavailable/failed revocation returns 503.
- This endpoint deliberately does not depend on the local active-user/profile check: a disabled account should still be able to revoke a valid session through Supabase.

## Client behavior

Web and mobile provide current-session and all-session logout actions. Global logout requires confirmation. An expired access token triggers at most one refresh and one retry; the same scope is preserved.

Local credentials are deleted even if the network or provider fails. The user is explicitly told when server revocation was not confirmed; signing in again and selecting global logout online is the recovery path. No refresh tokens are kept in a retry queue.

Web logout invalidates pending refresh responses so they cannot write tokens back after logout. Mobile stops new authenticated requests and waits for an existing refresh before revocation and local deletion. Restore failures perform only local cleanup, not an unintended remote signout.

Deploy the backend before the updated clients. Website changes become available with that deployment; mobile changes require a new Flutter build installed on devices. Old mobile builds only perform local cleanup and must be updated to use server revocation.

## Access-token lifetime

Supabase logout revokes refresh tokens. Already-issued JWT access tokens can remain valid until their configured expiry. ReTrace continues to validate protected requests via Supabase `/user`, without claiming a separate immediate access-token revocation guarantee. An already-running app on another device may not return to login until its next failed request/refresh.

Check the JWT expiry setting in the project's Supabase Auth settings. No live project configuration or expiry setting is changed by this PR. A backend session denylist or session-existence enforcement would be a separate change if immediate invalidation of every issued access token is required.

References:
- https://supabase.com/docs/guides/auth/signout
- https://github.com/supabase/auth/blob/master/openapi.yaml (`POST /logout`)

## Validation

```bash
python -m pip install -r backend/requirements-dev.txt
PYTHONPATH=backend python -m pytest backend/tests -q
node --test backend/tests/logout_web.test.cjs
```

Provider calls are simulated: tests check default/explicit scopes, refresh-token rejection after local/global revocation, isolation of another account, invalid credentials, invalid scope, provider failures and repeated logout. Node executes the actual web logout/refresh/cleanup functions with fake fetch/storage, covering expired-token retry, offline cleanup, cancellation and a refresh/logout race.

No real Supabase session was revoked during testing. Live provider behavior, browser UI and the Flutter build still need staging/device verification.
