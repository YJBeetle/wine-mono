using System;
using System.Net;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography.X509Certificates;

// Local parsing only: not a trust-policy or TLS-handshake test.
// Raw calls vary ONLY the DllImport calling convention.
public static class BtlsProbe
{
    const string Library = "libmono-btls-shared.dll";
    [DllImport(Library, EntryPoint="mono_btls_x509_from_data", CallingConvention=CallingConvention.Cdecl)]
    static extern IntPtr ParseCdecl(IntPtr data, int length, int format);
    [DllImport(Library, EntryPoint="mono_btls_x509_from_data")]
    static extern IntPtr ParseDefault(IntPtr data, int length, int format);
    [DllImport(Library, EntryPoint="mono_btls_x509_free", CallingConvention=CallingConvention.Cdecl)]
    static extern void FreeCdecl(IntPtr certificate);
    static void Managed(string data, string expectedData)
    {
        Type factory = typeof(HttpWebRequest).Assembly.GetType("Mono.Net.Security.MonoTlsProviderFactory", true);
        var method = factory.GetMethod("GetProvider", BindingFlags.Static | BindingFlags.NonPublic,
                                       null, Type.EmptyTypes, null);
        if (method == null) throw new MissingMethodException("GetProvider");
        object provider = method.Invoke(null, null);
        string name = (string)provider.GetType().GetProperty("Name").GetValue(provider, null);
        Console.WriteLine("tls-provider=" + name);
        if (name != "btls") throw new Exception("BTLS provider unavailable");
        using (var certificate = new X509Certificate2(Convert.FromBase64String(data), ""))
        {
            Console.WriteLine("CERTIFICATE_CONSTRUCTOR_RETURNED");
            // Subject/OID lookup, Thumbprint and GetModuleHandle have independent
            // Windows stdcall paths. Validate raw certificate bytes instead.
            byte[] actual = certificate.GetRawCertData();
            byte[] expected = Convert.FromBase64String(expectedData);
            if (actual.Length != expected.Length) throw new Exception("Unexpected certificate size");
            for (int i = 0; i < actual.Length; ++i)
                if (actual[i] != expected[i]) throw new Exception("Unexpected certificate content");
            Console.WriteLine("certificate-raw-bytes=" + actual.Length);
        }
    }

    static void Raw(string data, bool cdecl)
    {
        byte[] bytes = Convert.FromBase64String(data);
        IntPtr buffer = Marshal.AllocHGlobal(bytes.Length);
        try
        {
            Marshal.Copy(bytes, 0, buffer, bytes.Length);
            for (int i = 0; i < 256; ++i)
            {
                IntPtr certificate = cdecl ? ParseCdecl(buffer, bytes.Length, 1)
                                          : ParseDefault(buffer, bytes.Length, 1);
                if (certificate == IntPtr.Zero) throw new Exception("Native DER parse returned null");
                FreeCdecl(certificate);
            }
        }
        finally { Marshal.FreeHGlobal(buffer); }
    }

    public static int Main(string[] args)
    {
        Console.WriteLine("PROBE_ENTER=" + args[0]);
        try
        {
            if (args[0] == "native-cdecl" || args[0] == "native-default")
                Raw(args[1], args[0] == "native-cdecl");
            else Managed(args[1], args[2]);
            Console.WriteLine("PROBE_PASS=" + args[0]);
            return 0;
        }
        catch (Exception ex) { Console.WriteLine(ex.ToString()); return 1; }
    }
}
