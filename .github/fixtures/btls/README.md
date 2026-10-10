# 11.3.0 BTLS investigation (not a release)

This branch forks the former v3 integration test branch (2b19a5da). It does
not contain the CCW lifetime patch. The original investigation workflow does
not rebuild managed assemblies; the separate fix workflow below does.

The CI matrix builds the original 11.3.0 engine (73610cc7350) and the v3
engine with PR #35 (04226a35017), each with BTLS enabled, for x86 and x64.
Every job also runs the official, prebuilt 11.3.0 engine as a control.
System.dll, mscorlib.dll, the official native BTLS DLL and fixtures stay the
same when engines are exchanged. Exact checksums and source revisions are
saved with the results. The v3 source also contains RegistrationServices
changes, but their managed assemblies are not installed by these tests.

Certificate fixtures are passed as base64 memory data, not loaded by managed
File.ReadAllBytes. The first CI run showed the original x86 interpreter
crashing in BCryptGenRandom during file/path initialization, before BTLS;
the crypto and socket probes deliberately continue to cover those paths
separately. Thumbprint is also excluded to avoid CryptoConfig/file lookup
masking the certificate-parse result.
The second run further isolated a CryptFindOIDInfo crash after successful
certificate construction when reading Subject. Subject/OID lookup is now a
separate probe; certificate tests validate the exact raw DER bytes, not
Subject, Thumbprint or a Windows GetModuleHandle call.

Push runs reuse the four engines built by run 38078468319: source manifests,
binary hashes, BTLS configuration and unchanged mono.make are verified before
reuse. Dispatch with a blank engine_run rebuilds from source. The failed
overall run is not treated as a successful runtime gate: only its verified
engine-build outputs are reused, and all API tests execute again.

Each API is tested in its own process in JIT (none) and interpreter (interp)
modes. A failed case does not skip later cases. Real API failures fail CI;
the deliberately ambiguous native-default ABI probe is a diagnostic control
and a verified native crash is recorded as ABI_MISMATCH_OBSERVED instead.
The explicit cdecl native probe must succeed. A timeout without the probe
entry and a native-crash signature is never accepted as the ABI result.

Scope: DER and PKCS#12 certificate parsing; direct native DER parsing with
default vs explicit cdecl declarations; handle-based internal calls; a real
Windows default-Winapi call; gzip round trip; hashing, RNG and AES round
trip; XML; OID lookup; loopback TCP. This is not full TLS handshake, trust-policy,
SOLIDWORKS, Toolbox, COM lifetime, or exhaustive class-library validation.

The source inventory is a triage list, not proof of a defect: default Winapi
is correct for stdcall Windows APIs, and Unix-only P/Invokes may not run in
Wine. No production runtime or container is changed.

## Cdecl fix regression

`btls-fix.yml` builds two Windows System.dll versions from the same 11.3.0-based
source: unchanged declarations and explicit Cdecl declarations. It runs the
new metadata unit test, then compares released, rebuilt-baseline and fixed
System.dll under the same BTLS-enabled PR35 engines from run 38078468319.
mscorlib and native BTLS stay at their official released versions. Source
revisions, build configuration and binary hashes are checked before reuse.

The x86 interpreter baseline must reproduce the specific managed BTLS import
crash; the deliberately invalid native-default declaration must still produce
its own ABI-mismatch diagnostic. Neither outcome substitutes for a passing
fixed API test. Fixed DER/PFX imports, metadata, certificate properties, PFX
export/reimport, invalid input, and a self-signed loopback TLS 1.2 handshake
must all pass on x86/x64 in both JIT and interpreter modes, as must the wider
runtime controls. The TLS callback accepts only the generated fixture; this
does not validate system trust-store policy or external HTTPS services.

Push runs can reuse the successfully compiled System.dll pair from run
38085093813. That overall job failed when its new test used Assert.Greater,
which the vendored NUnitLite does not expose. The test-only follow-up uses
Assert.IsTrue; CI verifies no library implementation changed between those
source revisions. It compiles the repository's actual NUnitLite and exact
fixture and executes it in all four Wine runtime modes, requiring one
executed, successful test case in the XML report (ignored tests fail).
Prior job status is never used as a passing test gate. Dispatch with a blank
classlib_run rebuilds the matching class libraries from source.
