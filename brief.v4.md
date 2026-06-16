# Haiku for Strangers — Brief

> **Status:** iOS pivot draft
> **Version:** 4.0
> **Supersedes:** `brief.final.md` (v3.0, responsive web app)
> **Purpose:** Foundational brief for an anonymous, ephemeral collaborative haiku iOS app
> **Tone:** Small, fleeting, unowned

---

## 0. What Changed From v3

This version makes two deliberate shifts from the v3 brief:

1. **Platform: iOS-native first, not responsive web.** The idea is being vetted as an iOS app. A phone is a more intimate surface, native motion and haptics sell the ceremony, and — most importantly — push notifications transform the app's hardest problem (waiting) from a dead-end into a gentle invitation. Web remains a plausible future, not the starting point.

2. **Connection model: durable and asynchronous, not strictly live.** A matched pair forms a *thread* that persists. If one person steps away, the connection holds and the other simply waits — and is brought back by a push notification when there is a response. Composition can happen live (both present) or across time (write a line, leave, the partner answers later). The v3 model of synchronous turns with a short, unforgiving reconnect grace is replaced by a patient, resumable thread.

These two shifts reinforce each other. They also reframe what "ephemeral" means here — see Section 3.

What did **not** change: the philosophy, the haiku form, the refusal of identity/ownership/archive, the soft (non-enforced) syllable guidance, and the principle that the artifact carries the emotional weight while the backend protects the lightness.

### Decisions locked for v1

These were open in early drafts and are now settled. They are reflected throughout this brief.

* **Composition model: hybrid.** Write together live when both participants are present; fall back to note-and-wait + push when one steps away.
* **Outer expiration bound: short — 1–2 hours.** A poem awaiting an absent partner stays open on the order of an hour or two, then gently dissolves. Patient enough to survive a step away, short enough that the thread still feels of-the-moment rather than like durable correspondence. Each new line refreshes the clock.
* **Transport: HTTPS + APNs.** Submissions and state fetches over plain HTTPS; push notifications drive all re-engagement. No continuously held socket in v1. The "live, both present" half of the hybrid model is approximated by APNs delivery to foregrounded apps plus light foreground polling — near-live, not instant. A true WebSocket layer is a deferred upgrade for if/when the present-together case demands more immediacy.
* **v1 target: thin slice → TestFlight.** Match → write three lines → reveal → dissolve, plus the push re-engagement loop. Minimal abuse rails for the first internal/TestFlight cohort; the fuller App Store UGC stack (Section 13) is layered in before any public submission.

---

## 1. Core Idea

This is an iOS app that connects two anonymous people to create a short poem together, line by line.

One person begins. The other responds. They alternate until the poem is complete. The turns may happen in the same minute or across hours — the connection between the two strangers holds either way. When the poem is finished it is shown briefly to both participants, then disappears.

There are no accounts, no profiles, no saved history, no social graph, and no durable ownership of what was made.

The point is not accumulation. The point is the exchange.

---

## 2. Creative / Philosophical Intent

This project explores joy, beauty, and connection without requiring those things to justify themselves through utility, identity, permanence, or value extraction.

The app should resist the normal patterns of digital products:

* no personal brand
* no followers
* no content library
* no collection mechanic
* no archive
* no streaks, badges, or engagement loops
* no optimization toward retention through ownership

The experience should feel more like a passing encounter than a platform — and now, sometimes, like leaving a folded note for a stranger and trusting them to answer.

Key ideas:

* **ephemerality is a feature** — but it lives in identity and the artifact, not necessarily in speed
* **anonymity protects tenderness**
* **constraint creates intimacy**
* **patience is allowed** — a held, unanswered line is part of the form, not a failure
* **meaning does not need to become utility**
* **shared creation does not need to become property**

This is a small machine for making unkeepable things.

### A note on installing an app

The v3 brief worried that turning this into an installable app-object might make it feel possessive — something owned and accumulated. That concern is valid and is answered not by avoiding the App Store but by the app's *internal* behavior. Resistance to possession lives in what the app does: nothing is kept, there are no accounts, no library, no badges, no streaks, and the only notification the app ever sends is "a stranger is waiting for your line." An app can be installed and still refuse to be a possession.

---

## 3. What "Ephemeral" Means Now

Because connections are now durable, the meaning of ephemerality must be stated precisely, or the project loses its center.

**Strict and non-negotiable:**

* no durable user identity
* no accounts, profiles, or recoverable history
* no archive of completed poems
* the finished poem dissolves and is not retrievable
* participants can never identify, re-contact, or build a picture of each other

**Allowed to be patient:**

* an in-progress poem may live for a bounded window (1–2 hours), awaiting a partner's next line, refreshed on each new line
* a matched connection survives one or both participants closing the app
* a participant may leave and return to their single active poem

So: the *session* is allowed to wait. The *identity* and the *artifact* are not allowed to persist. Ephemerality is about what is kept and who can be known — not about how fast the moment must pass.

---

## 4. Success Criteria

The initial version succeeds if:

* a first-time anonymous user can install, open, and understand the experience within a few seconds of first turn
* two strangers can complete a full poem with no explanation beyond the interface — whether they write together in one sitting or across time
* a participant can step away mid-poem, close the app entirely, and be drawn back gently to finish — without the poem feeling broken or lost
* the act of waiting for a partner's line feels like patient anticipation, not a stalled process
* completed poems disappear cleanly and unmistakably
* no part of the experience implies ownership, collection, identity, or social continuation
* a durable *connection* never becomes a durable *identity* — the other participant remains unknowable
* the backend can sustain many simultaneous patient sessions with minimal, bounded, self-expiring state
* abuse controls exist without dragging identity or permanence into the main user experience
* the app can plausibly satisfy App Store review requirements for user-generated content (see Section 13)

These criteria give future decisions something to push against.

---

## 5. Product Shape

### User flow

A person opens the app to a brief threshold — a quiet landing state with a single action to enter. They are not auto-enqueued. The threshold exists so the user feels they are choosing to step into the ritual rather than being dropped into a queue.

Once they enter:

1. they are placed in a lightweight anonymous session
2. they are matched with one other anonymous participant — immediately if someone is waiting, or when one next arrives (and a push can bring them back for it)
3. they see the lines written so far and write the next line when it is their turn
4. when it is the other person's turn, they may stay and watch for a live response, or leave entirely and be notified later
5. when the poem completes, they see it briefly
6. they watch it vanish

Then the interaction ends. Nothing remains.

### The two kinds of waiting

This app has two distinct waiting experiences, and both are now softened by push:

* **Waiting for a match** — no partner yet. The user can stay in the quiet anteroom, or leave; a push arrives when a stranger appears.
* **Waiting for a line** — matched, but it is the partner's turn and they are away. The user's line has been sent; they wait for an answer. A push arrives when the partner responds.

Neither should feel like a loading screen or an error. Both are "someone might be here soon," not "something is broken."

### Poem visibility during composition

Each participant sees all lines written so far before contributing the next line. The poem accumulates visibly, and the full shape is revealed together at the end through the dissolution sequence.

### Non-goals

This is explicitly **not**:

* a social network
* a chat or messaging app
* a dating app
* a pen-pal or correspondence platform with durable threads
* a community platform
* a content publishing system
* a poem archive
* a personal poetry notebook

The durable connection is a single-poem thread between two anonymous strangers. It is not an ongoing relationship, and it ends when the poem does.

---

## 6. Platform Direction

The initial implementation should be a **native iOS app (SwiftUI)**.

Reasons:

* **Push notifications** make patient, asynchronous composition possible without forcing anyone to sit and stare at a screen — directly solving the v3 brief's hardest problem (the waiting/cold-start experience).
* A phone held in the hand is a more intimate surface for a tender, private ritual.
* Native animation, transitions, and haptics let the reveal and dissolution feel like real, physical moments rather than CSS performances.
* Strong, system-level accessibility (Dynamic Type, VoiceOver, Reduce Motion) is available for free if respected.
* **TestFlight** gives a controlled cohort for vetting the idea before any public release.

Costs accepted for now:

* installation friction (mitigated: vetting is the goal, not reach)
* App Store review for anonymous user-generated content (addressed in Section 13)
* a single platform initially (Android and web are deferred, not rejected)

No login, signup, or durable user identity should exist in the experience. Everything is anonymous.

A future responsive web client could share the same backend; nothing in this design precludes it.

---

## 7. Anonymity Model (Expanded)

Anonymity is the load-bearing principle, and the durable-connection change puts new pressure on it. The pressure is handled by a strict separation between *infrastructural identifiers* and *user identity*.

### The boundary

**Anonymous** means: no participant can identify, re-contact, or build a profile of the other. The other person is, and remains, a stranger.

It does **not** mean the system is blind to operational signals. The system may use short-lived, infrastructural identifiers for coordination and abuse prevention:

* a **session/resume token** held on-device (e.g., in the Keychain), scoped to the single active poem, so a returning user can rejoin their own thread
* an **APNs push token**, so the away participant can be notified there is a line waiting
* **IP-derived rate-limit keys** and Apple **DeviceCheck / App Attest** for abuse throttling

These are infrastructural only. They never become user-facing identity, are never shown to the other participant, and are erased when the session ends.

### Rules this boundary implies

* The push token maps to a *device's current session*, not to a person. No cross-session history is keyed to it for product purposes.
* The on-device resume token is scoped to the single active poem and is destroyed on completion or expiry. The device does not accumulate a record of past poems or partners.
* No participant ever receives any identifier, token, or signal that could be used to recognize or re-contact the other — in this session or a future one.
* Future decisions must not creep into device identity, reputation scoring, shadow profiles, or behavioral fingerprinting that would constitute durable identity by another name. DeviceCheck/App Attest may be used to *throttle abuse*, not to *profile users*.

A durable connection is permitted. A durable identity is not.

### External recording

The system does not provide saving or sharing features, but cannot prevent participants from screenshotting what they see. This is acknowledged and accepted. Ephemerality is a property of the system, not a guarantee about the universe.

### Likely user-visible states

* landing / threshold
* waiting for match
* matched — my turn
* matched — their turn, present (waiting live)
* matched — their turn, away (line sent, can close app)
* returning to an in-progress poem
* completed poem reveal
* poem dissolved / session ended
* gentle "no one came" / "your partner never returned" conclusion

---

## 8. Frontend Direction

The backend coordination layer is well-defined, but the frontend is where the emotional experience actually lives. The pacing, the feel of waiting, the moment of dissolution — these are design problems, not just engineering problems.

### Emotional tone

The UI should feel quiet, unhurried, and slightly ceremonial. Not a productivity tool, a game lobby, or a social feed. The closest analogy is a small physical ritual — lighting a candle, folding a note, slipping it under a door.

### Design principles

* **restraint over decoration** — minimal UI surface, generous whitespace, no ornament that doesn't serve the moment
* **typography is the primary design material** — the poem is the visual center; everything else recedes
* **animation serves meaning, not delight** — transitions should feel like breathing, not performance; the reveal and dissolution are the most important animated moments in the app, and native iOS animation should be used to make them feel physical
* **haptics, sparingly and meaningfully** — a soft haptic at the arrival of a partner's line or at the moment of dissolution, never as gamified feedback
* **no chrome that implies permanence** — no save buttons, no share icons, no history indicators, no UI that suggests the poem will persist

### Pacing and transitions

The app has a natural emotional arc: anticipation (waiting) → intimacy (writing together) → revelation (the completed poem) → loss (dissolution). The frontend should honor this arc through pacing. Transitions between states should not be instantaneous — they should have just enough duration to feel like something is happening, not just changing.

### The waiting states

Both kinds of waiting (Section 5) deserve dedicated design attention. Neither should feel like an error, a loading screen, or a queue.

* **Waiting for a match** should feel like being alone in a quiet room where someone else might arrive. Consider ambient motion, a shift in light, a sense of anticipation. If no match arrives, the user can leave and be pushed later, or be offered gentle re-entry — never an apology or an error.
* **Waiting for a partner's line** should feel like the held breath after passing a note. The interface should make clear the line was received and it is now genuinely fine to put the phone down — the app will reach out when there is an answer.

### The dissolution

The moment the poem disappears is the emotional climax of the app's philosophy. It should not feel like a screen dismissal or a timeout. It should feel like watching something dissolve. This is worth significant design investment, and native animation makes it achievable.

### Accessibility

This app is minimal and text-driven, which makes accessibility easier to do well. Accessibility is a first-class design principle, not an afterthought.

* strong text contrast throughout all states
* full **Dynamic Type** support — the poem must remain beautiful at large text sizes
* **VoiceOver**-readable state changes (turn transitions, partner arrival, poem completion)
* **Reduce Motion** support for the reveal and dissolution animations
* waiting and turn status communicated clearly, not only visually
* sensible focus and announcement management across state transitions

A small app that does accessibility well shows self-respect.

---

## 9. Poem Structure and Constraint Enforcement

### Decision: Soft guidance, not hard enforcement

The app uses the haiku form (5-7-5 syllables across three lines) as a creative frame, but does **not** enforce syllable counts.

### Rationale

Programmatic syllable counting in English is unreliable. Dictionary-based approaches miss proper nouns, slang, neologisms, and creative language — exactly what people reach for in poetry. Algorithmic heuristics (counting vowel clusters) are fast but imprecise.

Hard enforcement means a stranger's creative contribution gets rejected by a syllable counter that is sometimes wrong. That is a terrible emotional experience in a context designed around tenderness. It turns the machine into an arbiter of poetry, which is antithetical to the project's spirit.

### Implementation stance

* **On-device syllable indicator:** Show a live, approximate syllable count as the person types. Style it as a gentle guide — a small number, not a progress bar or a gate. A reasonable heuristic (vowel cluster counting) is sufficient.
* **No server-side syllable validation:** The server accepts any submitted line. It validates turn order, session membership, and basic content checks (length limits, non-empty), but not meter.
* **UI framing does the real work:** The threshold, the prompt language, and the structure of three alternating turns make the haiku form clear. The constraint is communicated as an invitation, not enforced as a rule.
* **Target syllable count per line is visible:** Each line's target (5, 7, or 5) is shown alongside the input, so both participants share the same creative frame.

### Turn structure

A completed poem consists of exactly **three turns**:

1. Participant A writes line 1 (target: 5 syllables)
2. Participant B writes line 2 (target: 7 syllables)
3. Participant A writes line 3 (target: 5 syllables)

The assignment of who goes first is random at match time.

### Intentional asymmetry

The same participant writes the first and third lines, giving the poem a sense of opening and return. Authorship weight is uneven — one person contributes two lines, the other one. This asymmetry is intentional: a frame by one voice with an interruption by another, which has its own beauty.

---

## 10. Core Technical Framing

This system is not primarily a CRUD app with durable user content.

It is an **ephemeral session orchestration system** — now with patient, resumable sessions.

The core technical problem is:

* accepting anonymous arrivals
* matching participants (possibly asynchronously, via push)
* maintaining a small shared poem state that may live for hours
* enforcing turn-taking across presence and absence
* notifying an absent participant that it is their turn
* allowing a participant to leave and rejoin their single active poem
* briefly revealing the result
* deleting the session and all associated infrastructural identifiers

The backend should be optimized for **coordination**, not storage.

---

## 11. Technical Priorities

### Prioritize

* low-friction matching, including asynchronous match-by-push
* reliable, timely push notifications for turn handoff and match
* cheap handling of many concurrent *patient* sessions
* minimal, bounded state size per session
* simple, aggressive cleanup of expired sessions and tokens
* very low durability requirements (bounded, not permanent)
* graceful handling of app backgrounding, termination, and return
* horizontally scalable coordination

### De-prioritize

* long-term storage
* user management / accounts / recovery
* profile systems
* permissions complexity
* durable ownership of content
* heavy relational modeling

---

## 12. Backend Direction

### Recommended stack direction

* **Go** backend, one deployable service with modular internal packages
* **APNs** integration for push notifications (match-ready and your-turn)
* **Redis** for transient coordination and ephemeral session state with TTLs
* a transport for live interaction and submission (WebSockets when foregrounded, with HTTPS request/response as a simpler baseline — see open questions)
* optional lightweight reverse proxy in front
* no SQL database in the core path initially; a narrowly-scoped store only for the moderation exception (Section 13)

### Why this shape fits

The app needs many lightweight connections, small state objects, real-time-ish event flow, aggressive expiration, and simple horizontal scaling. Go handles concurrency well; Redis handles ephemeral coordination, queues, presence, and TTL expiration with minimal ops burden.

The asynchronous model slightly changes the transport question. Because a session no longer requires a continuously held socket — a participant can be fully offline between turns — the system leans on **push as the re-engagement mechanism** and treats any live socket as an enhancement for the present-together case, not a requirement. This is called out as an open question in Section 19.

### Backend mental model

Three responsibilities, which may live in one service initially:

* **Gateway** — establishes anonymous sessions, accepts user actions, pushes state transitions to connected clients. (Unlike v3, it does not serve a web app.)
* **Matchmaker** — maintains the waiting pool, pairs participants, creates sessions, assigns first turn, and triggers a match push to an away user.
* **Session runtime** — tracks poem progress, validates whose turn it is, accepts line submissions, manages the patient/absent states, triggers your-turn pushes, enforces the outer expiration bound, reveals the completed poem, and erases session data.

A **push notifier** component wraps APNs and is used by the matchmaker and session runtime.

---

## 13. Moderation, Abuse, and App Store Reality

An anonymous user-generated-content system needs moderation, and on iOS this is not optional — App Store Review Guideline 1.2 requires UGC apps to provide content filtering, a reporting mechanism, a way to act on reports, and a way to deal with abusive users. The durable, push-driven connection also widens the abuse surface: an abusive line can be *pushed* to someone who has put their phone down.

### The core constraint

In an anonymous, ephemeral system, the **only person who can report abuse is the other participant**, and the evidence (the poem) is designed to disappear. This shapes every moderation decision.

### Minimum requirements

* rate limiting on session creation and line submission
* basic anti-spam controls (reject empty lines, over-length input, rapid-fire submissions)
* on-submission filtering of obviously abusive or malformed content, so the worst material never reaches the partner's push
* a **reporting mechanism** available when a line is received, during the reveal, and for a brief grace period after dissolution
* the ability to **act on reports** and to throttle/block abusive devices (via DeviceCheck/App Attest and IP throttling — infrastructural, not identity)
* a published EULA with a zero-tolerance clause for objectionable content (an App Store requirement for UGC)

### Reporting design

* A report should capture the poem content and minimal session metadata *before erasure*, routing it to a moderation queue — the **one deliberate exception** to the app's ephemerality principle.
* Reported content may be retained temporarily for review. This is narrow and justified: moderation requires evidence.
* Because lines can now arrive asynchronously via push, a recipient should be able to report a line on receipt, not only at reveal.

### Philosophy

Moderation should exist behind the curtain, not as a social layer. The poem remains the visible object; enforcement stays infrastructural. The line to protect is the other participant's willingness to be open with a stranger.

### Operational anti-abuse

* IP-based rate limits on connection and session creation
* DeviceCheck/App Attest throttling for repeat abuse (without building durable identity)
* per-IP and global connection caps
* message size limits on all submitted content
* turn submission idempotency (prevent duplicate line submissions from retries)
* connection/abuse detection (rapid connect/disconnect or create/abandon cycling)

### App Store vetting path

* **TestFlight first.** Vet the idea with a controlled cohort under lighter review before any public submission.
* The reporting + filtering + EULA + act-on-reports stack above is designed to satisfy Guideline 1.2.
* **Open risk:** the guideline's "block abusive users" expectation assumes durable identities to block, which this app deliberately lacks. Device-level throttling plus reporting is the proposed substitute; reviewer acceptance is unproven and is an explicit risk to validate early.

---

## 14. Session Model

Each poem session consists of:

* two anonymous participants (referenced by ephemeral, infrastructural IDs)
* a small shared poem state (up to three lines)
* a strict turn order (three turns total)
* the current turn and whose turn it is
* presence/away status per participant
* per-participant push tokens (infrastructural, erased on session end)
* a soft "live turn" expectation and a hard outer expiration bound (see Section 19)
* a short reveal window after completion
* automatic expiration and full erasure if abandoned or finished

Possible session fields:

* session ID
* participant A / B ephemeral IDs
* participant A / B presence state
* participant A / B push tokens (transient)
* current turn (1, 2, or 3)
* line 1 / line 2 / line 3
* session status (waiting, matched, awaiting-line-live, awaiting-line-away, complete, revealing, dissolved)
* created timestamp
* last-activity timestamp
* outer expiration timestamp

This is still tiny state — it simply lives a bit longer.

### Redis usage

* waiting queue
* active session objects (with generous-but-bounded TTL, refreshed on activity)
* session membership / resume lookup keyed by resume token
* push-token mapping per active session
* presence/heartbeat keys for the live case
* pub/sub or equivalent cross-node signaling if needed for live delivery

---

## 15. Waiting, Timeouts, and the Asynchronous Question

This system will live or die by how it handles waiting and cleanup.

### Two-tier timing

The asynchronous model replaces v3's single short per-turn timer with two horizons:

* **Soft / live window:** when both participants are present and composing together, gentle pacing applies — enough structure to keep momentum, but not a punishing 90-second gate.
* **Hard / outer bound:** an in-progress poem awaiting an absent partner persists for **1–2 hours** (v1 default), after which it gently expires if untouched. Each new line refreshes the clock.

When the outer bound passes with no completion, the poem dissolves and both participants — when next seen — are met with a gentle conclusion, not an error.

### Match-waiting

* A user waiting for a match can either stay in the quiet anteroom or leave; a push arrives when a partner appears.
* Match-waiting should still have a sensible bound; "no one is here right now, we'll let you know" is the tone, not "request timed out."

### Cleanup

TTL-based cleanup remains the backbone:

* waiting-queue entries expire
* presence keys expire (live case)
* session state has a bounded lifetime, refreshed on activity, hard-capped by the outer bound
* reveal state expires
* push tokens and resume tokens are erased on session end

No zombie state should accumulate. The session is patient, not immortal.

### Transport (decided: HTTPS + APNs)

Because participants can be fully offline between turns, the system does **not** require a continuously held connection. v1 uses **HTTPS for submissions and state fetches, with APNs driving re-engagement.** There is no held socket.

The hybrid model's "live, both present" half is approximated rather than socket-true: APNs delivers to foregrounded apps, and the client does light foreground polling, so a partner's line appears within a second or two while both are looking. This is near-live, not instant — an acceptable tradeoff for vetting.

A **WebSocket-when-foregrounded** layer remains a clean future upgrade if the present-together case turns out to deserve genuine immediacy. Nothing in the HTTPS + APNs design precludes adding it later.

---

## 16. Reconnect and Return Behavior

In the v3 model, reconnection was a short, unforgiving grace window. In this model, **return is a first-class, expected behavior**.

* A participant can close the app entirely and return to their single active poem at any time within the outer bound, via the on-device resume token.
* Re-opening the app while a poem is in progress should drop the user straight back into that poem's current state — not the threshold.
* If the partner has stepped away, the returning user sees the patient waiting state, not a broken one.
* The only thing that ends a session early is completion, the outer expiration bound, an explicit leave, or a moderation action.

This durability is bounded by the rules in Section 3: the connection is resumable, but the identity behind it is not recoverable or knowable, and nothing survives the poem's end.

---

## 17. Failure Handling Philosophy

The app should tolerate imperfection. A poem disappearing is unfortunate, not catastrophic. This is not banking software; it is a small, fragile interaction.

### Acceptable

* occasional loss of in-flight poems
* sessions that dissolve at the outer bound if a partner never returns
* hard expiration of dead state
* a missed or delayed push occasionally costing a match

### Not acceptable

* systemic queue stalls
* server behavior that violates turn order
* state leaks that accumulate endlessly
* resource growth from abandoned (but not expired) sessions
* push tokens or resume tokens outliving their session
* abuse without any response path

---

## 18. Observability Priorities

Metrics should focus on system health, not engagement theater. Useful metrics:

* active sessions (live and patient/away)
* waiting-queue depth and median match wait time
* match failure rate (waits that expire without matching)
* poem completion rate and time-to-completion distribution (now potentially long)
* push delivery success/latency for match and your-turn notifications
* abandonment / outer-expiration rate
* return rate (participants who leave and come back to finish)
* Redis latency, per-node memory, message throughput
* moderation rejection count and report submission rate

These answer whether the little machine is alive and functioning.

---

## 19. Strong Architectural Warning

Do not accidentally build this like a conventional social/content/messaging app. Avoid defaulting into:

* a users table
* a poems table as durable canonical content
* REST CRUD around saved poem objects
* a profile model
* message history / threads as a durable inbox
* relationship graphs or contacts
* feed logic

The durable connection is a *single-poem coordination thread*, not a messaging inbox. Treat it as ephemeral coordination state that happens to be patient — not as correspondence to be stored.

---

## 20. Implementation Bias

Initial implementation should favor:

* one SwiftUI iOS app
* one Go backend service with modular internal packages (`gateway`, `matchmaker`, `sessions`, `presence`, `push`, `moderation`, `metrics`)
* Redis for transient state; a narrow store only for the moderation exception
* APNs for re-engagement
* simple event flow and bounded session state machines
* minimal infrastructure complexity

Avoid early service sprawl. Keep it austere.

---

## 21. Open Questions for the Build Phase

Resolved (see "Decisions locked for v1" in Section 0): composition model, outer bound, transport, v1 scope.

Still open:

* soft/live pacing values when both are present (how much gentle structure, if any, on a live turn)
* moderation thresholds, tooling, and the App Store "block users" risk (Section 13)
* whether completed poems show for a fixed duration or until dismissal with a hard cap
* language support / matchmaking segmentation
* specific UI copy for the threshold, waiting states, return, and dissolution
* specific ambient/animation direction for the waiting states and dissolution
* whether a "no one came" state offers anything beyond push re-entry (a solo prompt, a found poem)

---

## 22. Summary

This is an anonymous iOS app for making tiny poems with strangers and letting them disappear.

It rejects identity, ownership, history, and social accumulation in favor of brief shared creation. A matched pair forms a patient, resumable thread: turns can happen live or across time, and a push gently calls an absent partner back. The connection is allowed to wait; the identity behind it never becomes knowable, and nothing survives the poem's end.

Technically, it is a lean real-time-ish coordination system: small state, turn-taking across presence and absence, push-driven re-engagement, aggressive expiration, and minimal persistence.

The app carries the emotional weight. The backend protects the lightness of the thing.

Nothing is kept unless moderation requires it.

Something happens, and then it is gone.
