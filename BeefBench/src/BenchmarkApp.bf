using System;
using System.Collections;

namespace BeefBench;

/// Called when a registered flag (--name) appears on the command line.
public delegate void BenchmarkFlagHandler();
/// Called with the text after '=' for a registered option (--name=value).
public delegate void BenchmarkOptionHandler(StringView value);
/// A registered command replaces the whole run (--name): it receives every argument and returns the exit code.
public delegate int BenchmarkCommandHandler(Span<String> args);

/// The command line, suites and help of a benchmark program. The program registers its suites and the
/// flags its suites need; the harness parses and validates the command line, calls the handlers, prints
/// --help, and runs the selected suites. The harness knows nothing about what is measured.
///
/// Built-in flags (always available):
///   --suite=<name>[,<name>...]   run only these suites ("all" runs every suite)
///   --<name>                     shorthand for --suite=<name>
///   --filter=<text>              keep benchmarks whose name contains <text>
///   --csv=<path>                 where to write results (empty: no file; default benchmark_results.csv)
///   --no-tui                     plain text output instead of the live table
///   --list                       print the suite names and exit
///   --help                       print the usage, suites and registered flags, and exit
public class BenchmarkApp
{
	class Suite
	{
		public String Name = new .() ~ delete _;
		public String Help = new .() ~ delete _;
		public function void() Setup;
		public function void() Teardown;
		public bool InDefaultRun;
	}

	class Flag
	{
		public String Name = new .() ~ delete _;
		public String ValueName ~ delete _;
		public String Help = new .() ~ delete _;
		/// The suite the flag belongs to (shown under it in --help), or null for a general flag.
		public String Suite ~ delete _;
		public BenchmarkFlagHandler OnFlag ~ delete _;
		public BenchmarkOptionHandler OnOption ~ delete _;
		public BenchmarkCommandHandler OnCommand ~ delete _;
	}

	static readonly String[?] sReserved = .("suite", "filter", "csv", "no-tui", "list", "help");

	/// Heading of the live results table (default "BeefBench").
	public StringView Title = "BeefBench";

	List<Suite> mSuites = new .() ~ DeleteContainerAndItems!(_);
	List<Flag> mFlags = new .() ~ DeleteContainerAndItems!(_);
	List<String> mSuiteNames = new .() ~ DeleteContainerAndItems!(_);
	String mFilter ~ delete _;
	String mCsv ~ delete _;

	/// Registers a suite: `setup` registers its benchmarks with BenchmarkRegistry, `teardown` releases
	/// what it allocated. A suite with inDefaultRun false only runs when named.
	public void AddSuite(StringView name, function void() setup, function void() teardown = null, bool inDefaultRun = true, StringView help = default)
	{
		Suite suite = new .();
		suite.Name.Set(name);
		suite.Help.Set(help);
		suite.Setup = setup;
		suite.Teardown = teardown;
		suite.InDefaultRun = inDefaultRun;
		mSuites.Add(suite);
	}

	/// Registers `--name`. Takes ownership of the handler.
	public void AddFlag(StringView name, StringView help, BenchmarkFlagHandler onFlag, StringView suite = default)
	{
		Flag flag = NewFlag(name, help, suite);
		flag.OnFlag = onFlag;
	}

	/// Registers `--name=<valueName>`. Takes ownership of the handler.
	public void AddOption(StringView name, StringView valueName, StringView help, BenchmarkOptionHandler onValue, StringView suite = default)
	{
		Flag flag = NewFlag(name, help, suite);
		flag.ValueName = new String(valueName);
		flag.OnOption = onValue;
	}

	/// Registers `--name` as a command that replaces the whole run. Takes ownership of the handler.
	public void AddCommand(StringView name, StringView help, BenchmarkCommandHandler run, StringView suite = default)
	{
		Flag flag = NewFlag(name, help, suite);
		flag.OnCommand = run;
	}

	Flag NewFlag(StringView name, StringView help, StringView suite)
	{
		for (let reserved in sReserved)
		{
			if (reserved == name)
				Runtime.FatalError(scope $"BenchmarkApp: '--{name}' is a built-in flag and cannot be registered.");
		}
		for (let existing in mFlags)
		{
			if (existing.Name == name)
				Runtime.FatalError(scope $"BenchmarkApp: '--{name}' is already registered.");
		}
		Flag flag = new .();
		flag.Name.Set(name);
		flag.Help.Set(help);
		if (!suite.IsEmpty)
			flag.Suite = new String(suite);
		mFlags.Add(flag);
		return flag;
	}

	/// Parses the arguments, runs the selected suites and returns the process exit code:
	/// 0 on success, 2 for a command line error.
	public int Run(Span<String> args)
	{
		bool useTui = true;
		bool list = false;
		bool help = false;
		BenchmarkCommandHandler command = null;

		for (let arg in args)
		{
			if (!arg.StartsWith("--"))
				return UsageError(scope $"Unexpected argument '{arg}'.");

			StringView body = arg.Substring(2);
			StringView name = body;
			StringView value = default;
			bool hasValue = false;
			int equals = body.IndexOf('=');
			if (equals >= 0)
			{
				name = body.Substring(0, equals);
				value = body.Substring(equals + 1);
				hasValue = true;
			}

			if (name == "no-tui") { useTui = false; continue; }
			if (name == "list") { list = true; continue; }
			if (name == "help") { help = true; continue; }
			if (name == "filter")
			{
				if (!hasValue)
					return UsageError("--filter needs a value: --filter=<text>.");
				Set(ref mFilter, value);
				continue;
			}
			if (name == "csv")
			{
				if (!hasValue)
					return UsageError("--csv needs a value: --csv=<path>.");
				Set(ref mCsv, value);
				continue;
			}
			if (name == "suite")
			{
				if (!hasValue)
					return UsageError("--suite needs a value: --suite=<name>[,<name>...].");
				for (let part in value.Split(','))
				{
					if (!part.IsEmpty)
						mSuiteNames.Add(new String(part));
				}
				continue;
			}

			Flag flag = null;
			for (let candidate in mFlags)
			{
				if (candidate.Name == name)
				{
					flag = candidate;
					break;
				}
			}

			if (flag != null)
			{
				if (flag.OnOption != null)
				{
					if (!hasValue)
						return UsageError(scope $"--{name} needs a value: --{name}=<{flag.ValueName}>.");
					flag.OnOption(value);
				}
				else
				{
					if (hasValue)
						return UsageError(scope $"--{name} takes no value.");
					if (flag.OnCommand != null)
						command = flag.OnCommand;
					else
						flag.OnFlag();
				}
				continue;
			}

			// "--<suite name>" is a shorthand for "--suite=<suite name>".
			bool isSuite = false;
			if (!hasValue)
			{
				for (let suite in mSuites)
				{
					if (suite.Name == name)
					{
						mSuiteNames.Add(new String(name));
						isSuite = true;
						break;
					}
				}
			}
			if (!isSuite)
				return UsageError(scope $"Unknown flag '{arg}'.");
		}

		if (help)
		{
			PrintUsage();
			return 0;
		}
		if (list)
		{
			for (let suite in mSuites)
				Console.WriteLine(suite.Name);
			return 0;
		}
		if (command != null)
			return command(args);

		List<Suite> selected = scope .();
		bool all = false;
		for (let name in mSuiteNames)
		{
			if (name == "all")
			{
				all = true;
				continue;
			}
			Suite found = null;
			for (let suite in mSuites)
			{
				if (suite.Name == name)
				{
					found = suite;
					break;
				}
			}
			if (found == null)
				return UsageError(scope $"Unknown suite '{name}'.");
			selected.Add(found);
		}
		if ((all) || (mSuiteNames.IsEmpty))
		{
			selected.Clear();
			for (let suite in mSuites)
			{
				if ((all) || (suite.InDefaultRun))
					selected.Add(suite);
			}
		}

		BenchmarkRunner.Title = Title;
		if (mCsv != null)
			BenchmarkRunner.CsvPath = mCsv;

		for (let suite in selected)
			suite.Setup();
		BenchmarkRegistry.RetainByNameContains((mFilter == null) ? StringView() : StringView(mFilter));
		BenchmarkRunner.RunAll(useTui);
		for (int i = selected.Count - 1; i >= 0; i--)
		{
			if (selected[i].Teardown != null)
				selected[i].Teardown();
		}
		BenchmarkRegistry.Clear();
		return 0;
	}

	int UsageError(StringView message)
	{
		Console.WriteLine(message);
		Console.WriteLine("Run with --help for the flags and suites.");
		return 2;
	}

	static void Set(ref String target, StringView value)
	{
		delete target;
		target = new String(value);
	}

	static void PrintRow(StringView left, StringView right)
	{
		Console.WriteLine($"  {left,-30} {right}");
	}

	void PrintFlag(Flag flag)
	{
		String usage = scope $"--{flag.Name}";
		if (flag.ValueName != null)
			usage.AppendF($"=<{flag.ValueName}>");
		PrintRow(usage, flag.Help);
	}

	void PrintUsage()
	{
		Console.WriteLine("Usage: <program> [flags]");
		Console.WriteLine();
		Console.WriteLine("Flags:");
		PrintRow("--suite=<name>[,<name>...]", "Run only these suites (\"all\" runs every suite). --<name> is a shorthand.");
		PrintRow("--filter=<text>", "Keep benchmarks whose name contains <text>.");
		PrintRow("--csv=<path>", "Write results to <path> (empty: no file; default benchmark_results.csv).");
		PrintRow("--no-tui", "Plain text output instead of the live table.");
		PrintRow("--list", "Print the suite names and exit.");
		PrintRow("--help", "Print this text and exit.");
		for (let flag in mFlags)
		{
			if (flag.Suite == null)
				PrintFlag(flag);
		}

		Console.WriteLine();
		Console.WriteLine("Suites:");
		for (let suite in mSuites)
		{
			String text = scope .(suite.Help);
			if (!suite.InDefaultRun)
				text.Append(" (only when named)");
			PrintRow(suite.Name, text);
			for (let flag in mFlags)
			{
				if ((flag.Suite != null) && (flag.Suite == suite.Name))
				{
					Console.Write("  ");
					PrintFlag(flag);
				}
			}
		}
	}
}
