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
mcs -out:"$test_root/regasm-x86.exe" tools/regasm/regasm.cs
cp "$test_root/regasm-x86.exe" "$test_root/regasm-x86_64.exe"
mcs -out:"$test_root/fixuparch.exe" tools/fixuparch.cs
mono "$test_root/fixuparch.exe" x86 "$test_root/regasm-x86.exe"
mono "$test_root/fixuparch.exe" x86_64 "$test_root/regasm-x86_64.exe"
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
    local progid_view=$2
    local clsid_view=$3
    local regasm_windows
    regasm_windows=$(winepath -w "$test_root/regasm-$architecture.exe")

    WINE_MONO_AOT=none timeout -k 5 120 wine "$regasm_windows" /silent /codebase "$probe_windows" > "$test_root/register-$architecture.log" 2>&1

    wine reg query 'HKCR\MonoTests.RegistrationServices.Probe' "/reg:$progid_view" > "$test_root/progid-$architecture.log"
    wine reg query 'HKCR\CLSID\{5E4466A3-2BA4-414E-B70B-317D91BE57CC}\InprocServer32' "/reg:$clsid_view" > "$test_root/clsid-$architecture.log"
    wine reg query 'HKCR\CLSID\{5E4466A3-2BA4-414E-B70B-317D91BE57CC}\MonoRegistrationProbe' "/reg:$clsid_view" > "$test_root/callback-$architecture.log"
    grep -q 'mscoree.dll' "$test_root/clsid-$architecture.log"
    grep -q 'MonoTests.RegistrationServices.ProbeObject' "$test_root/clsid-$architecture.log"
    grep -q 'RegistrationProbe.dll' "$test_root/clsid-$architecture.log"
    grep -q 'registered' "$test_root/callback-$architecture.log"

    WINE_MONO_AOT=none timeout -k 5 120 wine "$regasm_windows" /silent /unregister "$probe_windows" > "$test_root/unregister-$architecture.log" 2>&1
    if wine reg query 'HKCR\MonoTests.RegistrationServices.Probe' "/reg:$progid_view" > "$test_root/progid-after-unregister-$architecture.log" 2>&1; then
        echo "ProgID remains after $architecture unregistration" >&2
        exit 1
    fi
    if wine reg query 'HKCR\CLSID\{5E4466A3-2BA4-414E-B70B-317D91BE57CC}' "/reg:$clsid_view" > "$test_root/clsid-after-unregister-$architecture.log" 2>&1; then
        echo "CLSID remains after $architecture unregistration" >&2
        exit 1
    fi
}

# Wine treats HKCR\CLSID as a shared key, while ordinary ProgIDs are redirected.
test_registration x86 32 64
test_registration x86_64 64 64

echo 'RegistrationServices integration test passed'
