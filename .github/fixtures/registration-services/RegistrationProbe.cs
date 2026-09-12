using System;
using System.Runtime.InteropServices;
using Microsoft.Win32;

[assembly: ComVisible (false)]

namespace MonoTests.RegistrationServices {
	static class CallbackState {
		const string Path = "MonoTests.RegistrationServices.CallbackState";

		public static void Set (string name, string value)
		{
			using (RegistryKey key = Registry.ClassesRoot.CreateSubKey (Path))
				key.SetValue (name, value);
		}
	}

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
			CallbackState.Set ("Register", type.FullName);
		}

		[ComUnregisterFunction]
		public static void Unregister (Type type)
		{
			CallbackState.Set ("Unregister", type.FullName);
		}
	}

	[ComVisible (false)]
	public abstract class CallbackBase {
		[ComRegisterFunction]
		public static void RegisterBase (Type type)
		{
			CallbackState.Set ("DerivedRegister", "base");
		}

		[ComUnregisterFunction]
		public static void UnregisterBase (Type type)
		{
			CallbackState.Set ("DerivedUnregister", "base");
		}
	}

	[ComVisible (true)]
	[Guid ("641D963E-EA94-4E4F-B6EF-1DFEB43FB697")]
	[ProgId ("MonoTests.RegistrationServices.DerivedProbe")]
	public class DerivedProbe : CallbackBase {
		public DerivedProbe ()
		{
		}

		[ComRegisterFunction]
		public static void RegisterDerived (string key)
		{
			CallbackState.Set ("DerivedRegister", key);
		}

		[ComUnregisterFunction]
		public static void UnregisterDerived (string key)
		{
			CallbackState.Set ("DerivedUnregister", key);
		}
	}
}
