# Product

<!--
Drafted 2026-11-10 by the impeccable-swift polish pass, from loci-client/PRODUCT.md,
the App Store description, docs/ios and the code. Only the three personality
words under "Brand Personality" came from the owner; everything else is
inferred. Correct anything that reads wrong and delete this note.
-->

## Register

product

## Users

Travellers planning or walking a city trip on an iPhone, often outdoors, often
one-handed, often in daylight. Two moments matter: the evening before
(planning, comparing cities, inviting friends) and the day itself (what is
nearby, is it open today, what is the next stop). They are fluent in Apple
Maps, Google Maps, Airbnb and Flighty, and will not tolerate a chat box that
forgets the plan.

## Product Purpose

Loci turns one sentence into a trip that knows what changed today: holiday
closures, weather, real prices. It keeps the plan after the chat is gone,
walks the day with you stop by stop, records the places you actually went,
and lets friends compare. Success is a stranger planning a trip, walking it,
and coming back for the next one.

The iOS app follows the web app (loci-client) screen for screen; where the two
differ, one of them is wrong.

## Brand Personality

Warm and playful, fast and pocketable, editorial and curated (owner's words,
2026-11-10). A well-thumbed field guide with a mascot in the margin: friendly
copy, streaks and achievements that feel like a game with friends; glanceable
on the street and quick to dismiss; photo-led city storytelling for
destinations.

Open question: the web PRODUCT.md says "observant, grounded, useful". The two
are compatible (the facts stay calm; the voice around them is warm), but the
owner should confirm which leads when they pull apart.

## Anti-references

- Purple-on-white or indigo "AI dashboard" chrome, gradient text, glass stacks.
- The default SwiftUI tutorial: white cards with `cornerRadius(10)` and
  `shadow(radius: 4)`, system blue, `.secondary` everywhere.
- Default-blue map clusters and rainbow itinerary pins.
- Emoji as navigation, in quick prompts, badges or map popups. (The server
  still sends emoji for trending cities, featured collections and in-season
  chips; that is known drift, not a pattern to copy.)
- Fake metrics, fabricated ratings, "coming soon" strips without a date.

## Design Principles

1. **The plan outlives the chat.** Every result lands in a durable, editable
   surface; chat is an input, never the only record.
2. **Say why.** Each recommendation carries its rationale, freshness and
   trust signal next to it ("estimated", "Why it fits you"), not hidden.
3. **Earned familiarity.** Standard iOS affordances (tabs, navigation stacks,
   sheets, steppers) in Loci's materials. Surprise is spent on the map and
   the mascot, not on controls.
4. **Readable outdoors, usable one-handed.** Contrast and touch targets are
   measured, not assumed; opacity-faded text is a bug.
5. **One visual language, every screen.** Tokens come from `LociTheme`
   (source: loci-client/docs/NATIVE_DESIGN.md). If a control looks different
   on two screens, one of them is wrong.

## Accessibility & Inclusion

WCAG 2.2 AA as the floor: 4.5:1 for text in both appearances, 3:1 for control
boundaries, 44pt touch targets. Dynamic Type through the accessibility sizes
(rows restack with `AdaptiveStack`, sheets open full height). VoiceOver labels
on every control, headings marked, state never carried by colour alone.
Reduce Motion gets a fade in place of movement and stops the marquee and
mascot. Light and dark are both verified. The app also plans for travellers
with access needs (Settings, access notes on results), so this bar is part of
the product, not a compliance step.
