#!/usr/bin/env bash
set -euo pipefail

test_root="$PWD/registration-test"
runtime_root=$(dirname "$(dirname "$(find runtime -name libmono-2.0-x86_64.dll -print -quit)")")
candidate_mscorlib="$PWD/image/lib/mono/4.5/mscorlib.dll"

test -n "$runtime_root"
test -f "$runtime_root/lib/mono/4.5/mscorlib.dll"
test -f "$candidate_mscorlib"

mkdir -p "$test_root"
mcs -target:library -out:"$test_root/RegistrationProbe.dll" .github/fixtures/registration-services/RegistrationProbe.cs
mcs -out:"$test_root/RegistrationRunner.exe" .github/fixtures/registration-services/RegistrationRunner.cs
cp "$candidate_mscorlib" "$runtime_root/lib/mono/4.5/mscorlib.dll"

export WINEPREFIX="$test_root/prefix"
export WINEDEBUG=-all
WINEDLLOVERRIDES='mscoree,mshtml=' timeout -k 5 120 wine wineboot -u
runtime_windows=$(winepath -w "$runtime_root")
wine reg add 'HKCU\Software\Wine\Mono' /v RuntimePath /t REG_SZ /d "$runtime_windows" /f

runner_windows=$(winepath -w "$test_root/RegistrationRunner.exe")
probe_windows=$(winepath -w "$test_root/RegistrationProbe.dll")
WINE_MONO_AOT=none timeout -k 5 120 wine "$runner_windows" register "$probe_windows" > "$test_root/register.log" 2>&1

wine reg query 'HKCR\MonoTests.RegistrationServices.Probe' /reg:32 > "$test_root/progid.log"
wine reg query 'HKCR\CLSID\{5E4466A3-2BA4-414E-B70B-317D91BE57CC}\InprocServer32' /reg:32 > "$test_root/clsid.log"
wine reg query 'HKCR\CLSID\{5E4466A3-2BA4-414E-B70B-317D91BE57CC}\MonoRegistrationProbe' /reg:32 > "$test_root/callback.log"
grep -q 'mscoree.dll' "$test_root/clsid.log"
grep -q 'MonoTests.RegistrationServices.ProbeObject' "$test_root/clsid.log"
grep -q 'registered' "$test_root/callback.log"

WINE_MONO_AOT=none timeout -k 5 120 wine "$runner_windows" unregister "$probe_windows" > "$test_root/unregister.log" 2>&1
if wine reg query 'HKCR\MonoTests.RegistrationServices.Probe' /reg:32 > "$test_root/progid-after-unregister.log" 2>&1; then
    echo 'ProgID remains after unregistration' >&2
    exit 1
fi
if wine reg query 'HKCR\CLSID\{5E4466A3-2BA4-414E-B70B-317D91BE57CC}' /reg:32 > "$test_root/clsid-after-unregister.log" 2>&1; then
    echo 'CLSID remains after unregistration' >&2
    exit 1
fi

echo 'RegistrationServices integration test passed'
