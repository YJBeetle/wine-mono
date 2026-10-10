# 11.3.0 BTLS investigation (not a release)

This branch forks the former v3 integration test branch (2b19a5da). It does
not contain the CCW lifetime patch and does not rebuild managed assemblies.

The CI matrix builds the original 11.3.0 engine (73610cc7350) and the v3
engine with PR #35 (04226a35017), each with BTLS enabled, for x86 and x64.
Every job also runs the official, prebuilt 11.3.0 engine as a control.
System.dll, mscorlib.dll, the official native BTLS DLL and fixtures stay the
same when engines are exchanged. Exact checksums and source revisions are
saved with the results. The v3 source also contains RegistrationServices
changes, but their managed assemblies are not installed by these tests.

Each API is tested in its own process in JIT (none) and interpreter (interp)
modes. A failed case does not skip later cases. Real API failures fail CI;
the deliberately ambiguous native-default ABI probe is a diagnostic control
and a verified native crash is recorded as ABI_MISMATCH_OBSERVED instead.
The explicit cdecl native probe must succeed. A timeout without the probe
entry and a native-crash signature is never accepted as the ABI result.

Scope: DER and PKCS#12 certificate parsing; direct native DER parsing with
default vs explicit cdecl declarations; handle-based internal calls; a real
Windows default-Winapi call; gzip round trip; hashing, RNG and AES round
trip; XML; loopback TCP. This is not full TLS handshake, trust-policy,
SOLIDWORKS, Toolbox, COM lifetime, or exhaustive class-library validation.

The source inventory is a triage list, not proof of a defect: default Winapi
is correct for stdcall Windows APIs, and Unix-only P/Invokes may not run in
Wine. No production runtime or container is changed.
