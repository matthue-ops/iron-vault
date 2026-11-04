# Member portal agreement and account menu

## Deployment

After migration **031**, manually run **one copy** of `supabase/manual/member_portal_agreement.sql` in the gym Supabase project's SQL Editor. It is identical to migration 032. Then merge/deploy the frontend PR to Cloudflare. **No Edge Function deployment or Auth URL changes are required.** The agent has not executed SQL or deployed the app.

Platform and gym legal details must already be published using the existing legal editors. If documents or the new RPC are unavailable, members retain profile viewing while QR generation and self-service pass purchases remain unavailable. The UI explains how to review documents and that staff can assist with entry.

## Member behavior

The top-right notification bell remains separate. The new hamburger menu contains Personal Information & Security, Terms & Privacy, and Sign Out. The existing settings form is moved into a dialog; its IDs and save/recovery handlers are retained. It is no longer a large section in the main profile.

The notification bell combines unread announcement count with one persistent legal notice. Opening or reading announcements does not acknowledge terms. Review Documents opens the Terms & Privacy dialog and closes the announcement overlay so its keyboard trap does not interfere with the native dialog. The member must open/read the linked documents and explicitly tick the unchecked agreement before pressing Agree. The API action records the acceptance; the UI never makes an automatic acceptance call.

Before agreement, membership, balance and account information remain available. Account security/contact correction controls are retained. Only QR issuance/use and member pass purchases require the current agreement. Feature explanations remain beside those actions. Staff-assisted registration, purchases/top-ups, and manual admission continue to operate under their existing authorizations. No staff action records a member's online acceptance on their behalf.

If a matching signup receipt already exists, the profile unlocks without asking again. Terms & Privacy always offers the accepted versions and server-recorded agreement date. When a new platform or gym version is published, the old pair remains available and the new pair requires acceptance. Draft saves do not trigger renewed agreement. Every new publication is treated as requiring a new agreement; there is no separate material-change switch in this implementation.

## Server enforcement and records

No new consent table is created. `iv_member_legal_status()` reads only the authenticated active member's role, exact member/gym, current version pair and latest applicable receipt. `iv_member_legal_accept(platform,gym)` derives the member/account from auth.uid(), requires an enabled/non-revoked member role and active member/gym, checks the exact current pair under locks, and saves the server timestamp in existing private legal_acceptances. Repeated acceptance of the same pair reuses the record; member-row serialization prevents duplicate concurrent inserts. Prior receipts remain unchanged. A scoped lookup index is added for the status checks.

Only authenticated callers can execute these public RPCs; their SQL guards reject staff/owners/global administrators attempting to accept as a member, another member's identity, inactive/revoked access, missing publications or stale/wrong-gym versions. Direct table access remains revoked. Published versions and receipts are not deleted or rewritten by this migration.

The private current-agreement check is added to member-originated purchases in iv_financial_transaction, QR issuance in iv_issue_member_pass, and QR redemption in iv_redeem_member_pass. The original financial validations, request/actor/payload binding and ledger logic remain. Completed receipt retries return their saved result before the new gate, because they cause no new purchase. Staff-authorized operations bypass only this new member agreement gate, preserving their existing authorization checks. The private record_admission and manual iv_checkin functions are not replaced, so manual admission does not require a member portal agreement.

A QR generated before a new publication can no longer redeem until the member accepts the new pair. This prevents a cached QR from bypassing the rule; staff may use manual admission meanwhile. A rejected financial call with IV002 rolls back and clears only that rejected retry key; transport/unknown outcomes still retain their request ID for safe retries.

Publication of a legal version emits the existing gym/system metadata signal. Saving an acceptance emits the existing member signal so another open device can catch up. The client also checks on focus, after profile updates, before restricted actions and approximately every 20 seconds while visible/online. No new Realtime table publication or channel is introduced. Server enforcement applies immediately even before the browser refreshes its badge. Hidden/offline pages do not perform periodic status requests.

Identity checks, generations and signout handling discard late responses, close account dialogs and prevent another account's receipt from unlocking the current one. Network/status failures fail closed for restricted features while retaining the profile. Terms links pin the exact accepted platform and gym version IDs; consent does not opt members into marketing.

## Validation / project checks

Automated tests cover locked/unlocked states, explicit acceptance, prior signup receipts, version changes, accepted/current links, failure/identity guards, safe financial retries and SQL contracts. Browser tests use mocked APIs on phone/desktop layouts to exercise the moved security form, menu, bell notice, unchecked agreement, QR unlocking/relocking and offline read-only behavior. SQL and PL/pgSQL are syntax-parsed, not executed.

After installing 032, test real member/staff accounts: member direct purchase/QR RPCs denied before agreement; the member can still see their profile; staff can register/manual-check-in/purchase; acceptance saves exactly one record for the pair and unlocks features; another member cannot accept for them; an already-accepted self-registered member is not re-prompted; a new publication relocks only member self-service and preserves old accepted links; wrong/stale versions are denied. Confirm actual authorization and transaction behavior in your Supabase project before rolling out to real members.
