using System;
using System.Diagnostics;
using System.Collections;

namespace Benchmarks.Framework;

struct BenchmarkResult
{
    public String Name;
    public BenchmarkEntry Entry;
    public double Mean;
    public double Error;
    public double StdDev;
    public double Median;

    public this(BenchmarkEntry entry, double mean, double error, double stdDev, double median)
    {
        Name = entry.Name;
        Entry = entry;
        Mean = mean;
        Error = error;
        StdDev = stdDev;
        Median = median;
    }
}

class BenchmarkRunner
{
    public static void RunAll()
    {
        PrintHeader();
        
        Cursor.Hide();

        let logWindow = scope LogWindow(5);
        let progressBar = scope ProgressBar();

        // Reserve space
        for (int i = 0; i < 5; i++) Console.WriteLine();
        Console.WriteLine(); // For progress bar
        Cursor.Up(1); // Move to progress bar line

        List<BenchmarkResult> results = scope .();
        let stopwatch = scope Stopwatch();

        int total = BenchmarkRegistry.Entries.Count;
        int current = 0;

        for (let entry in BenchmarkRegistry.Entries)
        {
            logWindow.AddLine(scope String()..AppendF($"Running {entry.Name}..."));
            RenderUI(logWindow, progressBar, (double)current / total, entry.Name);

            results.Add(RunBenchmark(entry, stopwatch));

            logWindow.ReplaceLastLine(scope String()..AppendF($"Running {entry.Name}... Done."));
            current++;
            RenderUI(logWindow, progressBar, (double)current / total, entry.Name);
        }
        
        RenderUI(logWindow, progressBar, 1.0, "Complete");
        Cursor.Show();
        Console.WriteLine();

        PrintTable(results);
        PrintComparisons(results);
    }

    private static void PrintHeader()
    {
        Console.WriteLine(scope String()..Append(Ansi.Reset)); // Ensure reset
        
        String s = scope .();
        
        Ansi.Color(s, Theme.Primary);
        s.Append("   _____ _         _      ____                  _     \n");
        s.Append("  / ____(_)       | |    |  _ \\                | |    \n");
        s.Append(Ansi.Reset);
        
        Ansi.Color(s, Theme.Secondary);
        s.Append(" | (___  _ _______| | ___| |_) | ___ _ __   ___| |__  \n");
        s.Append("  \\___ \\| |_  /_  / |/ _ \\  _ < / _ \\ '_ \\ / __| '_ \\ \n");
        s.Append(Ansi.Reset);
        
        Ansi.Color(s, Theme.Success);
        s.Append("  ____) | |/ / / /| |  __/ |_) |  __/ | | | (__| | | |\n");
        s.Append(" |_____/|_/___/___|_|\\___|____/ \\___|_| |_|\\___|_| |_|\n");
        s.Append(Ansi.Reset);
        
        Console.WriteLine(s);
        Console.WriteLine();
    }

    private static void RenderUI(LogWindow log, ProgressBar bar, double progress, StringView status)
    {
        Cursor.ClearLine();
        Cursor.Up(5);
        log.Render();
        bar.Render(progress, status);
    }

    private static void PrintComparisons(List<BenchmarkResult> results)
    {
        // Group by Category
        Dictionary<String, List<BenchmarkResult>> categories = scope .();
        List<List<BenchmarkResult>> lists = scope .();

        for (let res in results)
        {
            if (String.IsNullOrEmpty(res.Entry.Category)) continue;

            if (!categories.ContainsKey(res.Entry.Category))
            {
                let list = new List<BenchmarkResult>();
                lists.Add(list);
                categories[res.Entry.Category] = list;
            }
            categories[res.Entry.Category].Add(res);
        }

        defer {
            for (let list in lists) delete list;
        }

        if (categories.Count == 0)
        {
            // Console.WriteLine("No comparisons found (no categories defined).");
            return;
        }

        Console.WriteLine();
        String compHeader = scope .();
        Ansi.Color(compHeader, Theme.Secondary);
        compHeader.Append("Comparisons");
        compHeader.Append(Ansi.Reset);
        Console.WriteLine(compHeader);

        let table = scope Table();
        table.AddColumn("Category");
        table.AddColumn("Baseline");
        table.AddColumn("Candidate");
        table.AddColumn("Speedup", true);

        for (let kv in categories)
        {
            let category = kv.key;
            let entries = kv.value;

            BenchmarkResult? baselineRes = null;
            for (let res in entries)
            {
                if (res.Entry.IsBaseline)
                {
                    baselineRes = res;
                    break;
                }
            }

            if (!baselineRes.HasValue) continue;

            let b = baselineRes.Value;

            for (let c in entries)
            {
                if (c.Entry.IsBaseline) continue;

                double speedup = b.Mean / c.Mean;
                
                String speedupStr = scope String()..AppendF($"{speedup:F2}x");
                String coloredSpeedup = scope String();
                if (speedup >= 1.0)
                    Ansi.Color(coloredSpeedup, Theme.Success);
                else
                    Ansi.Color(coloredSpeedup, Theme.Secondary);
                
                coloredSpeedup.Append(speedupStr);
                coloredSpeedup.Append(Ansi.Reset);

                table.AddRow(category, b.Name, c.Name, coloredSpeedup);
            }
        }

        table.Render();
    }

    private static BenchmarkResult RunBenchmark(BenchmarkEntry entry, Stopwatch stopwatch)
    {
        // Warmup
        for (int i < entry.WarmupCount)
        {
            stopwatch.Restart();
            for (int j < entry.Iterations)
            {
                entry.Func();
            }
            stopwatch.Stop();
        }

        // Measurements
        List<double> measurements = scope .();
        for (int i < entry.MeasurementCount)
        {
            stopwatch.Restart();
            for (int j < entry.Iterations)
            {
                entry.Func();
            }
            stopwatch.Stop();
            measurements.Add(stopwatch.Elapsed.TotalMilliseconds);
        }

        return CalculateStats(entry, measurements);
    }

    private static BenchmarkResult CalculateStats(BenchmarkEntry entry, List<double> measurements)
    {
        double total = 0;
        for (let m in measurements) total += m;
        double meanTotal = total / measurements.Count;
        double meanPerOp = (meanTotal / entry.Iterations) * 1000000.0; // Convert to ns

        double sumSquares = 0;
        for (let m in measurements)
        {
            double diff = (m / entry.Iterations * 1000000.0) - meanPerOp;
            sumSquares += diff * diff;
        }
        double stdDev = Math.Sqrt(sumSquares / (measurements.Count - 1));
        double error = stdDev / Math.Sqrt(measurements.Count); // Standard Error

        measurements.Sort();
        double medianTotal = measurements[measurements.Count / 2];
        double medianPerOp = (medianTotal / entry.Iterations) * 1000000.0;

        return .(entry, meanPerOp, error, stdDev, medianPerOp);
    }

    private static void PrintTable(List<BenchmarkResult> results)
    {
        Console.WriteLine();

        let table = scope Table();
        table.AddColumn("Method");
        table.AddColumn("Mean", true);
        table.AddColumn("Error", true);
        table.AddColumn("StdDev", true);
        table.AddColumn("Median", true);

        for (let res in results)
        {
            String method = scope String();
            Ansi.Color(method, Theme.Primary);
            method.Append(res.Name);
            method.Append(Ansi.Reset);

            String mean = FormatTime(res.Mean);
            String error = FormatTime(res.Error);
            String stdDev = FormatTime(res.StdDev);
            String median = FormatTime(res.Median);

            table.AddRow(method, mean, error, stdDev, median);
            
            delete mean;
            delete error;
            delete stdDev;
            delete median;
        }

        table.Render();
    }

    private static String FormatTime(double ns)
    {
        if (ns >= 1000000000.0) return new String()..AppendF($"{ns / 1000000000.0:F4} s");
        if (ns >= 1000000.0) return new String()..AppendF($"{ns / 1000000.0:F4} ms");
        if (ns >= 1000.0) return new String()..AppendF($"{ns / 1000.0:F4} us");
        return new String()..AppendF($"{ns:F4} ns");
    }
}
