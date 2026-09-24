# Slice 19: Reviews (parity pass 2, Phase 5)

Reviews on iOS are tied to places. They live on a place's detail and on
Profile › My reviews, not on a separate feed. Web's `/reviews` is mostly a
mock (fake "Places to review", hard-coded counts, a local append when the
write fails), so it was not ported. This slice follows the contract that api
`30da4de` / proto v5.27.0 actually serve.

## Screens → RPCs

| Screen | RPC | Fields sent |
|---|---|---|
| Place detail › Reviews (summary) | `ReviewService.GetReviewStatistics` | `poiId` |
| Place detail › Reviews (latest 3), See all | `GetPOIReviews` | `poiId`, `pagination{page ≥ 1, pageSize 20}` |
| "Write a review" vs "Edit your review" | `GetUserReviews` | `pagination{page, pageSize 100}`, **no `userId`** (empty means the caller). Filtered by `poi_id` on the client |
| Write sheet › Post | `CreateReview` | `poiId`, `rating` (whole 1–5 as a double), `title`, `content` (both trimmed), `visitDate` only when set |
| Write sheet › Save (edit) | `UpdateReview` | `reviewId`, `rating`, `title`, `content`, `visitDate` (none clears it: the handler overwrites every field) |
| Delete (card menu, sheet, My reviews swipe) | `DeleteReview` | `reviewId` |
| Helpful | `LikeReview` | `reviewId`, `isLike` = the new state (false takes your vote back; web always sends true) |
| My reviews | `GetUserReviews` | `pagination{page, pageSize 20}`, no `userId` |
| My reviews › tap | `PoiService.GetPOI` | `poiId` (the saved-place pattern: the review's name shows first, then the stored place fills in) |

- `userId` is never sent. Every review request has an optional `user_id`, and
  the handler reads the caller from the token.
- Photos, aspects, language and `content_*` are not sent. There is no upload
  RPC, and the server ignores the rest.
- `ReportReview` is Unimplemented on the server, so there is no report
  button. `GetContentReviews` and `GetRecentReviews` are not used.
- A 501 becomes "… This isn't available on the server yet." (`reviewRPC`,
  the same approach as `ListsAPI`).

## Rules (`Features/Reviews/Model`)

- **Who can review:** `ReviewPayload.canReview` is Add to list's rule
  (`ListPayload.realUUID(stop.id)`). A name-keyed place gets no Reviews
  section at all, because the handler parses `poi_id` as a UUID.
- **Form** (`ReviewForm`):
  - The rating is required, and its labels are web's: Terrible, Poor, Average, Good, Excellent.
  - The title is optional, up to 100 characters.
  - The content must be 10–1000 characters after trimming (web checks only the minimum).
  - The fields clamp what is typed or pasted. Post stays disabled until the form is valid, and the counters read `n/100` and `n/1000`.
- **Visit date:** a calendar day, not an instant. The local day picked is
  sent as 12:00 UTC and shown as "Visited March 2026" in UTC, so it never
  moves a day in another time zone.
- **Card:**
  - The text folds at 200 characters with "…" and a "Read more" link (web's `truncateContent`).
  - The rating badge uses web's colour bands: ≥ 4 forest, ≥ 3 coral, otherwise the destructive red.
  - Your own review shows "Your review" and an Edit/Delete menu, never a helpful button.
- **Second review:** a second review of the same place comes back as
  `AlreadyExists` (`APIError.conflict`). The sheet keeps what was typed,
  loads your existing review, switches to editing it, and says so. Saving
  then updates that review.
- **Helpful vote** (`HelpfulVote`):
  - It flips at once, and `new_helpful_count` from the server settles the count.
  - A failure puts the previous state back and shows an alert. A second tap while a vote is in flight is ignored.
- **Summary** (`ReviewStats`):
  - The bars are shares of the breakdown's own sum.
  - After your own create, edit or delete, the count, average and bars update locally without a refetch.

## State

- **`PlaceReviewsStore`:**
  - The place section and "See all" (`PlaceReviewsListView`) share one store, so votes and your edits agree on both screens.
  - Each screen owns its own composer and delete state.
  - Only the screen on top presents the error alert. While the sheet is open, the sheet shows the error itself.
- **`MyReviewsStore`:**
  - Paging, and an optimistic delete that is rolled back on failure.
  - Edit goes through the same `ReviewComposer`.
  - The summary line (count, average given, helpful votes) is computed from the loaded rows, because the server leaves `UserReviewStatistics` empty.
- Both stores take a `ReviewsService`:
  - `ConnectReviewsService` is the live one.
  - `PreviewReviewsService` supplies offline samples, and is used by any place detail shown under `-designPreview`.

## Analytics

- `review_submitted {rating, is_edit}` on every successful post or edit.
  Web sends `{rating, has_photos, travel_type}` from its mock page. iOS has
  neither field.
- Screens: `place_reviews` ("See all"), `review_composer {is_edit}`,
  `my_reviews`.

## Server gaps (read at `30da4de`, not probed live)

| # | Gap | Effect on iOS | Fix |
|---|---|---|---|
| 1 | `Review` has no "voted by me" field, and there is no RPC to read your votes. | A review always starts unvoted. If you voted in an earlier session, your first tap sends `is_like=true` again (an upsert, so the count doesn't move) and shows it as liked. You need a second tap to take the vote back. | `bool liked_by_me` on `Review`, filled for the caller |
| 2 | There is no "my review of this POI" RPC. | "Edit your review" pages through `GetUserReviews` 100 at a time, up to 5 pages, and filters on the client. | `GetReview` by `(caller, poi_id)`, or `mine` on `GetPOIReviews` |
| 3 | `LikeReview` accepts a vote on your own review. | iOS hides the button, but web does not. | refuse the review's owner |
| 4 | `GetUserReviews.statistics` is never filled. | My reviews works out its summary from the loaded rows. | fill it, or drop it from the proto |
| 5 | `ReportReview` is Unimplemented. | There is no report UI. | a table and a handler, or remove the RPC |
| 6 | Reads need a JWT. | Nothing on iOS, which is always signed in. | none needed for iOS |

## Tests and previews

`lociTests/ReviewModelTests.swift` has three suites:

- **`ReviewModelTests`:** labels, tone thresholds, rating clamp, form rules and limits, the 200-character fold, helpful toggles and settling, summary maths (share, add, edit, remove), and the proto and page mapping.
- **`ReviewPayloadTests`:** the stored-POI rule, each request builder (trimmed, whole stars, no `user_id`, no photos), refusals, visit day at noon UTC across time zones, update clearing fields, like direction, and paging bounds.
- **`PlaceReviewsStoreTests`:** load, finding your own review, vote settle and rollback, no vote on your own, a post updating the summary, AlreadyExists switching to edit, and delete taking its star away.

Previews (Debug, offline):

- `-designPreview placeReviews`
- `reviewComposer` (editing your own review, over the section)
- `myReviews`

## Not verified

- Nothing has run signed in against the live API. Still untested there: write, edit, AlreadyExists → edit, like and unlike, delete, My reviews, tap through to the place, and the plan's live check.
- "See all" paging beyond the first page, pull to refresh, and the swipe actions have run only against preview data.
- Dynamic Type XL was not checked.
