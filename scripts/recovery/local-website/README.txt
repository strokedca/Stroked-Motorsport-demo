STROKED LOCAL WEBSITE RESTORE - 1.6
Prepared November 22, 2026 for Whisky's existing Surface recovery setup.

RUN ON THE SURFACE

1. Keep Docker Desktop open. Download this ZIP and choose Extract All.
2. Open the extracted folder. Right-click Run-Website-Restore.cmd and choose
   Run as administrator. Keep its window open.
3. Wait for the local recovery page to open in your browser. Click
   Run account checks. It walks two disposable accounts through confirmation
   and the restored website's password-reset form, then returns to the page.
4. Open the restored website from that page. Sign out if needed, then sign in
   with your usual Stroked account and complete its usual authenticator check.
   Open the administration view and an event with a photo. Use the yellow
   banner to return to the recovery page.
5. Click Download report and stop local test. Attach that JSON report in our
   chat. If the script stops earlier, attach the JSON saved beside this file.
   The command window now stays open after the script finishes or stops;
   close it yourself after saving the report. The final safe report is also
   copied to your clipboard when available; return to chat and press Ctrl+V.

The script uses your already verified backup download and existing local
recovery identity. It downloads a pinned HAProxy image for local-only access;
no new recovery keys or PowerShell pastes are needed.
Enter your password and authenticator codes only in the local website.

WHAT THE PACKAGE DOES

- Checks the exact StrokedRecoverySite containers, local Docker connection,
  PostgreSQL 17, empty-database/checkpoint state, and scoped Windows firewall.
- Privately opens and verifies the already checked database/files/source pair.
- Keeps this recovery project's app containers on an internal Docker network,
  and exposes four fixed services through a localhost-only TCP proxy. It
  checks local-only Auth mail routing, and stops app services during import.
- Enables authenticator verification in the still-empty local copy if its
  default disables it, saves a private config backup, restarts only this local
  project, and verifies the effective setting before loading account data.
- Preserves current managed Auth/Storage definitions, service role passwords
  and migration state. Restores core app data, account password hashes,
  identities, MFA factors, bucket/object metadata and archived image bytes.
- Uses a guarded transaction and checks selected table counts and database
  protections. Old login sessions, pending tokens, provider operation tables,
  schedules, outbound webhook triggers and Vault secrets are not replayed.
- If necessary, creates only specifically referenced missing cloud roles as
  NOLOGIN/NOINHERIT. Existing role passwords and memberships are preserved.
- Serves the archived website on http://127.0.0.1:3000 with its API directed to
  the local stack. The exact archived SDK is bundled. External browser network
  requests are restricted by CSP; payments and external navigation are disabled.
- Uses local Mailpit messages for disposable confirmation/reset checks. It
  verifies the reset account can actually sign in with its changed password.
- Records aggregate pass/fail evidence. The report excludes passwords, codes,
  tokens, email addresses, account IDs and private application records.
- Reports exact startup steps and safe error metadata/literal guard messages.
  Existing tools can be found through registered PATH/install directories in
  a fresh elevated window; nothing is downloaded or installed.

FINISHING AND CLEANUP

The finish button stops only the named recovery project's containers. If all
required core-site checks passed, it also removes that clone's containers,
owned volumes, internal network, temporary web files/checkpoint and its exact
temporary firewall rule. It does not delete original encrypted backups.

If checks are incomplete, the clone stays stopped with its scoped firewall
rule and private checkpoint retained for diagnosis/resume. Do not start it
from Docker Desktop independently or remove the firewall rule. Send the JSON
report so the next action is based on the actual result.

The existing backup lock is released before the interactive browser checks;
the scheduled 9 AM backup is a separate job. This package neither changes its
schedule nor proves that the scheduled backup succeeded. An earlier failure
can briefly hold the lock while opening/checking the recovery pair.

SCOPE OF THE RESULT

This is the actual local core-website recovery stage, following the completed
archive checks and earlier 67-table offline database proof. Its Surface run is
still required. A prepared package or a passed component test is not a passed
owner recovery drill.

The archived source is commit 5557ed06e17d55286cf67397544051cb30e37f39, which
predates the latest live fixes. Local API, payment and recovery-observer edits
are deliberate test changes; nothing is deployed back to the live site.

MFA rows are preserved without a reset or bypass. Encrypted factor secrets can
require the original Auth encryption configuration; actual local Auth
verification must pass before the report calls this core recovery verified.
If it does not, attach the report rather than changing your live MFA settings.

This stage does not prove live email delivery/inbox placement, payment
processing, recovery of provider accounts, Vault-dependent background jobs,
every network path, or the scheduled backup. Family Calendar is outside scope.
An internal Docker network still permits communication with host services;
it is not a comprehensive outbound-isolation test.

VALIDATION BEFORE DELIVERY

- PowerShell files parsed with PowerShell 7.4.6; the C# loopback server compiled.
- A real PostgreSQL 17.12 fixture and pg_dump exercised the import planner,
  generated-column handling, managed-default/password preservation, a missing
  role, RLS, selected data exclusions and rollback on a deliberate COPY error.
- The actual archived reset form and pinned SDK submitted the disposable reset
  password in a DOM test with simulated local HTTP responses.
- HTTP/controller tests covered CSP hashes, origin/nonce checks, traversal
  refusal, report privacy, incomplete-result handling and the finish response.
- Browser-observer tests checked aggregate evidence without password/token/OTP
  recording. Cleanup guards were exercised with synthetic container fixtures.
- Local TOTP config-edit tests covered scoped changes, idempotence, missing
  sections/keys and refusal of duplicate/nonliteral settings. Local API-key
  selection tests covered safe resume and rejection of a privileged browser key.
- Version 1.1 startup tests covered a deliberately missing tool, precise safe
  reports, lock release, existing-installation fallback, exclusion of private
  error text and no native/container action after a preflight failure.
- Version 1.2 reproduced the reported line12 failure using a process API model
  without the unsupported StandardInputEncoding member. The corrected runner
  passed real child-process tests through that model for omitted/empty/UTF-8
  input, local Docker pinning, remote-context removal, safe errors and timeout.
  A real PostgreSQL 17.12 transaction also accepted UTF-8 SQL through the runner,
  and a deliberate SQL failure preserved its safe SQLSTATE. These are targeted
  compatibility tests on Linux; the actual Surface recovery is still pending.

Version 1.2 uses Windows PowerShell 5.1-compatible stream APIs and redirects
stdin only when the caller supplied it. Technical API references:
https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.processstartinfo.standardinputencoding
https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.process.standardinput?view=netframework-4.8

Actual owner Docker Desktop networking/services, encrypted owner archives,
and real browser/Auth integration remain to be tested by the Surface run. Earlier preparation was already
successfully owner-run; it does not need to be repeated.

Bundled Supabase JS: version 2.95.3, original integrity-matching bytes.
License: vendor/LICENSE.supabase-js.txt.

VERSION 1.3 DATA-EXPORT COMPATIBILITY

The owner v1.2 run reached archive planning, then stopped on an unsupported
non-COPY statement before importing data. The official CLI3.2.0 data-dump
script requests quoted identifiers and appends RESET ALL. The old parser
reproduces the exact reported error on either the quoted setval form or
that trailer. Version1.3 accepts balanced quoted/unquoted sequence names,
preserves only application sequence resets, and removes only the exact
RESET ALL trailer because the enclosing import owns its session settings.
Unrecognized statements and psql commands still stop the import. A further
parser stop reports only a line number and fixed statement category, never
raw SQL or account data. Existing manifest counts/import checks are retained.

Technical source:
https://github.com/supabase/cli/blob/v3.2.0/apps/cli/src/command-internal/pg-dump.scripts.ts

The real Surface v1.3 import and browser/Auth checks remain pending.

Version1.3 validation passed with official temporary PowerShell7.4.6 and a
real PostgreSQL17.12 server on Linux. The official CLI3.2.0 dumpDataScript
produced the fixture export, including quoted sequences and RESET ALL.
The selected import round-tripped seven core/application tables, preserved
UTF8/password/MFA fixture values, reset application sequences correctly,
kept managed sequence state local, removed pending tokens and excluded
sessions/Vault data. Manifest mismatches, malformed quoted names, appended
SQL and psql meta commands were rejected. COPY rows containing SQL-like text
were preserved as data. This remains component evidence, not a completed
Surface website/browser/Auth recovery test.

VERSION 1.4 DOCKER INSPECTION COMPATIBILITY

The owner's network-only report identified the precise Windows PowerShell 5.1
array-shape error: all twelve inspected containers were treated as one array.
Their names were joined and array members (Count, Length and others) were
mistaken for network names. This also affected singleton network inspections
and the container-stop cleanup. It was a defect in the restore helper.

The decoder now preserves the inspected JSON array inside an object and
explicitly enumerates its members. Empty, single and multiple inspections
produce the same scalar objects on Windows PowerShell 5.1 and newer versions.
A scoped container count check detects incomplete inspections. The existing
project identities, firewall, checkpoint, import and isolation guards remain.
Native failures report only an allowlisted operation name and numeric exit;
private arguments, raw output and environment values are never reported.

Independent regression workflow: actual Windows PowerShell 5.1 reproduces
the original array failure and exercises corrected scoped network/stop calls
with twelve synthetic containers. A separate real Linux Docker test exercises
twelve disposable containers, aliases, internal-network changes, stops and
resume. No owner data, backups or hosted credentials are used in those tests.
These tests do not replace the Surface website/Auth/browser recovery drill.

Extract this version into a fresh folder. With Docker Desktop open, run the
extracted Run-Website-Restore.cmd as administrator. Startup must show v1.4.
The existing private checkpoint is resumed; no new backup is required.

VERSION 1.6 SAFE LOCAL PROTECTION DIAGNOSTICS

The restored database-protection verifier now tags each of its eight possible
assertion failures with a fixed DBP01–DBP08 identifier. Only that allowlisted
identifier may appear in the recovery JSON report; SQL output, account data,
and private logs remain withheld. A resumed run uses the committed local import
and rechecks it; it does not replay the import. The report identifies the failed
protection check so the next repair is based on evidence.

VERSION 1.5 INTERNAL-NETWORK PORT ACCESS AND INTERRUPTED RESTART

Docker does not publish host ports for internal-only containers. Version1.4
correctly isolated the app services, but then expected direct published ports
for the CLI readiness checks and browser. That was a design error in the test.
Version1.5 uses a dedicated, digest-pinned HAProxy container. Only that proxy
joins a normal bridge; the app services remain on the internal bridge. Four
fixed TCP forwards publish only127.0.0.1 ports54321/54322/54323/54324 for API,
database, Studio and local Mailpit. No dynamic destination or internet proxy
is configured. The proxy runs nonroot/read-only, drops all capabilities, uses
no-new-privileges, and mounts only its fixed configuration read-only.

The existing Windows firewall is retained. Proxy identity, exact image digest,
command, labels, mounts, networks and loopback bindings are checked. The proxy
gets no Docker socket, owner archives, account records or application secrets.
It is stopped when the test stops and removed with a successfully completed
clone. Incomplete recovery retains the stopped proxy/config and checkpoint.
The normal proxy bridge itself permits outbound routing for the proxy process;
this is not a claim of total network isolation of the entire Docker engine.

An interrupted, explicitly recorded pre-import CLI restart may recreate the
local service containers. The existing labeled local database volume must
match; no original archive/volume is deleted. A replacement database ID is
accepted only after complete metadata proves PostgreSQL17, zero users, zero
app tables, no outgoing/scheduler extension and no restore marker. Imported
or unexpected nonempty copies are refused. Unneeded analytics, Vector, Edge
Functions, pooler and imgproxy are excluded from this local core-site restart.
MFA verification remains enabled; it is not bypassed.

The independent real-Docker fixture reproduced the unreachable published
port without the proxy, then passed actual SupabaseCLI3.2.0 cold startup,
PostgreSQL readiness, Auth TOTP verification enabled and Auth/Mail HTTP access
through the proxy. Additional final CI checks exercise the shipped guarded
volume-preserving restart, container replacement and WindowsPowerShell5.1
checkpoint guards. This is component evidence; the Surface import/browser
recovery is still required. The owner-specific original CLI error was not
retained byv1.4, so its exact text cannot be retrospectively established.

Technical reference: Docker maintainer explanation and supported proxy pattern
https://github.com/moby/moby/discussions/53256

Extract into a fresh folder; startup must showv1.6. The package can resume the
interrupted pre-import startup. Safe reports now identify the CLI stop/start
step and fixed error categories/service names. CLI output remains in private
local files for diagnosis; it is never copied into the report or clipboard.
