using System;
using System.Runtime.InteropServices;
using Microsoft.Win32;

[assembly: ComVisible (false)]

namespace MonoTests.RegistrationServices {
	[ComVisible (true)]
	[Guid ("5E4466A3-2BA4-414E-B70B-317D91BE57CC")]
	[ProgId ("MonoTests.RegistrationServices.Probe")]
	public class ProbeObject {
		public ProbeObject ()
		{
		}

		[ComRegisterFunction]
		public static void Register (Type type)
		{
			using (RegistryKey key = Registry.ClassesRoot.CreateSubKey (
				"CLSID\\{5E4466A3-2BA4-414E-B70B-317D91BE57CC}\\MonoRegistrationProbe"))
				key.SetValue (String.Empty, type == typeof (ProbeObject) ? "registered" : "wrong type");
		}

		[ComUnregisterFunction]
		public static void Unregister (Type type)
		{
			Registry.ClassesRoot.DeleteSubKeyTree (
				"CLSID\\{5E4466A3-2BA4-414E-B70B-317D91BE57CC}\\MonoRegistrationProbe", false);
		}
	}
}

