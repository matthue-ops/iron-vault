# FUT-002: Command Center authentication

Status: **PRELIMINARY IDEA — REVISIT AND DISCUSS BEFORE DEFINING A FINAL SCOPE**

This note is a starting point for discussion, not finalized requirements. Revisit this idea individually with the user; execution requires a separate explicit instruction after reviewing the scope.

Consider making Project Command Center private when more projects are added or the user needs a private launcher. The current decision is a public launch page; the gym app retains its own authentication.

Before revisiting, decide who needs launcher access and whether an additional login adds useful protection. Every application must retain its own server-side authorization: a launcher login must never be treated as authorization to an application reached directly.

Do not restore the retired embedded gym dashboard or duplicate gym-management entry points as part of this idea.
