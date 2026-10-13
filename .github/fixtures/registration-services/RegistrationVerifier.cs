using System;
using Microsoft.Win32;

class RegistrationVerifier
{
	const string ProgId = "MonoTests.RegistrationServices.Probe";
	const string ClassId = "{5E4466A3-2BA4-414E-B70B-317D91BE57CC}";
	const string DerivedProgId = "MonoTests.RegistrationServices.DerivedProbe";
	const string DerivedClassId = "{641D963E-EA94-4E4F-B6EF-1DFEB43FB697}";
	const string CallbackPath = "MonoTests.RegistrationServices.CallbackState";

	static int Main (string[] arguments)
	{
		if (arguments.Length != 1 || (arguments[0] != "registered" && arguments[0] != "removed")) {
			Console.Error.WriteLine ("Usage: RegistrationVerifier registered|removed");
			return 2;
		}

		try {
			if (arguments[0] == "registered")
				VerifyRegistered ();
			else
				VerifyRemoved ();
			Console.WriteLine (arguments[0]);
			return 0;
		} catch (Exception exception) {
			Console.Error.WriteLine (exception.Message);
			return 1;
		}
	}

	static void VerifyRegistered ()
	{
		using (RegistryKey progId = RequireKey (ProgId))
			RequireEqual ("ProgID", "MonoTests.RegistrationServices.ProbeObject", progId.GetValue (String.Empty));

		using (RegistryKey server = RequireKey ("CLSID\\" + ClassId + "\\InprocServer32")) {
			RequireEqual ("server", "mscoree.dll", server.GetValue (String.Empty));
			RequireEqual ("class", "MonoTests.RegistrationServices.ProbeObject", server.GetValue ("Class"));
			string codeBase = server.GetValue ("CodeBase") as string;
			if (codeBase == null || codeBase.IndexOf ("RegistrationProbe.dll", StringComparison.OrdinalIgnoreCase) < 0)
				throw new InvalidOperationException ("CodeBase was not registered.");
		}

		using (RegistryKey callback = RequireKey (CallbackPath)) {
			RequireEqual ("register bitness", IntPtr.Size.ToString (), callback.GetValue ("RegisterBitness"));
			RequireEqual ("register callback", "MonoTests.RegistrationServices.ProbeObject",
				callback.GetValue ("Register"));
			RequireEqual ("derived register callback",
				"HKEY_CLASSES_ROOT\\CLSID\\" + DerivedClassId,
				callback.GetValue ("DerivedRegister"));
		}

		using (RegistryKey derived = RequireKey (DerivedProgId))
			RequireEqual ("derived ProgID", "MonoTests.RegistrationServices.DerivedProbe",
				derived.GetValue (String.Empty));
	}

	static void VerifyRemoved ()
	{
		using (RegistryKey progId = Registry.ClassesRoot.OpenSubKey (ProgId)) {
			if (progId != null)
				throw new InvalidOperationException ("ProgID remains after unregistration.");
		}
		using (RegistryKey classId = Registry.ClassesRoot.OpenSubKey ("CLSID\\" + ClassId)) {
			if (classId != null)
				throw new InvalidOperationException ("CLSID remains after unregistration.");
		}
		using (RegistryKey progId = Registry.ClassesRoot.OpenSubKey (DerivedProgId)) {
			if (progId != null)
				throw new InvalidOperationException ("Derived ProgID remains after unregistration.");
		}
		using (RegistryKey classId = Registry.ClassesRoot.OpenSubKey ("CLSID\\" + DerivedClassId)) {
			if (classId != null)
				throw new InvalidOperationException ("Derived CLSID remains after unregistration.");
		}
		using (RegistryKey callback = RequireKey (CallbackPath)) {
			RequireEqual ("unregister bitness", IntPtr.Size.ToString (), callback.GetValue ("UnregisterBitness"));
			RequireEqual ("unregister callback", "MonoTests.RegistrationServices.ProbeObject",
				callback.GetValue ("Unregister"));
			RequireEqual ("derived unregister callback",
				"HKEY_CLASSES_ROOT\\CLSID\\" + DerivedClassId,
				callback.GetValue ("DerivedUnregister"));
		}
	}

	static RegistryKey RequireKey (string path)
	{
		RegistryKey key = Registry.ClassesRoot.OpenSubKey (path);
		if (key == null)
			throw new InvalidOperationException ("Missing registry key: HKCR\\" + path);
		return key;
	}

	static void RequireEqual (string name, string expected, object actual)
	{
		if (!String.Equals (expected, actual as string, StringComparison.Ordinal))
			throw new InvalidOperationException (name + " mismatch: " + (actual ?? "<null>"));
	}
}
