#!/usr/bin/env bash
# Only System.dll changes; reuse the same PR35 engine and released native libraries.
set -euo pipefail
architecture=${1:?architecture required}
case "$architecture" in
    x86) platform=x86; native_dir=x86 ;;
    x86_64) platform=x64; native_dir=x86_64 ;;
    *) exit 2 ;;
esac
root="$PWD/btls-fix-test"
mkdir -p "$root/runtime"
curl -fL --retry 3 https://github.com/wine-mono/wine-mono/releases/download/wine-mono-11.3.0/wine-mono-11.3.0-x86.tar.xz -o "$root/runtime.tar.xz"
tar -xf "$root/runtime.tar.xz" -C "$root/runtime"
runtime=$(dirname "$(dirname "$(find "$root/runtime" -name "libmono-2.0-$architecture.dll" -print -quit)")")
cp "$runtime/lib/mono/4.5/System.dll" "$root/released-System.dll"
engine="$PWD/engine-cache/image/bin/libmono-2.0-$architecture.dll"
native=$(find "$runtime/lib/$native_dir" -name libmono-btls-shared.dll -print -quit)
test -s "$native"
cp "$engine" "$runtime/bin/libmono-2.0-$architecture.dll"
cp "$native" "$root/libmono-btls-shared.dll"
sha256sum "$engine" "$native" "$runtime/lib/mono/4.5/mscorlib.dll" \
    "$root/released-System.dll" classlib-cache/btls-classlib/{baseline,fixed}/System.dll > "$root/checksums.txt"
mcs -platform:"$platform" -out:"$root/btls.exe" .github/fixtures/btls/BtlsProbe.cs
mcs -platform:"$platform" -r:System.Core -r:System.Xml -out:"$root/runtime.exe" .github/fixtures/btls/RuntimeProbe.cs
# Compile the repository's real NUnitLite and the exact upstream unit fixture,
# rather than replacing assertions with a stub or relying on distro NUnit APIs.
(cd mono/mcs/tools/nunit-lite/NUnitLite &&
 mcs -target:library -r:System.Core -r:System.Xml \
     -define:__MOBILE__,TRACE,DEBUG,NET_4_0,CLR_4_0,NUNITLITE \
     -out:"$root/nunitlite.dll" @nunitlite.dll.sources)
mcs -platform:"$platform" -r:"$root/nunitlite.dll" -out:"$root/unit.exe" \
    mono/mcs/class/System/Test/Mono.Btls/NativeCallingConventionTest.cs \
    mono/mcs/tools/nunit-lite/nunit-lite-console/Console.cs
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$root/key.pem" -out "$root/certificate.pem" -days 1 -subj '/CN=WineMonoBtlsProbe'
openssl x509 -in "$root/certificate.pem" -outform DER -out "$root/certificate.der"
openssl pkcs12 -export -legacy -inkey "$root/key.pem" -in "$root/certificate.pem" -out "$root/certificate.pfx" -passout pass:
export WINEPREFIX="$root/prefix" WINEARCH=win64 WINEDEBUG=-all MONO_TLS_PROVIDER=btls
WINEDLLOVERRIDES='mscoree,mshtml=' timeout -k 5 120 wine wineboot -u
wine reg add 'HKCU\Software\Wine\Mono' /v RuntimePath /t REG_SZ /d "$(winepath -w "$runtime")" /f
btls_exe=$(winepath -w "$root/btls.exe")
runtime_exe=$(winepath -w "$root/runtime.exe")
unit_exe=$(winepath -w "$root/unit.exe")
der=$(base64 -w 0 "$root/certificate.der")
pfx=$(base64 -w 0 "$root/certificate.pfx")
printf 'classlib\tmode\ttest\texit\tresult\n' > "$root/summary.txt"
failures=0
for classlib in released baseline fixed; do
    wineserver -k || true
    wineserver -w
    dll="$root/released-System.dll"
    test "$classlib" = released || dll="$PWD/classlib-cache/btls-classlib/$classlib/System.dll"
    cp "$dll" "$runtime/lib/mono/4.5/System.dll"
    cmp "$dll" "$runtime/lib/mono/4.5/System.dll"
    for mode in none interp; do
        probes='managed-der managed-pkcs12 metadata'
        if [ "$classlib" = fixed ]; then
            probes='unit managed-der managed-pkcs12 metadata managed-properties managed-pkcs12-export managed-invalid loopback-tls native-cdecl native-default internal-calls compression crypto xml oid socket'
        fi
        for probe in $probes; do
            exe="$btls_exe"; fixture="$der"
            case "$probe" in
                managed-pkcs12|managed-pkcs12-export|loopback-tls) fixture="$pfx" ;;
                internal-calls|compression|crypto|xml|oid|socket) exe="$runtime_exe"; fixture='' ;;
            esac
            log="$root/$classlib-$mode-$probe.log"
            set +e
            if [ "$probe" = unit ]; then
                result_xml="$root/unit-$mode.xml"
                WINE_MONO_AOT="$mode" timeout -k 5 45 wine "$unit_exe" \
                    -test=MonoTests.Mono.Btls.NativeCallingConventionTest \
                    -format:nunit2 "-result:$(winepath -w "$result_xml")" > "$log" 2>&1
                code=$?
                if [ "$code" -eq 0 ]; then
                    python3 - "$result_xml" <<'PY'
import sys
import xml.etree.ElementTree as ET
cases = ET.parse(sys.argv[1]).findall('.//test-case')
assert len(cases) == 1, 'Expected exactly the BTLS unit test'
case = cases[0]
assert case.get('executed') == 'True' and case.get('success') == 'True', 'Unit ignored or failed'
assert case.get('name').endswith('NativeImportsAndCallbacksUseCdecl'), 'Unexpected test'
PY
                    code=$?
                    if [ "$code" -eq 0 ]; then echo 'PROBE_PASS=unit' >> "$log"; fi
                fi
            else
                WINE_MONO_AOT="$mode" timeout -k 5 45 wine "$exe" "$probe" "$fixture" "$der" > "$log" 2>&1
                code=$?
            fi
            set -e
            tr -d '\r' < "$log" > "$log.normalized"
            result=FAIL
            if [ "$classlib" != fixed ] && [ "$probe" = metadata ]; then
                if [ "$code" -eq 1 ] && grep -Fq 'BTLS_ABI_NOT_CDECL=Mono.Btls.' "$log"; then
                    result=BASELINE_METADATA_MISMATCH
                fi
            elif [ "$classlib" != fixed ] && [ "$architecture" = x86 ] && [ "$mode" = interp ]; then
                if [ "$code" -ne 0 ] && grep -Fxq "PROBE_ENTER=$probe" "$log.normalized" &&
                   grep -Eq 'Native Crash Reporting|Unhandled page fault' "$log" &&
                   grep -Fq 'mono_btls_pkcs12_import' "$log"; then
                    result=BASELINE_BTLS_CRASH_REPRODUCED
                fi
            elif [ "$probe" = native-default ] && [ "$architecture" = x86 ] && [ "$mode" = interp ]; then
                if [ "$code" -ne 0 ] && grep -Fxq "PROBE_ENTER=$probe" "$log.normalized" &&
                   grep -Eq 'Native Crash Reporting|Unhandled page fault' "$log" &&
                   grep -Fq 'BtlsProbe:ParseDefault' "$log"; then
                    result=DIAGNOSTIC_ABI_MISMATCH
                fi
            elif [ "$code" -eq 0 ] && grep -Fxq "PROBE_PASS=$probe" "$log.normalized" &&
                 ! grep -Eq 'Assertion at|Unhandled Exception|Native Crash Reporting' "$log"; then
                result=PASS
            fi
            test "$result" != FAIL || failures=$((failures + 1))
            printf '%s\t%s\t%s\t%s\t%s\n' "$classlib" "$mode" "$probe" "$code" "$result" >> "$root/summary.txt"
            cat "$log"
            wineserver -k || true
            wineserver -w
        done
    done
done
cat "$root/summary.txt"
test "$failures" -eq 0
echo BTLS_FIXED_RUNTIME_MATRIX_PASS
