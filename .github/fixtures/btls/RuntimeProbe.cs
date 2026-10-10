using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Xml;

public static class RuntimeProbe
{
    [DllImport("kernel32.dll")]
    static extern uint GetCurrentProcessId();

    static void Check(bool condition) { if (!condition) throw new Exception("Validation failed"); }

    static void InternalCalls()
    {
        for (int n = 0; n < 256; ++n)
        {
            int[] values = { 11, 22, 33, 44, 55, 66, 77, 88 };
            Check(values[7] == 88 && values.Sum() == 396);
            Check(new string('x', 31).Length == 31);
            Check(typeof(Stream).IsAssignableFrom(typeof(MemoryStream)));
            Check(GetCurrentProcessId() != 0);
        }
    }

    static void Compression()
    {
        byte[] data = Encoding.UTF8.GetBytes(new string('a', 10000) + "test");
        using (var output = new MemoryStream())
        {
            using (var gzip = new GZipStream(output, CompressionMode.Compress, true))
                gzip.Write(data, 0, data.Length);
            using (var input = new MemoryStream(output.ToArray()))
            using (var gzip = new GZipStream(input, CompressionMode.Decompress))
            using (var restored = new MemoryStream())
            {
                gzip.CopyTo(restored);
                Check(restored.ToArray().SequenceEqual(data));
            }
        }
    }

    static void Crypto()
    {
        byte[] bytes = Encoding.ASCII.GetBytes("abc");
        using (var sha = SHA256.Create())
            Check(BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-", "").ToLowerInvariant()
                  == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
        using (var rng = RandomNumberGenerator.Create())
        {
            byte[] key = new byte[32];
            rng.GetBytes(key);
            Check(key.Any(b => b != 0));
        }
        using (var aes = Aes.Create())
        {
            byte[] encrypted = aes.CreateEncryptor().TransformFinalBlock(bytes, 0, bytes.Length);
            byte[] decrypted = aes.CreateDecryptor().TransformFinalBlock(encrypted, 0, encrypted.Length);
            Check(decrypted.SequenceEqual(bytes));
        }
    }

    static void Xml()
    {
        var doc = new XmlDocument();
        doc.LoadXml("<root><item id='7'>value</item></root>");
        Check(doc.SelectSingleNode("/root/item[@id='7']").InnerText == "value");
    }

    static void Oid()
    {
        var oid = new Oid("2.5.4.3");
        Check(!String.IsNullOrEmpty(oid.FriendlyName));
        Check(new Oid(oid.FriendlyName).Value == "2.5.4.3");
    }

    static void Socket()
    {
        var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        try
        {
            using (var client = new TcpClient())
            {
                client.Connect((IPEndPoint)listener.LocalEndpoint);
                using (var accepted = listener.AcceptTcpClient())
                {
                    client.GetStream().WriteByte(42);
                    accepted.GetStream().ReadTimeout = 5000;
                    Check(accepted.GetStream().ReadByte() == 42);
                }
            }
        }
        finally { listener.Stop(); }
    }

    public static int Main(string[] args)
    {
        Console.WriteLine("PROBE_ENTER=" + args[0]);
        try
        {
            switch (args[0])
            {
                case "internal-calls": InternalCalls(); break;
                case "compression": Compression(); break;
                case "crypto": Crypto(); break;
                case "xml": Xml(); break;
                case "oid": Oid(); break;
                case "socket": Socket(); break;
                default: throw new ArgumentException(args[0]);
            }
            Console.WriteLine("PROBE_PASS=" + args[0]);
            return 0;
        }
        catch (Exception ex) { Console.WriteLine(ex.ToString()); return 1; }
    }
}
