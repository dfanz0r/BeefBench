# BeefBench

A small benchmark harness for Beef programs: suites registered by name, run flags registered through
`BenchmarkApp` (`AddSuite`, `AddFlag`, `AddOption`, `AddCommand`), a terminal UI and CSV output. It has no
dependencies besides corlib and no benchmarks of its own; applications bring their suites.

Use it as a Git dependency (the project is in the `BeefBench/` folder):

```toml
BeefBench = {Git = "https://github.com/dfanz0r/BeefBench.git?path=/BeefBench", Version = "=0.1.0"}
```

See `BeefBench/README.md` for the API.
