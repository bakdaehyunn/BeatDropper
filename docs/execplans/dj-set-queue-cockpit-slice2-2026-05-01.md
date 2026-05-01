# DJ Set Queue Cockpit Slice 2 - ExecPlan

## Goal
Make the Auto DJ Queue panel feel spacious and stable without reducing playlist priority.

## Checklist
- [x] Remove the cramped flow strip from the main queue panel.
- [x] Rebuild queue rows as header, Now/Mix/Next cockpit, progress, and transport.
- [x] Constrain long titles and mix chips inside their cards.
- [x] Validate with tests, build, and screenshots.

## Locked Decisions
- Keep Now, AI Mix, and Next at equal visual priority.
- Do not add saved playlists, folder trees, or new analysis data in this slice.
- Keep transport controls in a dedicated footer row.

## Validation
- `npm run test`
- `npm run build`
- Playwright screenshot at 1194x842 empty and loaded states.
- Bounding-box check for cockpit, progress, and transport overlap.
