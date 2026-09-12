//
// Minimal RegAsm-compatible assembly registration tool for Wine Mono.
//
// Copyright 2026 YJBeetle
//
// This library is free software; you can redistribute it and/or
// modify it under the terms of the GNU Lesser General Public
// License as published by the Free Software Foundation; either
// version 2.1 of the License, or (at your option) any later version.
//
// This library is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
// Lesser General Public License for more details.
//

using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;

class RegAsm
{
	const int ErrorExitCode = 100;

	static bool unregister;
	static bool codeBase;
	static bool silent;
	static bool noLogo;
	static bool showHelp;
	static string assemblyFile;

	static int Main (string[] arguments)
	{
		try {
			ParseArguments (arguments);
			if (showHelp) {
				PrintUsage ();
				return 0;
			}
			if (assemblyFile == null)
				throw new ArgumentException ("No assembly file was specified.");

			if (!noLogo && !silent)
				Console.WriteLine ("Wine Mono Assembly Registration Tool");

			string path = Path.GetFullPath (assemblyFile);
			Assembly assembly = Assembly.LoadFrom (path);
			RegistrationServices services = new RegistrationServices ();
			if (unregister)
				services.UnregisterAssembly (assembly);
			else
				services.RegisterAssembly (assembly, codeBase ?
					AssemblyRegistrationFlags.SetCodeBase : AssemblyRegistrationFlags.None);

			if (!silent)
				Console.WriteLine (unregister ?
					"Types unregistered successfully" : "Types registered successfully");
			return 0;
		} catch (Exception exception) {
			Console.Error.WriteLine ("RegAsm : error RA0000 : {0}", GetMessage (exception));
			return ErrorExitCode;
		}
	}

	static void ParseArguments (string[] arguments)
	{
		foreach (string argument in arguments) {
			if (argument.Length == 0)
				continue;
			if (argument[0] != '/' && argument[0] != '-') {
				if (assemblyFile != null)
					throw new ArgumentException ("More than one assembly file was specified.");
				assemblyFile = argument;
				continue;
			}

			string option = argument.Substring (1);
			int separator = option.IndexOf (':');
			if (separator >= 0)
				option = option.Substring (0, separator);

			if (EqualsOption (option, "u") || EqualsOption (option, "unregister"))
				unregister = true;
			else if (EqualsOption (option, "codebase"))
				codeBase = true;
			else if (EqualsOption (option, "s") || EqualsOption (option, "silent"))
				silent = true;
			else if (EqualsOption (option, "nologo"))
				noLogo = true;
			else if (EqualsOption (option, "?") || EqualsOption (option, "help"))
				showHelp = true;
			else if (EqualsOption (option, "tlb") || EqualsOption (option, "regfile") ||
				EqualsOption (option, "registered") || EqualsOption (option, "asmpath") ||
				EqualsOption (option, "verbose"))
				throw new NotSupportedException ("The /" + option + " option is not implemented.");
			else
				throw new ArgumentException ("Unknown option: " + argument);
		}
	}

	static bool EqualsOption (string left, string right)
	{
		return String.Equals (left, right, StringComparison.OrdinalIgnoreCase);
	}

	static string GetMessage (Exception exception)
	{
		while (exception is TargetInvocationException && exception.InnerException != null)
			exception = exception.InnerException;

		ReflectionTypeLoadException loadException = exception as ReflectionTypeLoadException;
		if (loadException != null && loadException.LoaderExceptions != null &&
			loadException.LoaderExceptions.Length != 0)
			return loadException.Message + " " + loadException.LoaderExceptions[0].Message;
		return exception.Message;
	}

	static void PrintUsage ()
	{
		Console.WriteLine ("Usage: regasm assemblyFile [options]");
		Console.WriteLine ("  /codebase          Record the assembly path in the registry");
		Console.WriteLine ("  /unregister, /u    Unregister the assembly");
		Console.WriteLine ("  /silent, /s        Suppress success messages");
		Console.WriteLine ("  /nologo            Suppress the startup banner");
		Console.WriteLine ("  /help, /?          Display this help");
	}
}
