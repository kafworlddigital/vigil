# Natural speech and Mac checks

Automatic voice selection ranks installed English voices by Premium, Enhanced,
then quality of the fallback. Eloquence, novelty and super-compact voices are
excluded. Invalid saved choices migrate to Automatic. Preview is next to Voice.
The installed app's voice catalogue is authoritative; a voice listed by another
unsandboxed process may not be available inside Vigil.

When no Enhanced/Premium voice is available, authenticated `/speech` on the
existing vigil-brain renders Piper Alan neural speech. It runs on Keith's
Contabo server, without a paid service or additional model provider. Both client
and server keep at most 64 audio cache entries, using content hashes for names.
Cache contents are private, because spoken reminders may contain personal text.
The sentence is sent only to the existing brain; recognition stays on-device.
Network failure uses a natural installed Apple voice. Zero app volume is silent.

Server dependencies are pinned in server/requirements.txt. The worker loads
en_GB-alan-medium.onnx and its matching JSON from
/srv/projects/vigil-private/piper. Install that model using the official
`python -m piper.download_voices en_GB-alan-medium` command. The worker limits
ONNX to one thread. The brain permits one synthesis at a time, bounded to 12
seconds, and the app's network deadline is 14 seconds. No raw text is logged.
Piper is maintained at https://github.com/OHF-Voice/piper1-gpl; voice metadata
and licensing are supplied by the upstream model card.

Settings has a dedicated, resizable Mac window. Access is available from the
eye menu, the face context menu, the dashboard gear and Command-comma. Try
everything appears near the top. Reminder, meeting and break buttons are
explicit previews and do not alter saved reminders, calendars or switches.
The pointer test gives three seconds to position the mouse. Camera and tired
tests remain explicit requests, with a visible recording indicator.

Mac permissions are read without prompting. A single Allow card names missing
Microphone, Speech Recognition, Accessibility and Screen Recording access;
only its button requests or opens the next missing permission. Work/privacy
guards remain in force before screen access and before sending. On this Mac,
all four permissions were already authorised during the 6 November QA.

The bounded `--vigil-polish-check FOLDER` mode exercises the real installed
speech paths, visual nudges, synthetic speaker wake, current pointer pipeline,
camera stop/cleanup, covered-frame handling and Tuck-backed connection checks.
It preserves settings after checking and uses synthetic screen/task text.
Native content-view bitmaps can have transparent backgrounds. Inspect them on
white before deciding that black text is missing. All eleven introduction
cards were inspected this way and fit; the original captures are preserved.
Actual native Settings screenshots separately confirmed the visible layout,
natural-only voice choices, Automatic selection and face context menu.

6 November acceptance: 49 portable tests and 13 server tests passed on Contabo.
Actual authenticated HTTPS neural audio and repeat-cache reuse passed. Injected
429/auth failures for two free providers reached a real third-provider answer;
production health was not changed by that isolated test. The first local Mac
Release was build 11. One permitted runtime-fix retry, build 12, compiled but
crashed in installed QA and was rejected. Stable signed build 11 was restored;
no third local build was performed. Live C922 wake acceptance is recorded
separately in the private delivery receipt, rather than inferred from an engine
starting or a parser test passing.

The final controlled Mac check subsequently passed the live speaker-to-C922
wake and command, real pointer Accessibility text, a free NVIDIA answer,
observed spoken playback, the answer bubble and the sparkle delivery event.
The speaker test used numeric CoreAudio output selection with `say`; passing
a display name to `say -a` was not a valid successful acoustic test here.
Requested-camera inference and the local tired-frame check also passed in that
final run. Earlier failures remain in the private delivery record. This is a
synthetic acoustic test, not Keith's own voice acceptance. The screenshot-crop
fallback and a physical sleep/wake cycle were not independently exercised in
the final run. Calendar/break timing has portable tests and native previews;
calendar events and the Mac's sleep state were not changed for QA.
