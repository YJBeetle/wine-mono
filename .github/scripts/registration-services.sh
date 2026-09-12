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
mcs -platform:x86 -out:"$test_root/regasm-x86.exe" tools/regasm/regasm.cs
mcs -platform:x64 -out:"$test_root/regasm-x86_64.exe" tools/regasm/regasm.cs
mcs -platform:x86 -out:"$test_root/verifier-x86.exe" .github/fixtures/registration-services/RegistrationVerifier.cs
mcs -platform:x64 -out:"$test_root/verifier-x86_64.exe" .github/fixtures/registration-services/RegistrationVerifier.cs
cp "$candidate_mscorlib" "$runtime_root/lib/mono/4.5/mscorlib.dll"

export WINEPREFIX="$test_root/prefix"
export WINEDEBUG=-all
WINEDLLOVERRIDES='mscoree,mshtml=' timeout -k 5 120 wine wineboot -u
runtime_windows=$(winepath -w "$runtime_root")
wine reg add 'HKCU\Software\Wine\Mono' /v RuntimePath /t REG_SZ /d "$runtime_windows" /f

probe_windows=$(winepath -w "$test_root/RegistrationProbe.dll")

test_registration()
{
    local architecture=$1
    local regasm_windows
    local verifier_windows
    regasm_windows=$(winepath -w "$test_root/regasm-$architecture.exe")
    verifier_windows=$(winepath -w "$test_root/verifier-$architecture.exe")

    WINE_MONO_AOT=none timeout -k 5 120 wine "$regasm_windows" /silent /codebase "$probe_windows" > "$test_root/register-$architecture.log" 2>&1
    WINE_MONO_AOT=none timeout -k 5 120 wine "$verifier_windows" registered > "$test_root/verify-register-$architecture.log" 2>&1

    WINE_MONO_AOT=none timeout -k 5 120 wine "$regasm_windows" /silent /unregister "$probe_windows" > "$test_root/unregister-$architecture.log" 2>&1
    WINE_MONO_AOT=none timeout -k 5 120 wine "$verifier_windows" removed > "$test_root/verify-unregister-$architecture.log" 2>&1
}

test_registration x86
test_registration x86_64

echo 'RegistrationServices integration test passed'
