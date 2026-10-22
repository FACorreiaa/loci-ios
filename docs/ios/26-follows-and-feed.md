# 26 · Follows and the feed

Friends now work like followers on other social apps. Following is one-way;
two people who follow each other are **friends**, which is what unlocks
friends-only trips. Accounts are public by default; a private account turns
follows into requests. Web: `/friends` (People), `/u/:username`, settings.

## Where it shows

- **People** (`Features/Social/UI/FriendsView.swift`, You hub row
  `YouDestination.friends`, titled People). Chips, not a segmented control
  (five segments truncate on a phone):
  - **Feed**: what the people you follow did (`FeedItemSection`), with cheers.
  - **Trips**: public trips of people you follow, friends-only trips of friends.
  - **Followers**: swipe to remove one.
  - **Following**.
  - **Requests**: approve or decline incoming, cancel sent, and the private
    account switch.
  - Below every tab: contacts, Facebook, invite link, phone number.
  - Search by username; each hit has a follow button.
- **Follow button** (`FollowButton`, replaces `RelationshipButton`):
  Follow / Follow back / Requested / Following / Friends / Unblock. Unfollow
  asks first. Requested taps to withdraw (`Unfollow` also cancels a pending
  request on the server).
- **A profile** (`UserProfileView`): the follow button, "Follows you",
  followers / following / achievements counts (each opens its list when the
  profile is visible), the showcase, trips and top places. A private profile
  the caller may not see (`can_view` false) shows the card, the counts and a
  lock line, nothing else.
- **Settings › Who can follow you** and People › Requests both hold
  `AccountPrivacyToggle`. Going public approves everyone waiting.
- **Notifications** gains **Cheers**; Friends is now **Followers and friends**.

## Model

`FollowState` (`Features/Social/Model/FollowState.swift`) is read by raw
value like `Relationship`; the proto has no SELF, so `FollowEdge` takes the
legacy `relationship` to tell the caller's own profile apart. `FollowEdge`
holds both directions and names the button.

`UserProfileView` reloads the profile whenever the edge changes (a follow may
make it visible). Setting the edge from the response would re-run the task, so
`loadedEdge` remembers what the server last said and the second run returns.

## The feed

`SocialAPI.feed(pageToken:)` pages by cursor; the last row's `onAppear` loads
the next page. Each item is a `Section` so the profile link, the trip link and
the cheer are separate rows: two `NavigationLink`s in one List row both fire.

The feed loads apart from the other tabs: it has its own kill switch on the
server (`FEED_ENABLED`), and its failure must not blank Followers or Trips.

Cheers are optimistic (`FeedItem.cheered(_:)`), then the server's count
replaces the guess; a failure puts the old item back. A light haptic plays on
cheer. The server pushes only the first cheer per item, at most three a day.

## Pushes

Server `push.SocialCategory` (`loci_social`) carries the URL to open:

| Origin | Opens |
|---|---|
| `new_follower`, `followed_back`, `follow_approved` | `/u/<username>` |
| `follow_request` | `/friends?tab=requests` → `AppLink.followRequests` |
| `cheered` | `/achievements` (an achievement) or `/profile` → Your progress (a city or trip) |

## Not yet

- Feed items for an achievement don't open the achievement.
- A cheer on a city or trip opens Your progress, not the item.
