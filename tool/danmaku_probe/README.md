# Native interactive danmaku probe

An isolated Windows Flutter test page that accepts BV IDs or full Bilibili
video links (including ?p= for a specific part). Enter up to four videos, one
per line. It discovers every vote and rating card in the selected parts, without
hardcoded card IDs. The new default BV11d6rB4Evy has both types; a shortcut also
loads the previous participated examples. It follows the root .fvmrc, Windows SDK/material_ui patches, and
the exact media_kit fork revisions recorded in the root pubspec.lock. The
generated platform project and build outputs live under .fvm/danmaku_probe.
The probe has its own entry point. The experimental production integration is
documented in `docs/experimental-interactive-danmaku.md` at the repository root.

Run `pwsh -File tool/danmaku_probe/build.ps1 -Launch -AccountFile <account-json>`
after provisioning the pinned SDK and portable CMake as in the Windows build
script. Credentials are read from that file at runtime, held only in memory,
and sent only to api.bilibili.com; they are not bundled or logged.

The page loads actual card metadata and participation state. It never submits
automatically. Real submission requires clicking the button with an account
that has not participated. The saved fixtures represent the state before the
user's submissions; live participation is always read from the server.
Selection alone pauses the real video and reveals an accent-colored submit
button inside the card. Changing the choice does not submit. Only the explicit
submit button sends a vote or rating. It disappears once participation is
acknowledged by the submission API, even while participation readback is pending.
A later stale refresh cannot re-enable that submission in the same session.
The server participation state is queried
again before and after submission. It never automatically retries a submission.
The server's total votes, per-option counts, rating count, and average score
are displayed and refreshed with participation state. The average uses a
ten-point scale; the user's own rating appears to the right of the stars.

The page decodes real Bilibili MP4 streams with the project's native player.
Card visibility follows the player's position stream; seek buttons change the
actual video position. There is no simulated clock. This standalone page does
not validate the production player's fullscreen or part switching.

Both cards have a close button. Closing hides that card for the current video
session, including after seeking or refreshing statistics. Reloading videos
starts a new session. Existing participation is read from the API on load and
refresh: the chosen vote or star rating remains highlighted and cannot be
submitted again. Cards display results without server-status labels.
Selection uses highlights and filled stars without extra "already selected"
status text. Participation is read for any entered video, not just the bundled
examples, provided the API still returns its command card.
Cards also omit selection instructions. Their surfaces, text, selected options,
and submit buttons inherit the application's active ColorScheme. Cards have no
separate theme setting. The isolated test host keeps its existing dark theme;
component checks also verify a light host and theme changes preserve selection.
The user's ten-point rating is shown to the right of the stars, including
ratings read from existing participation. It is absent before selection.
