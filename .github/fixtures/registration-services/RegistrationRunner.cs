using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;

class RegistrationRunner {
	public static int Main (string[] args)
	{
		if (args.Length != 2 || (args[0] != "register" && args[0] != "unregister")) {
			Console.Error.WriteLine ("Usage: RegistrationRunner register|unregister assembly");
			return 2;
		}

		Assembly assembly = Assembly.LoadFrom (Path.GetFullPath (args[1]));
		RegistrationServices services = new RegistrationServices ();
		bool changed = args[0] == "register" ?
			services.RegisterAssembly (assembly, AssemblyRegistrationFlags.SetCodeBase) :
			services.UnregisterAssembly (assembly);
		Console.WriteLine ("{0}: {1}", args[0], changed);
		return changed ? 0 : 1;
	}
}
