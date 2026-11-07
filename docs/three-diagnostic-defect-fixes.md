# Three confirmed diagnostic defects — focused fixes

This batch fixes only the financial retry-ID defect, wrong-member refund drafts and duplicate subscription polling. It does not implement the proposed completed-refund reversal, owner-only correction policy, Super Admin correction feature, new financial adjustment APIs, database changes or migrations. No deployment or SQL execution is authorized/performed for this batch.

## 1. Financial retry identity

`assets/financial-requests.js` now distinguishes a first attempt from a saved unresolved request. A definitive rejection on the first attempt can still release the request so an input/terms problem can be corrected. An already unresolved request is retained even if a subsequent attempt returns a known rejection: the later rejection cannot prove an earlier call never committed. Lost replies, invalid receipts and uncertain identity confirmations continue to retain the original request ID/payload. No replacement payment can be submitted in that same actor/tenant slot while unresolved. Retrying through the existing API with the original ID can recover its saved receipt without another credit. The warning explains that the earlier outcome remains unresolved.

A permanently unverifiable outcome remains blocked for reconciliation; this change intentionally does not introduce a new receipt-status RPC, force-clear button or balance-edit facility. Browser storage clearing or independently entering another transaction is not a financial reconciliation mechanism.

Regression: commit a 100-peso top-up but lose confirmation, receive a later P0001/IV002/IV003/42501/23505/22003 rejection, attempt a changed payment, then retry with restored access. The original ID is retained throughout, one 100-peso credit exists, the changed payment is blocked, and a valid saved receipt clears the slot. Fresh definitive rejections remain correctable. Legacy saved IDs are treated conservatively as unresolved.

## 2. Member-specific refund drafts

`assets/refunds.js` keeps separate in-memory drafts keyed by active user/gym/member, with member-specific saved request-ID keys. Explicit settlement for B always opens B's draft, even if A has unfinished work. Selecting a different member or recent transaction switches draft context; it cannot mutate the previous draft's member identity. Returning to A restores A's fields and generated reference. A submitted draft clears only its completed member slot; identity changes/sign-out clear private in-memory drafts. Form values are retained during the session; only request identity is stored in sessionStorage. No new personal-data cache is introduced.

Async previews and confirmations are bound to the reviewed draft so a late response cannot attach a reference/review to a different member's draft. Existing financial checks and refund request/approval RPCs remain unchanged.

Regression: prepare A's amount/reason/source/reference, close, open B through the positive-balance member-removal shortcut, prepare B's independent draft/reference, then switch back and forth. Both retain their own fields and distinct references; Edit/Back still work; sign-out removes private UI. Existing confirmation, approval and History flows also pass.

## 3. Subscription polling

`assets/subscriptions.js` assigns each polling lifecycle a generation. Initialization invalidates the old timer before awaiting startup. Both initialization and each poll recheck generation after awaited responses. Older responses do not update the gate/badge or schedule another timer. Pagehide/sign-out invalidate the active generation and clear its timer. The existing restored-page initialization establishes the new loop.

Regression: hold an old poll's response, reinitialize and schedule a replacement, then finish the old poll with a conflicting suspended state. One timer remains, and the current paid gate is preserved. Sign-out while a poll is pending leaves zero timers; pagehide leaves zero timers. Ordinary subscription review/payment flows remain unchanged.

## Validation

- 411 Node tests pass.
- New mocked Chromium boundary suite passes at 320/375/1280: separate member drafts and references, one subscription timer after overlap, old response ignored, zero timers after sign-out/pagehide.
- Existing mocked browser suites for refunds, pending payments, subscription review and staff access pass at their phone/desktop widths.
- Pages build, Dashboard consistency and whitespace checks pass.
- No SQL or live financial transaction was executed. No remote branch push or deployment is part of this batch. Any future deployment requires user approval.
