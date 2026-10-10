using System;
using System.IO;
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
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)]
    static extern IntPtr GetModuleHandle(string module);

    static void Managed(string path)
    {
        Type factory = typeof(HttpWebRequest).Assembly.GetType("Mono.Net.Security.MonoTlsProviderFactory", true);
        var method = factory.GetMethod("GetProvider", BindingFlags.Static | BindingFlags.NonPublic,
                                       null, Type.EmptyTypes, null);
        if (method == null) throw new MissingMethodException("GetProvider");
        object provider = method.Invoke(null, null);
        string name = (string)provider.GetType().GetProperty("Name").GetValue(provider, null);
        Console.WriteLine("tls-provider=" + name);
        if (name != "btls") throw new Exception("BTLS provider unavailable");
        using (var certificate = new X509Certificate2(File.ReadAllBytes(path), ""))
        {
            if (certificate.Subject != "CN=WineMonoBtlsProbe" || certificate.Thumbprint.Length != 40)
                throw new Exception("Unexpected certificate content");
            Console.WriteLine("certificate-subject=" + certificate.Subject);
        }
        if (GetModuleHandle(Library) == IntPtr.Zero) throw new Exception("Native BTLS not loaded");
    }

    static void Raw(string path, bool cdecl)
    {
        byte[] bytes = File.ReadAllBytes(path);
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
            else Managed(args[1]);
            Console.WriteLine("PROBE_PASS=" + args[0]);
            return 0;
        }
        catch (Exception ex) { Console.WriteLine(ex.ToString()); return 1; }
    }
}
