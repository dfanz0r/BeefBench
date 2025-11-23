using System;
using System.Collections;

namespace Benchmarks.Framework;

delegate void BenchmarkFunc();

struct BenchmarkEntry
{
    public String Name;
    public BenchmarkFunc Func;
    public int WarmupCount;
    public int MeasurementCount;
    public int Iterations;
    public String Category;
    public bool IsBaseline;

    public this(String name, BenchmarkFunc func, int iterations, int warmupCount, int measurementCount, String category, bool isBaseline)
    {
        Name = name;
        Func = func;
        Iterations = iterations;
        WarmupCount = warmupCount;
        MeasurementCount = measurementCount;
        Category = category;
        IsBaseline = isBaseline;
    }
}

static class BenchmarkRegistry
{
    public static List<BenchmarkEntry> Entries = new .() ~ delete _;

    public static void Register(String name, BenchmarkFunc func, int iterations = 1000, int warmupCount = 5, int measurementCount = 15, String category = null, bool isBaseline = false)
    {
        Entries.Add(.(name, func, iterations, warmupCount, measurementCount, category, isBaseline));
    }

    public static void Clear()
    {
        for (let entry in Entries)
        {
            delete entry.Func;
        }
        Entries.Clear();
    }
}
