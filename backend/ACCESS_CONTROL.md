# Exercise access control

## Rules

- ADMIN can read and administer all exercises, including historical records.
- MANAGER can read/manage only exercises to which the account is assigned.
- USER can access only assigned exercises and only participants, tracks and events owned by that account. Command-room/web events and other participants' events are excluded, including from browser exports.
- Creating an exercise automatically assigns its creator.
- Only an assigned manager or ADMIN can grant/revoke exercise access. This does not change the account's global role.
- Creating a participant always binds it to the authenticated account. A request cannot choose another owner.
- Device sessions, uploads, participant events and finish notifications require ownership, including for managers/admins. Managers report web events as themselves.
- Existing server-generated videos may contain multiple participants and are readable only by assigned managers/ADMIN. Browser export remains available for a USER's own data.
- Revoking membership prevents further exercise access even when the account still owns participant records.

## Existing installations

Startup adds `exercise_members` and a nullable indexed `exercise_participants.user_id` foreign key. Existing accounts, participants, sessions, tracks and events are preserved. Historical participant ownership and exercise memberships are intentionally not guessed from names, roles, device IDs or timestamps.

After deployment an ADMIN must open each existing exercise and use **גישה לתרגיל**:

1. Add existing manager accounts by email, granting exercise management according to their global MANAGER role.
2. Add participant accounts by email. When identity is verified, optionally select an unowned historical participant to associate its existing data with that account.
3. Use **הסר גישה** to revoke membership. This preserves historical data but blocks subsequent access.

Existing MANAGER/USER accounts will not see historical exercises until assigned. An owned participant cannot be transferred silently to a different account. ADMIN retains recovery access. New participants are bound automatically and do not need manual ownership assignment.

Deploy the updated backend before the updated mobile build. Old mobile builds remain subject to server authorization, but cannot isolate their local queue by account/session. Upgrade the mobile app before switching accounts or starting another tracking session on a shared device.

Mobile SQLite schema v3 scopes pending uploads, counters and acknowledgements to the authenticated account and exact device session. Legacy queued rows with unknown ownership stay on-device and are not uploaded as a new identity. Pending rows from an earlier session are also retained rather than relabelled. Finish syncing the current exercise with the old app before upgrading where possible; recovery/resume of old queues is not implemented by this change. No server or local history is deleted by this migration.

## Validation

From the repository root:

```bash
python -m pip install -r backend/requirements-dev.txt
PYTHONPATH=backend python -m pytest backend/tests -q
```

HTTP regression tests use SQLite with a stub for the spatial JSON function. They exercise actual authorization dependencies/queries, read isolation, forged ownership, session access, export isolation, membership grant/revoke, historical assignment, and creator access. A separate SQL test checks mobile queue isolation including a v2 migration.

These tests do not validate PostgreSQL/PostGIS startup migration or build/run the Flutter app. Verify both on a staging deployment and device before production rollout.
