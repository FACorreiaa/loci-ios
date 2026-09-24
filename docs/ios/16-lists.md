# Slice 16: Lists (parity pass 2, Phase 2)

Web's `/lists` on iOS, plus the two pieces web never shipped: a list's own
page (web's `/lists/:id` 404s) and "Add to list" on a place (web's
`AddToListButton` is dead code). Profile › You › Lists, the Saved › Lists
segment and the `loci://lists/<id>` app link all lead here; the Phase 0
placeholders are gone.

**Read "Server gaps" first.** The iOS side follows the contract, but on the
server as of `30da4de` most of the list flow cannot work end to end yet.

## Screens → RPCs

| Screen | RPC | Fields sent | Web source |
|---|---|---|---|
| Lists (Profile, Saved segment) | `ListService.GetLists` | `userId`, `limit 100`, `offset 0` | `lib/api/lists.ts` `useLists` |
| New list / Edit list sheet | `CreateList` / `UpdateList` | create: `name`, `description` (both trimmed), `cityId` only when it is a real UUID, `isItinerary`, `isPublic`; update: `listId`, `name`, `description`, `isPublic` | `useCreateListMutation`, `useUpdateListMutation` |
| Swipe › Delete (confirmed) | `DeleteList` | `listId` | `useDeleteListMutation` |
| List page | `GetList`, then `PoiService.GetPOI` per row | `listId`, `includeDetailedItems true`; `poiId` = the row's `poi_id`, else its `item_id` | `useList` |
| List page › swipe Remove | `RemoveListItem` | `listId`, `itemId`, `contentType` | `useRemoveFromListMutation` |
| Place detail › Add to list | `GetLists`, `AddListItem` (and `CreateList` for "New list") | `itemId` = the stop's POI id, `contentType` from the domain (hotels → HOTEL, restaurants → RESTAURANT, else POI), `position 0`, `notes ""`, `itemAiDescription` = the blurb (≤ 4000), `recommendationTrace` when the stop has one; new list: `description "List created for {name}"`, the stop's `cityId` | `AddToListButton.tsx` |

- `userId` is `AuthSessionManager.currentUserID` (`"me"` fallback). The
  handler reads the caller from the token (`userFromCtx`); the field is only
  there because validation wants it non-empty.
- Every call goes through `ListsAPI.listRPC`, which reads the entitlement
  header before the Connect error becomes an `APIError` (that loses headers),
  and turns a 501 into "… This isn't available on the server yet."
- "Add to list" only shows for a place with a stored POI id: the handler
  parses `item_id` as a UUID, so a name-keyed place cannot go in a list.
- The Itinerary toggle is locked on edit: `UpdateListRequest` has no
  `is_itinerary` field (web drops it silently). An empty description on
  update means "unchanged" to the handler, so it cannot be cleared.
- Analytics: `poi_saved {surface: "list", content_type}` on a successful add
  (web's name), and `Analytics.screen("lists" | "list_detail" | "add_to_list")`.
  Web also records a `RECOMMENDATION_EVENT_TYPE_ADDED_TO_LIST` event; iOS has
  no recommendation-events client yet, so that is not sent (the trace still
  rides on `AddListItem`, which is what stops the server double-counting the
  preference signal).

## Free-plan limit (`EntitlementLimit`)

Port of web's `classifyEntitlementError`: only `PermissionDenied` counts; the
`x-loci-entitlement` header (`lists` | `places`, any case) wins, then the
message ("lists limit" / "list limit", "places limit" / "place limit"), then
web's catch-all (`free plan|upgrade|entitlement|limit reached` → places). It
opens `EntitlementSheet`: web's first sentence ("Free plans include 5 lists." /
"Free plans include 50 saved places.") plus how to make room. There is no
price, no pricing link and no "Upgrade" wording (App Store 3.1.1). A refused
create keeps the sheet open with what was typed.

## Server gaps (found reading `internal/domain/list` at `30da4de`, one probed live)

| # | Gap | Effect on iOS | Fix |
|---|---|---|---|
| 1 | `CreateListRequest.city_id` and `.description` have `min_len: 1` with no ignore rule. **Probed on api.lociai.fyi**: an empty `cityId` is `invalid_argument` before auth. | Creating a list without a city fails, from iOS and from web. "New list" from Add to list passes the stop's city id and gets past validation when the stop has one. | proto: `IGNORE_IF_ZERO_VALUE` on both (and on `List.city_id`/`description`) |
| 2 | Even past validation, `CreateTopLevelList` stores `uuid.Nil` as `city_id` (a non-pointer `uuid.UUID`), which is a foreign key to `cities`. | A list with no city would fail on insert (not probed: needs a signed-in write). | store NULL when there is no city |
| 3 | `GetLists` calls `GetUserLists(ctx, user, false)`: `WHERE is_itinerary = false`. | Lists made with "This is an itinerary" never come back; the Itineraries tab is always empty. | query both kinds |
| 4 | `GetListDetails` loads items only `if list.IsItinerary`. With 3, no list the user can open ever has items. `include_detailed_items` is ignored and `ListItemWithContent` carries only the row. | The list page is always empty. iOS already fills rows from `GetPOI` for when items do come back. | load items for every list; fill `poi`/`restaurant`/`hotel` |
| 5 | `RemoveListItem` is not implemented (falls to `UnimplementedListServiceHandler`, 501). The service method exists. | Swipe › Remove shows "… isn't available on the server yet." and the row comes back. | wire the handler to `RemoveListItem` |
| 6 | `toProtoListItem` never sets `content_type`; `toProtoList` never sets `item_count`. | Rows are shown as generic places; list rows show no count (iOS hides a 0). | set both |
| 7 | `UpdateListRequest` has no `is_itinerary`. | Kind is locked on edit. | proto field + handler |
| 8 | Owner/visibility failures return plain `fmt.Errorf` ("access denied to list", "user does not own list"), which map to `Internal`. | A list you cannot see reads as a server error. | wrap `ErrForbidden` / `ErrNotFound` |

1 and 3 to 5 mean the whole flow (create, see it, add, open, remove) cannot
pass on production today. Web is affected by 1 to 3 as well.

## Tests and previews

`lociTests/ListPayloadTests.swift`: the request builders, the entitlement parser,
the tab filter and counts, and the stores (a refused create opens the limit
and keeps the sheet; create goes first; delete; create-then-add). Previews
(Debug, offline through `PreviewListsService`): `-designPreview lists`,
`listDetail`, `addToList`.

## Not verified

Nothing has run signed in against the live API, and given the gaps above
most of it cannot until the server is fixed: create, add from place detail,
the list page with real rows (and the `GetPOI` fill), remove, delete, and the
6th-list Pro sheet on a free account (the plan's live check). The
entitlement header path is tested only against hand-built headers.
