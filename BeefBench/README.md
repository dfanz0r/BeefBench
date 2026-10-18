# BeefBench

A small benchmark harness for [Beef](https://www.beeflang.org/) programs: a runner with warm-up and
repeated measurement, mean/error/median statistics, optional throughput columns, a live terminal
table, CSV output, and a command line your suites extend. It depends only on corlib and knows nothing
about what you measure; suites live in the project that owns the code under test.

## Use

1. Add the project as a dependency (`BeefBench = "*"` in your `BeefProj.toml`, with the workspace
   pointing at this repository).
2. Write suites. A suite is a static class with `Setup` (registers benchmarks) and `Teardown`.
   Benchmarks are registered either directly:

   ```beef
   BenchmarkRegistry.Register("Bitfield_SetBit", new => Bitfield_SetBit, 100000, 5, 15, "SetBit");
   ```

   (the registry copies the name and category, and takes ownership of the delegate) or through the
   builder in `BenchmarkBuilder.bf` for suites with cases, variants, tags and comparison sets.
3. Register the suites and flags in your program's `Main`:

   ```beef
   let app = scope BenchmarkApp();
   app.Title = "MyBench";
   app.AddSuite("bit", => BitBenchmarks.Setup, => BitBenchmarks.Teardown, true, "Bit helpers");
   app.AddSuite("big", => BigBenchmarks.Setup, => BigBenchmarks.Teardown, false, "Slow suite");
   app.AddOption("data", "dir", "Directory with the input data.", new (value) => { ... }, "big");
   app.AddFlag("verbose", "Print extra detail.", new () => { ... });
   app.AddCommand("selftest", "Run the self test instead.", new (args) => RunSelfTest(args));
   return app.Run(args);
   ```

## Command line

Built in: `--suite=a,b` (or `--a`; `--suite=all` runs everything), `--filter=<text>`, `--csv=<path>`
(empty: no file), `--no-tui`, `--list`, `--help`. Everything you register with `AddFlag`,
`AddOption` and `AddCommand` is parsed, validated (unknown flags exit with code 2) and listed by
`--help`, grouped under the suite it belongs to.

## Measuring correctly

A benchmark must consume every result it computes, or the optimiser removes the work. Compare
changes against the previous commit built the same way, on a quiet machine.
