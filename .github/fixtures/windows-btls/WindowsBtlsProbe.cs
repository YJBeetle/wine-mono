using System;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography.X509Certificates;

public static class WindowsBtlsProbe
{
    const string Library = "libmono-btls-shared.dll";
    [DllImport(Library, EntryPoint = "mono_btls_x509_from_data", CallingConvention = CallingConvention.Cdecl)]
    static extern IntPtr ParseCdecl(IntPtr data, int length, int format);
    [DllImport(Library, EntryPoint = "mono_btls_x509_from_data")]
    static extern IntPtr ParseDefault(IntPtr data, int length, int format);
    [DllImport(Library, EntryPoint = "mono_btls_x509_free", CallingConvention = CallingConvention.Cdecl)]
    static extern void FreeCdecl(IntPtr certificate);

    static void Native(byte[] der, bool cdecl)
    {
        var buffer = Marshal.AllocHGlobal(der.Length);
        try
        {
            Marshal.Copy(der, 0, buffer, der.Length);
            var declaration = typeof(WindowsBtlsProbe).GetMethod(cdecl ? "ParseCdecl" : "ParseDefault",
                BindingFlags.Static | BindingFlags.NonPublic);
            var attribute = (DllImportAttribute)Attribute.GetCustomAttribute(declaration, typeof(DllImportAttribute));
            Console.WriteLine("calling-convention=" + attribute.CallingConvention);
            for (int i = 0; i < 256; ++i)
            {
                var certificate = cdecl ? ParseCdecl(buffer, der.Length, 1) : ParseDefault(buffer, der.Length, 1);
                if (certificate == IntPtr.Zero) throw new Exception("Native parse returned null");
                FreeCdecl(certificate);
            }
        }
        finally { Marshal.FreeHGlobal(buffer); }
    }

    static void StandardApi(byte[] der, byte[] pfx)
    {
        if (typeof(X509Certificate2).Assembly.GetType("Mono.Btls.MonoBtlsObject") != null)
            throw new Exception("Expected Microsoft .NET Framework, not Mono");
        using (var certificate = new X509Certificate2(der))
        {
            if (!certificate.Subject.Contains("WineMonoBtlsProbe") ||
                certificate.GetRawCertData().Length != der.Length)
                throw new Exception("Standard DER API failed");
        }
        using (var certificate = new X509Certificate2(pfx, "", X509KeyStorageFlags.Exportable))
        {
            if (!certificate.HasPrivateKey) throw new Exception("Standard PFX private key missing");
            byte[] exported = certificate.Export(X509ContentType.Pkcs12, "roundtrip");
            using (var restored = new X509Certificate2(exported, "roundtrip"))
                if (!restored.HasPrivateKey || restored.Thumbprint != certificate.Thumbprint)
                    throw new Exception("Standard PFX round trip failed");
        }
    }

    public static int Main(string[] args)
    {
        Console.WriteLine("PROBE_ENTER=" + args[0]);
        Console.WriteLine("pointer-size=" + IntPtr.Size);
        Console.WriteLine("clr-version=" + Environment.Version);
        Console.WriteLine("class-library=" + typeof(X509Certificate2).Assembly.Location);
        try
        {
            byte[] der = Convert.FromBase64String(args[1]);
            if (args[0] == "standard-api") StandardApi(der, Convert.FromBase64String(args[2]));
            else Native(der, args[0] == "native-cdecl");
            Console.WriteLine("PROBE_PASS=" + args[0]);
            return 0;
        }
        catch (Exception ex) { Console.WriteLine(ex); return 1; }
    }
}
