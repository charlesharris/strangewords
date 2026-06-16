# Haiku for Strangers — Brief

> **Status:** Final draft
> **Version:** 3.0
> **Purpose:** Foundational brief for an anonymous, ephemeral collaborative haiku web app
> **Tone:** Small, fleeting, unowned

---

## 1. Core Idea

This is a responsive web app that connects two anonymous people to create a short poem together, line by line.

One person begins. The other responds. They alternate until the poem is complete. The finished poem is shown briefly to both participants, then disappears.

There are no accounts, no profiles, no saved history, no social graph, and no durable ownership of what was made.

The point is not accumulation. The point is the moment.

---

## 2. Creative / Philosophical Intent

This project explores joy, beauty, and connection without requiring those things to justify themselves through utility, identity, permanence, or value extraction.

The app should resist the normal patterns of digital products:

* no personal brand
* no followers
* no content library
* no collection mechanic
* no archive
* no optimization toward retention through ownership

The experience should feel more like a passing encounter than a platform.

Key ideas:

* **ephemerality is a feature**
* **anonymity protects tenderness**
* **constraint creates intimacy**
* **meaning does not need to become utility**
* **shared creation does not need to become property**

This is a small machine for making unkeepable things.

---

## 3. Success Criteria

The initial version succeeds if:

* a first-time anonymous user can arrive and understand the experience within a few seconds
* two strangers can complete a full poem with no explanation beyond the interface
* the waiting experience feels intentional rather than broken
* completed poems disappear cleanly and unmistakably
* no part of the experience implies ownership, collection, or social continuation
* the backend can sustain many simultaneous ephemeral sessions with minimal persistent storage
* abuse controls exist without dragging identity or permanence into the main user experience

These criteria give future decisions something to push against.

---

## 4. Product Shape

### User flow

A person visits the site and is presented with a brief threshold — a landing state with a single action to enter. They are not auto-enqueued. The threshold exists so the user feels they are choosing to step into the ritual rather than being passively dropped into a queue.

Once they enter:

1. they are placed in a lightweight anonymous session
2. they are matched with one other anonymous participant
3. they see the lines written so far and write the next line when it is their turn
4. they wait while the other person writes
5. they see the completed poem briefly
6. they watch it vanish

Then the interaction ends.

### Poem visibility during composition

Each participant sees all lines written so far before contributing the next line. The poem accumulates visibly, and the full shape is revealed together at the end through the dissolution sequence.

### Non-goals

This is explicitly **not**:

* a social network
* a chat app
* a dating app
* a community platform
* a content publishing system
* a poem archive
* a personal poetry notebook

---

## 5. Platform Direction

The initial implementation should be a **responsive web app**.

Reasons:

* no installation required
* works across phone, tablet, and desktop browsers
* low barrier to entry
* better aligned with the disposable, pass-through nature of the experience
* avoids turning the project into a possessive app-object too early

No login, signup, or durable identity should exist in the main experience.

Everything is anonymous.

---

## 6. Functional Principles

### Required principles

* anonymous by default and in practice
* no login
* no persistent user identity
* no recovery of prior poems
* no ability to re-contact or follow the other participant
* no ability to save or publish completed poems inside the system
* no account-based ownership model

### Anonymity model

The experience is anonymous between participants and avoids durable user identity. The system may still use short-lived technical identifiers — session tokens, IP-derived rate-limit keys, temporary fingerprints — for session coordination, abuse prevention, and rate limiting. These are infrastructural only and do not become user-facing identity.

This distinction matters: anonymous means no participant can identify, re-contact, or build a profile of the other. It does not mean the system is blind to operational signals. Future decisions should not creep beyond this boundary into device identity, reputation scoring, shadow profiles, or behavioral fingerprinting that would constitute durable identity by another name.

### External recording

The system does not provide saving or sharing features, but cannot prevent participants from externally recording what they see (e.g., screenshots). This is acknowledged and accepted. Ephemerality is a property of the system, not a guarantee about the universe.

### Likely user-visible states

* landing / threshold
* waiting for match
* poem in progress (my turn)
* poem in progress (their turn)
* completed poem reveal
* poem dissolved / session ended

---

## 7. Frontend Direction

The backend coordination layer is well-defined, but the frontend is where the emotional experience actually lives. The pacing, the feel of waiting, the moment of dissolution — these are design problems, not just engineering problems.

### Emotional tone

The UI should feel quiet, unhurried, and slightly ceremonial. It should not feel like a productivity tool, a game lobby, or a social feed. The closest analogy might be a small physical ritual — lighting a candle, folding a note.

### Design principles

* **restraint over decoration** — minimal UI surface, generous whitespace, no ornament that doesn't serve the moment
* **typography is the primary design material** — the poem is the visual center; everything else recedes
* **animation serves meaning, not delight** — transitions should feel like breathing, not performance; the reveal and dissolution of the poem are the most important animated moments in the entire app
* **no chrome that implies permanence** — no save buttons, no share icons, no history indicators, no UI that suggests the poem will persist

### Pacing and transitions

The app has a natural emotional arc: anticipation (waiting) → intimacy (writing together) → revelation (the completed poem) → loss (dissolution). The frontend should honor this arc through pacing. Transitions between states should not be instantaneous — they should have just enough duration to feel like something is happening, not just changing.

### The waiting state

Waiting for a match may be the most common experience during low-traffic periods. It deserves dedicated design attention. The waiting state should not feel like an error, a loading screen, or a queue. It should feel like the anteroom to something. Consider ambient elements — a subtle animation, a shift in light, a sense of anticipation rather than frustration.

If the wait ends without a match, the tone should be gentle and should invite return, not apologize.

### The dissolution

The moment the poem disappears is the emotional climax of the app's philosophy. It should not feel like a page redirect or a timeout. It should feel like watching something dissolve. This is worth significant design investment.

### Accessibility

This app is minimal and text-driven, which makes accessibility easier to do well. Accessibility is a first-class design principle, not an afterthought.

* strong text contrast throughout all states
* fully keyboard-accessible interaction on desktop
* screen-reader readable state changes (turn transitions, timer status, poem completion)
* reduced-motion support for dissolution and reveal animations
* timers communicated clearly, not only visually
* focus management across state transitions

A small app that does accessibility well shows self-respect.

### Responsiveness

The primary interaction is typing a single short line of text and reading a few lines. This should work beautifully on a phone screen. The layout should be simple enough that responsive adaptation is trivial — this is not a complex layout problem, it is a typography and spacing problem.

---

## 8. Poem Structure and Constraint Enforcement

### Decision: Soft guidance, not hard enforcement

The app uses the haiku form (5-7-5 syllables across three lines) as a creative frame, but does **not** enforce syllable counts server-side.

### Rationale

Programmatic syllable counting in English is unreliable. Dictionary-based approaches (like CMU Pronouncing Dictionary) miss proper nouns, slang, neologisms, and creative language — exactly what people reach for in poetry. Algorithmic heuristics (counting vowel clusters) are fast but imprecise, with roughly 5–10% error rates.

Hard enforcement means a stranger's creative contribution gets rejected by a syllable counter that is sometimes wrong. That is a terrible emotional experience in a context designed around tenderness. It turns the machine into an arbiter of poetry, which is antithetical to the project's spirit.

### Implementation stance

* **Client-side syllable indicator:** Show a live, approximate syllable count as the person types. Style it as a gentle guide — a small number, not a progress bar or a gate. Use a reasonable heuristic (vowel cluster counting is sufficient for guidance purposes).
* **No server-side syllable validation:** The server accepts any submitted line. It validates turn order, session membership, and basic content checks (length limits, non-empty), but not meter.
* **UI framing does the real work:** The landing page, the prompt language, and the structure of three alternating turns should make the haiku form clear. The constraint is communicated as an invitation, not enforced as a rule.
* **Target syllable count per line is visible:** Each line's target (5, 7, or 5) is shown alongside the input, so both participants share the same creative frame even without enforcement.

### Turn structure

A completed poem consists of exactly **three turns**:

1. Participant A writes line 1 (target: 5 syllables)
2. Participant B writes line 2 (target: 7 syllables)
3. Participant A writes line 3 (target: 5 syllables)

The assignment of who goes first is random at match time.

### Intentional asymmetry

The same participant writes the first and third lines, giving the poem a sense of opening and return. This means authorship weight is uneven — one person contributes two lines, the other contributes one. This asymmetry is intentional and part of the form. It gives the poem a frame by one voice with interruption by another, which has its own beauty.

---

## 9. Core Technical Framing

This system is not primarily a CRUD app with durable user content.

It is an **ephemeral session orchestration system**.

The core technical problem is:

* accepting anonymous arrivals
* matching participants
* maintaining a live shared poem state
* enforcing turn-taking
* handling disconnects and timeouts
* briefly revealing the result
* deleting the session

The backend should be optimized for **coordination**, not storage.

---

## 10. Technical Priorities

### Prioritize

* low-latency matchmaking
* cheap handling of many concurrent ephemeral sessions
* minimal state size
* simple cleanup of expired sessions
* very low durability requirements
* efficient handling of disconnects and session death
* horizontally scalable real-time coordination

### De-prioritize

* long-term storage
* user management
* account recovery
* profile systems
* permissions complexity
* durable ownership of content
* heavy relational modeling

---

## 11. Proposed Backend Direction

### Recommended stack direction

* **Go** backend
* **WebSockets** for live session communication
* **Redis** for transient coordination and ephemeral state
* responsive web frontend
* optional lightweight reverse proxy in front
* no SQL database in the core path initially

### Why this shape fits

The app needs:

* many lightweight ephemeral connections
* small state objects
* real-time event flow
* aggressive expiration / cleanup
* simple horizontal scaling

Go is a strong fit for highly concurrent connection handling.

Redis is a strong fit for:

* waiting queues
* session state
* presence / heartbeats
* TTL-based expiration
* transient routing / signaling

This allows the backend to remain small, fast, and operationally simple.

---

## 12. Backend Mental Model

The system can be understood as three responsibilities:

### 12.1 Edge / Gateway

The service users connect to.

Responsibilities:

* serve the web app
* establish anonymous session
* upgrade to websocket
* accept user actions
* push real-time state transitions to clients

### 12.2 Matchmaker

Pairs waiting users into poem sessions.

Responsibilities:

* maintain waiting pool
* match participants
* create active poem sessions
* assign first turn
* notify connected clients

### 12.3 Session Runtime

Maintains live poem state.

Responsibilities:

* track poem progress
* validate whose turn it is
* accept line submission
* enforce deadlines
* handle disconnects
* reveal completed poem
* expire and erase session data

These may live in one deployable service initially, even if conceptually separated.

---

## 13. State and Storage Philosophy

The system should assume that almost everything is temporary.

### Durable storage is not central

The app has extremely light requirements around:

* storage
* durability
* identity
* recovery
* long-term retrieval

That is a strength, not a missing feature.

### Ephemeral state is central

The system must handle transient state such as:

* anonymous session identifiers
* waiting queue membership
* active poem/session membership
* poem lines in progress
* turn ownership
* per-turn deadlines
* presence heartbeats
* completion / reveal windows

All of this can live in Redis with TTLs.

---

## 14. Connection Model

Use **WebSockets** for the live interactive experience.

Why:

* low-latency updates
* natural fit for waiting / matched / your turn / complete transitions
* tiny payload sizes
* simple real-time coordination model
* better than polling for this kind of live handoff

The traffic profile is lightweight:

* short events
* tiny text payloads
* minimal state transfer
* bounded session length

This should be very efficient.

---

## 15. Session Model

Each poem session consists of:

* two anonymous participants
* a small shared poem state
* a strict turn order (three turns total)
* a time limit per turn
* a short reveal window after completion
* automatic expiration if abandoned or finished

Possible session fields:

* session ID
* participant A ephemeral ID
* participant B ephemeral ID
* current turn (1, 2, or 3)
* line 1 (target: 5 syllables)
* line 2 (target: 7 syllables)
* line 3 (target: 5 syllables)
* session status
* created timestamp
* turn deadline
* expiration timestamp

This is tiny state.

---

## 16. Redis Usage Direction

Redis can serve as the primary transient coordination layer.

### Potential uses

* waiting queue
* active session objects
* per-user ephemeral presence
* session membership lookup
* heartbeat TTL keys
* pub/sub or equivalent cross-node signaling if needed

### Key advantages

* fast reads/writes
* simple TTL expiration
* good fit for ephemeral coordination
* minimal ops burden compared to a more elaborate distributed system
* avoids overbuilding durability the app does not need

---

## 17. Scalability Assumptions

This architecture should scale surprisingly well because the app is so light.

### Reasons

* text-only payloads
* tiny session objects
* no media
* no feed hydration
* no heavy user records
* no complex joins
* bounded session duration
* no history retrieval traffic

A single Go service plus Redis may go quite far before needing serious decomposition.

### Horizontal scaling path

Later, the system can evolve to:

* multiple Go instances behind a load balancer
* shared Redis coordination
* cross-node signaling for websocket delivery as needed

The initial design should avoid unnecessary microservice fragmentation.

---

## 18. Timeouts and Session Cleanup

This system will live or die by cleanup quality.

### Important rules

* waiting users should expire cleanly
* presence should be maintained with heartbeats
* abandoned sessions should dissolve quickly
* completed poems should vanish automatically
* all transient state should have bounded lifetime

### TTL-based cleanup is preferred

Use expiration aggressively for:

* waiting queue entries
* presence keys
* session state
* reveal state
* reconnect grace windows

This keeps zombie state from piling up.

---

## 19. The Waiting Problem

During low-traffic periods, the waiting-for-match state may be the single most common user experience. This is both a technical and an emotional design problem.

### Technical handling

* A waiting user should have a bounded wait time. If no match is found within a reasonable window (e.g., 60–120 seconds), the system should gracefully end the wait rather than leaving the user in limbo indefinitely.
* The timeout should be communicated gently — not as an error, but as a natural conclusion. Something closer to "no one else is here right now" than "request timed out."
* The user should be offered the ability to re-enter the waiting pool without refreshing or restarting the experience.
* Waiting queue depth should be a key operational metric (see Observability). If it is consistently high with low match rates, the system is failing its core promise.

### Emotional handling

* The waiting state should not feel broken. It should feel like being alone in a quiet room where someone else might arrive.
* Consider whether the waiting state can carry some of the app's aesthetic weight — ambient motion, a shift in color or light, a sense of anticipation rather than frustration.
* If the wait ends without a match, the tone should be gentle and should invite return, not apologize.

---

## 20. Reconnect Behavior

Reconnection should be possible only within a short grace window. The experience should be resilient to accidental drops — a brief network hiccup should not destroy a poem in progress — but not so persistent that sessions feel durable or resumable.

If the grace window expires, the session dissolves. The other participant should see a gentle indication that the connection was lost and be returned to a clean state.

The grace window length is a tuning decision, but the value it should be tuned against is clear: long enough to survive a brief accident, short enough that nothing feels like it persists.

---

## 21. Failure Handling Philosophy

The app should tolerate imperfection.

A poem disappearing due to disconnect or backend failure is unfortunate, but not catastrophic. This is not banking software. It is closer to a live, tiny, fragile interaction.

That means the system can intentionally accept some tradeoffs in favor of simplicity.

### Acceptable

* occasional loss of in-flight poems
* sessions that dissolve if someone vanishes
* hard expiration of dead state
* reconnect windows that are short and unforgiving

### Not acceptable

* systemic queue stalls
* server behavior that violates turn order
* state leaks that accumulate endlessly
* resource growth from abandoned sessions
* abuse without any response path

---

## 22. Content Boundaries

The system should reject or interrupt content that is clearly abusive, threatening, sexually explicit in a harassing way, spam-like, or intended to break the interaction.

The goal is not to aggressively sanitize language or police poetry. The goal is to preserve the conditions for brief anonymous collaboration without turning the experience into an abuse vector.

Content moderation should err on the side of allowing creative expression while preventing the experience from becoming hostile. The line is: protect the other participant's willingness to be open with a stranger.

---

## 23. Moderation and Abuse Realities

An anonymous system needs moderation even if it rejects most social machinery.

### The core constraint

In an anonymous, ephemeral system, the **only person who can report abuse is the other participant**, and they have a very short window to do so. The poem is shown briefly, then it disappears — and with it, the evidence. This is a real design constraint that shapes every moderation decision.

### Minimum requirements

* rate limiting on session creation and line submission
* basic anti-spam controls (e.g., reject empty lines, extremely long input, rapid-fire submissions)
* rejection of obviously abusive or malformed content
* a reporting mechanism available during the reveal window (and possibly for a short grace period after dissolution)
* temporary blocking / fingerprint-based throttling where necessary

### Reporting design

* The report action must be available **during the reveal** and possibly for a brief window after the poem dissolves. Once the session is fully expired, reporting is no longer possible.
* A report should capture the poem content and session metadata before it is erased, routing it to a moderation queue that is the **one exception** to the app's ephemerality principle.
* Reported content may need to be retained temporarily for review, even though everything else is deleted. This is a narrow, justified exception — moderation requires evidence.

### Philosophy

Moderation should exist behind the curtain, not as part of an identity-driven social layer. The poem should remain the visible object. Enforcement should remain infrastructural.

---

## 24. Operational Anti-Abuse

Beyond product-level moderation, the backend needs basic defensive infrastructure:

* IP-based rate limits on connection and session creation
* temporary fingerprint throttling for repeat abuse
* per-IP and global websocket connection caps
* message size limits on all submitted content
* turn submission idempotency (prevent duplicate line submissions from retries)
* connection-level abuse detection (e.g., rapid connect/disconnect cycling)

These are unglamorous but necessary. Without them, the system is trivially abusable at the infrastructure level regardless of product-level moderation.

---

## 25. Observability Priorities

Metrics should focus on system health, not engagement theater.

Useful metrics include:

* active websocket connections
* waiting queue depth
* median match wait time
* match failure rate (waits that expire without matching)
* active poem session count
* poem completion rate
* timeout / dissolution rate
* disconnect / reconnect rate
* Redis latency
* per-node memory usage
* message throughput
* moderation rejection count
* report submission rate

These help answer whether the little machine is alive and functioning.

---

## 26. Strong Architectural Warning

Do not accidentally build this like a conventional social/content app.

Avoid defaulting into:

* a users table
* a poems table as durable canonical content
* REST CRUD around saved poem objects
* a profile model
* message history
* relationship graphs
* feed logic

That would distort the nature of the project.

This is better understood as a **lightweight real-time ephemeral coordination system**, closer in spirit to a tiny multiplayer interaction than a standard social platform.

---

## 27. Implementation Bias

Initial implementation should favor:

* one Go codebase
* one deployable service
* modular internal packages
* Redis for transient state
* simple websocket event flow
* bounded session state machines
* minimal infrastructure complexity

Avoid early service sprawl.

Keep it austere.

---

## 28. Suggested Initial Internal Modules

A single backend codebase could contain modules such as:

* `gateway`
* `matchmaker`
* `sessions`
* `presence`
* `moderation`
* `metrics`

These can remain internal packages until scale genuinely requires otherwise.

---

## 29. Open Questions for Future Refinement

This brief intentionally leaves some questions unresolved for later exploration:

* exact per-turn timeout length (likely 60–90 seconds, but worth testing)
* exact reconnect grace window duration
* moderation thresholds and tooling specifics
* language support / matchmaking segmentation
* whether a completed poem is shown for a fixed duration or until dismissal with a hard expiration cap
* specific UI copy for the landing threshold, transition states, and dissolution
* specific ambient/animation direction for the waiting state
* whether a "no match found" state should offer anything beyond re-entry (e.g., a solo writing prompt, a found poem from the ether)

These belong in later refinement documents.

---

## 30. Summary

This is a responsive anonymous web app for making tiny poems with strangers and letting them disappear.

It rejects identity, ownership, history, and social accumulation in favor of brief shared creation.

Technically, it should be built as a lean real-time coordination system: small state, live turn-taking, aggressive expiration, and minimal persistence.

The frontend carries the emotional weight. The backend protects the lightness of the thing.

Nothing is kept unless moderation requires it.

Something happens, and then it is gone.
