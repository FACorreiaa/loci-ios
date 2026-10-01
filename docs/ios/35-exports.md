# 35 — PDF exports for results pages and lists (pass 3, Phase 4)

Web exports hotels, restaurants, activities, places and lists to PDF through
ExportService (`lib/api/export.ts`); iOS only had the itinerary PDF in Trip
Kit. Now every results page and every list has "PDF" next to Share.

## RPCs

`ExportService.ExportHotelsToPDF / ExportRestaurantsToPDF /
ExportActivitiesToPDF / ExportPOIsToPDF / ExportListToPDF` →
`ExportPDFResponse{pdf_data, filename}`. All validated and live in prod
(400 on an empty selection). The itinerary PDF stays `ResultsAPI.pdf`
(Trip Kit), with `TripExportGate` deciding the day gate.

## Pieces

- `Core/Export/PDFExport.swift` — request builders per surface. Web maps only
  its SelectionItem fields; iOS sends the full place: POI copy over generic
  copy, price range or level, phone, website, opening hours as one sorted
  line, star rating parsed from "4 stars", amenities split on commas. Lists
  bucket entries by content type (itinerary stops count as places).
  `file(from:fallback:)` writes a temporary file for `ShareLink`, keeps the
  server's file name without any path, and refuses an empty PDF.
  `fallbackName` → `loci-<city-slug>-<surface>.pdf`.
- `Core/Export/ExportAPI.swift` — `results(destination…)` and `list(detail)`.
- `Features/Search/UI/Results/ResultsExportButton.swift` — "PDF" → "Building
  PDF…" → "Share PDF" in the results share row (not on the itinerary page);
  `ListExportButton` in the list detail toolbar.
- Analytics: `trip_exported{format: pdf, surface, count}` as web.

## Not done

No preview case: the button is three words in an existing row. No per-day
gate on these pages — they are free on web too.
