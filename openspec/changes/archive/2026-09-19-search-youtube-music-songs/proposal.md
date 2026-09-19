## Why

The current fallback searches all YouTube videos, so official song results compete with music videos and unrelated uploads. Restricting discovery to songs alone would improve the common case but hide unofficial remixes and video-only releases, so the owner needs an explicit choice with music-first defaults.

## What Changes

- Add two mutually exclusive external-discovery modes beside the search field: `Music` and `All`, with `Music` selected by default when the client starts.
- Keep normal Arion catalog search unchanged. The selected mode applies only when the owner explicitly starts external discovery after an empty local search; changing the mode never contacts an external provider automatically.
- Make `Music` discovery query the YouTube Music Songs category and return only song results with useful song title, artist, duration when available, thumbnail, and canonical YouTube identity.
- Keep `All` discovery as the existing broad YouTube video search so unofficial remixes and releases that are not classified as songs remain discoverable.
- Do not silently fall back from `Music` to `All`; show an empty/error result and let the owner change modes deliberately.
- Preserve the existing approval, authorization acknowledgement, bounded revalidation, download, import, provenance, and playback workflow for both modes.
- Keep the broader visual redesign and playback repeat modes outside this change so they can be designed and verified independently.

This change is stacked on `import-missing-tracks-from-youtube`; that prerequisite must be integrated before this change is archived or merged independently.

## Capabilities

### New Capabilities

- `youtube-acquisition-search-modes`: Explicit music-only and broad-video discovery modes, their default behavior, provider routing, and stable result semantics.

### Modified Capabilities

- `flutter-client`: Add a music-first external-discovery mode selector without changing local catalog search or triggering automatic external requests.

## Impact

- Backend candidate-discovery request/response contracts and provider routing.
- A pinned unauthenticated YouTube Music search dependency, while pinned `yt-dlp` remains responsible for selected-video revalidation and acquisition.
- Candidate-token contents, sanitized provider errors/logging, dependency smoke checks, and provider tests.
- Flutter library controller state, search controls, candidate labels, API serialization, and widget tests.
- Documentation and isolated private deployment verification for both discovery modes.
