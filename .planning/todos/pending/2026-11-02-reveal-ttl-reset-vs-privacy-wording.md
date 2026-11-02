---
created: 2026-11-02T18:30:00.000Z
title: A reveal offer resets RevealTTL, stretching a finished poem past the privacy page's "two minutes"
area: api
severity: minor
files:
  - server/internal/gateway/gateway.go (handleTrade / handleDismiss re-save refreshes the session TTL)
  - server/internal/gateway/privacy.html (promises a two-minute reveal window)
---

## Problem

06-REVIEW.md WR-02 (2026-11-02): each save at the reveal (an offer, and the dismiss
rewrite's compare-and-set — behavior the old plain write already had) resets the session
TTL to the full RevealTTL (120 s). A finished poem can therefore live up to roughly
4 minutes of wall time while the privacy page says the reveal window is two minutes.

## Why not fixed now

The TTL refresh is arguably intentional — an offer must keep the reveal alive long
enough for the partner to answer, and shortening it changes trade UX. The drift is
between copy and behavior, not a leak: all state remains TTL-bounded and ephemeral.

## Solution sketch

Either (a) soften the privacy wording ("a few minutes") — pinned phrases in
privacy_test.go must move with it — or (b) stop refreshing the TTL on reveal-state
saves by preserving the remaining TTL in the compare-and-set. Decide deliberately;
(b) needs race tests around expiry during a pending offer.
