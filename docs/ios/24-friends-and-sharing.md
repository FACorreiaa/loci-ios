# 24 · Friends and trip sharing

Mutual friends (one side asks, the other accepts), trips shared at four
levels, and a read-only view of someone else's trip that can be saved as
your own. Web: `/friends`, `/t/:code`, `/u/:username`, `/invite/:code` and
the share panel on `/trips/:id`.

## Where it shows

- **Friends** (`Features/Social/UI/FriendsView.swift`), first row of the You
  hub (`YouDestination.friends`). Three segments:
  - Trips: what friends shared with friends or publicly.
  - Friends.
  - Requests: accept or decline incoming, cancel sent.

  Also on this screen:
  - a username search (`.searchable`);
  - **From your contacts**;
  - the invite QR code and link (`InviteSheet`).
- **A trip's Share menu** (`TripShareMenu`, in `TripEditorView`'s toolbar) has
  four levels: Only me, Friends, Anyone with the link, Public. It shows the
  link once the trip has one. It replaces the old one-tap `ShareTrip`.
- **Someone's trip** (`SharedTripView`): the hero, who made it and the days,
  read-only. **Save to my trips** calls `CopyTrip` and opens the private
  copy. It is opened by a share code (`/t/:code`) or by id
  (`/friends/trips/:id`).
- **A profile** (`UserProfileView`): stats (cities, countries, trips shared,
  friends), the relationship button, block, and the trips the viewer may see.
- **An invite** (`InviteView`): one tap to become friends.

## Contacts

`ContactMatchView` reads the address book (with iOS 18 limited access the
person picks which contacts; **Choose more contacts** opens
`contactAccessPicker`). Only hashes are sent:

- `ContactHasher` turns each phone number into E.164, using the device
  region for national numbers.
- It trims and lower-cases each email.
- It then hashes both with SHA-256 as lower-case hex.

This is the same form the server indexes (`loci_sha256_hex`), which matches
verified identifiers only. Nothing is stored for contacts who are not on
Loci. `NSContactsUsageDescription` says the same in Info.plist.

## Links and pushes

- `AppLink` gains `.sharedTrip`, `.invite`, `.user`, `.friends` and
  `.friendTrip`. All of them open on the Profile tab.
- The web AASA lists `/t/*`, `/invite/*`, `/u/*` and `/friends*`.
- Friend pushes (request, accepted) carry no session, only `url`.
  `PushRoute.tap` falls back to `AppLink(url:)` and returns `.openLink`.
- The **Friends** toggle in Settings → Notifications (`friend_activity`) gates
  these pushes.

## Data

- `SocialAPI` wraps SocialService and TripService's sharing RPCs:
  - SetTripVisibility, GetSharedTrip, GetFriendTrip;
  - ListFriendTrips, ListUserTrips, CopyTrip.
- Relationship and visibility are read by raw value (`Relationship`,
  `TripVisibility`), so the app does not depend on how the generator spells
  `NONE` or the Swift keywords `private` and `public`.

## Tests

- `lociTests/SocialModelTests.swift`: relationship and visibility mapping,
  initials, E.164 normalisation, and the hash format.
- `AppLinkTests`: the new routes and their tab.
- `ChatPushTests`: a friend push opens its page.
