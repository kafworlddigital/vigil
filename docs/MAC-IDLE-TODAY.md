# Keith Mac build 13 — delivery 7 November 2026

One Release build succeeded and replaced build 11 at `/Applications/Vigil.app`.
The existing Dock pin, development signing and shared Tuck entitlement were preserved.
The old app was backed up and the new app relaunched immediately. Internal dd-today was removed.

Ordinary-background idle process CPU, over separate 30-second windows: 0.098% before → 2.935% after (100% = one core).
The baseline was already low. Mouse activity occurred during the samples; this does not establish reduced CPU during active animation/listening.
Default input is C922; default output is FlyPods Pro, without a forced speaker route.

Prepared validation: 54 portable core and 13 server tests, syntax/isolation and source parity passed on Contabo.
Today: the exact source manifest passed, native Release compilation and signing passed, ordinary process stability and exact Dock pin were independently read back.
The former image/timed acceptance suite and human speech were not rerun today. No physical Macy device acceptance is claimed.
