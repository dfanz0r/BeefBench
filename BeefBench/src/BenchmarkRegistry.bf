using System;
using System.Collections;

namespace BeefBench;

delegate void BenchmarkFunc();
delegate void BenchmarkLifecycleFunc();

struct BenchmarkMetadata
{
    public String Suite;
    public String CaseName;
    public String DisplayName;
    public String Tags;
    public String Dimensions;

    public this(String suite = null, String caseName = null, String displayName = null, String tags = null, String dimensions = null)
    {
        Suite = suite;
        CaseName = caseName;
        DisplayName = displayName;
        Tags = tags;
        Dimensions = dimensions;
    }

    public static BenchmarkMetadata Default => default;
}

struct BenchmarkReportOptions
{
    public String LinkedSet;
    public bool SortByPerformance;
    public String ComparisonSet;
    public bool EnableThroughput;
    public double ThroughputWorkPerIteration;
    public String ThroughputUnit;

    public this(String linkedSet = null, bool sortByPerformance = false, String comparisonSet = null, bool enableThroughput = false, double throughputWorkPerIteration = 0, String throughputUnit = null)
    {
        LinkedSet = linkedSet;
        SortByPerformance = sortByPerformance;
        ComparisonSet = comparisonSet;
        EnableThroughput = enableThroughput;
        ThroughputWorkPerIteration = throughputWorkPerIteration;
        ThroughputUnit = throughputUnit;
    }

    public static BenchmarkReportOptions Default => default;
}

struct BenchmarkEntry
{
    public String Name;
    public BenchmarkFunc Func;
    public int WarmupCount;
    public int MeasurementCount;
    public int Iterations;
    public String Category;
    public bool IsBaseline;
    public BenchmarkReportOptions ReportOptions;
    public BenchmarkMetadata Metadata;
    public BenchmarkLifecycleFunc SetupFunc;
    public BenchmarkLifecycleFunc TeardownFunc;

    public this(String name, BenchmarkFunc func, int iterations, int warmupCount, int measurementCount, String category, bool isBaseline, BenchmarkReportOptions reportOptions, BenchmarkMetadata metadata, BenchmarkLifecycleFunc setupFunc = null, BenchmarkLifecycleFunc teardownFunc = null)
    {
        Name = name;
        Func = func;
        Iterations = iterations;
        WarmupCount = warmupCount;
        MeasurementCount = measurementCount;
        Category = category;
        IsBaseline = isBaseline;
        ReportOptions = reportOptions;
        Metadata = metadata;
        SetupFunc = setupFunc;
        TeardownFunc = teardownFunc;
    }
}

static class BenchmarkRegistry
{
    public static List<BenchmarkEntry> Entries = new .() ~ delete _;

    private static void DisposeEntry(BenchmarkEntry entry)
    {
        delete entry.Func;
        delete entry.SetupFunc;
        delete entry.TeardownFunc;
        delete entry.Name;
        delete entry.Category;
        delete entry.ReportOptions.LinkedSet;
        delete entry.ReportOptions.ComparisonSet;
        delete entry.ReportOptions.ThroughputUnit;
        delete entry.Metadata.Suite;
        delete entry.Metadata.CaseName;
        delete entry.Metadata.DisplayName;
        delete entry.Metadata.Tags;
        delete entry.Metadata.Dimensions;
    }

    /// Registers a benchmark. The registry keeps its own copies of `name` and `category`, so string
    /// literals and temporaries are fine; it takes ownership of `func` (pass `new => Method`).
    public static void Register(StringView name, BenchmarkFunc func, int iterations = 1000, int warmupCount = 5, int measurementCount = 15, StringView category = default, bool isBaseline = false)
    {
        Register(new String(name), func, iterations, warmupCount, measurementCount, category.IsEmpty ? null : new String(category), isBaseline, .Default, .Default);
    }

    // The overloads taking String (not StringView) and report options or metadata take OWNERSHIP of every
    // string and delegate they are given: pass heap strings (new String(...)), never literals.
    public static void Register(String name, BenchmarkFunc func, int iterations, int warmupCount, int measurementCount, String category, bool isBaseline, BenchmarkReportOptions reportOptions)
    {
        Register(name, func, iterations, warmupCount, measurementCount, category, isBaseline, reportOptions, .Default);
    }

    public static void Register(String name, BenchmarkFunc func, int iterations, int warmupCount, int measurementCount, String category, bool isBaseline, BenchmarkReportOptions reportOptions, BenchmarkMetadata metadata)
    {
        Entries.Add(.(name, func, iterations, warmupCount, measurementCount, category, isBaseline, reportOptions, metadata));
    }

    public static void Register(String name, BenchmarkFunc func, int iterations, int warmupCount, int measurementCount, String category, bool isBaseline, BenchmarkReportOptions reportOptions, BenchmarkMetadata metadata, BenchmarkLifecycleFunc setupFunc, BenchmarkLifecycleFunc teardownFunc)
    {
        Entries.Add(.(name, func, iterations, warmupCount, measurementCount, category, isBaseline, reportOptions, metadata, setupFunc, teardownFunc));
    }

    /// Takes ownership of every string and delegate in the entry (heap strings only, never literals).
    public static void Register(BenchmarkEntry entry)
    {
        Entries.Add(entry);
    }

    public static void Clear()
    {
        for (int i < Entries.Count)
            DisposeEntry(Entries[i]);
        Entries.Clear();
    }

    public static void RetainByNameContains(StringView filter)
    {
        if (filter.Length == 0)
            return;

        for (int i = Entries.Count - 1; i >= 0; i--)
        {
            ref BenchmarkEntry entry = ref Entries[i];
            if (entry.Name.Contains(filter) ||
                (!String.IsNullOrEmpty(entry.Metadata.DisplayName) && entry.Metadata.DisplayName.Contains(filter)))
            {
                continue;
            }

            DisposeEntry(entry);
            Entries.RemoveAt(i);
        }
    }
}
