using System;
using System.Diagnostics;
using System.Collections;
using System.IO;

namespace BeefBench;

struct BenchmarkResult
{
    public String Name;
    public BenchmarkEntry Entry;
    public double Mean;
    public double Error;
    public double StdDev;
    public double Median;
    public bool HasThroughput;
    public String ThroughputUnit;
    public double ThroughputMean;
    public double ThroughputError;
    public double ThroughputStdDev;
    public double ThroughputMedian;

    public this(BenchmarkEntry entry, double mean, double error, double stdDev, double median, bool hasThroughput, String throughputUnit, double throughputMean, double throughputError, double throughputStdDev, double throughputMedian)
    {
        Name = entry.Name;
        Entry = entry;
        Mean = mean;
        Error = error;
        StdDev = stdDev;
        Median = median;
        HasThroughput = hasThroughput;
        ThroughputUnit = throughputUnit;
        ThroughputMean = throughputMean;
        ThroughputError = throughputError;
        ThroughputStdDev = throughputStdDev;
        ThroughputMedian = throughputMedian;
    }
}

struct MetricStats
{
    public double Mean;
    public double Error;
    public double StdDev;
    public double Median;

    public this(double mean, double error, double stdDev, double median)
    {
        Mean = mean;
        Error = error;
        StdDev = stdDev;
        Median = median;
    }
}

class BenchmarkRunner
{
    /// Heading of the live table; applications set their own name.
    public static StringView Title = "BeefBench";

    /// Where RunAll writes the results table; an empty path writes no file.
    public static StringView CsvPath = "benchmark_results.csv";

    public static void RunAll(bool useTui = true)
    {
        PrintHeader();

        List<BenchmarkResult> results = scope .();
        let stopwatch = scope Stopwatch();

        if (useTui)
        {
            RunWithTui(results, stopwatch);
        }
        else
        {
            RunPlainText(results, stopwatch);
        }

        PrintTable(results);
        PrintThroughputTable(results);
        PrintComparisons(results);
        WriteResultsCsv(results);
    }

    private static void WriteResultsCsv(List<BenchmarkResult> results)
    {
        String csv = scope .();
        csv.Append("Name,DisplayName,Suite,CaseName,Category,Tags,Dimensions,MeanNs,ErrorNs,StdDevNs,MedianNs,HasThroughput,ThroughputUnit,ThroughputMean,ThroughputError,ThroughputStdDev,ThroughputMedian\n");

        for (let result in results)
        {
            csv.Append('"');
            csv.Append(result.Name);
            csv.Append("\",\"");
            csv.Append(GetDisplayName(result));
            csv.Append("\",\"");
            csv.Append(result.Entry.Metadata.Suite ?? "");
            csv.Append("\",\"");
            csv.Append(result.Entry.Metadata.CaseName ?? "");
            csv.Append("\",\"");
            csv.Append(result.Entry.Category ?? "");
            csv.Append("\",\"");
            csv.Append(result.Entry.Metadata.Tags ?? "");
            csv.Append("\",\"");
            csv.Append(result.Entry.Metadata.Dimensions ?? "");
            csv.Append("\",");
            csv.AppendF($"{result.Mean:F4},{result.Error:F4},{result.StdDev:F4},{result.Median:F4},");
            csv.Append(result.HasThroughput ? "true," : "false,");
            csv.Append('"');
            csv.Append(result.ThroughputUnit ?? "");
            csv.Append("\",");
            csv.AppendF($"{result.ThroughputMean:F4},{result.ThroughputError:F4},{result.ThroughputStdDev:F4},{result.ThroughputMedian:F4}\n");
        }

        if (!CsvPath.IsEmpty)
            File.WriteAllText(CsvPath, csv).IgnoreError();
    }

    private static void RunWithTui(List<BenchmarkResult> results, Stopwatch stopwatch)
    {
        Cursor.Hide();

        let logWindow = scope LogWindow(5);
        let progressBar = scope ProgressBar();

        // Reserve space
        for (int i = 0; i < 5; i++)
            Console.WriteLine();
        Console.WriteLine(); // For progress bar
        Cursor.Up(1); // Move to progress bar line

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
    }

    private static void RunPlainText(List<BenchmarkResult> results, Stopwatch stopwatch)
    {
        int total = BenchmarkRegistry.Entries.Count;
        int current = 0;

        for (let entry in BenchmarkRegistry.Entries)
        {
            results.Add(RunBenchmark(entry, stopwatch));
            let meanNs = results[results.Count - 1].Mean;
            String meanStr = scope String();
            if (meanNs >= 1000000.0)
                meanStr.AppendF($"{meanNs / 1000000.0:F3} ms");
            else if (meanNs >= 1000.0)
                meanStr.AppendF($"{meanNs / 1000.0:F3} us");
            else
                meanStr.AppendF($"{meanNs:F2} ns");
            Console.WriteLine($"[{++current}/{total}] {entry.Name} ({entry.Iterations * entry.MeasurementCount}×): {meanStr}");
        }

        Console.WriteLine();
    }

    private static void PrintHeader()
    {
        Console.WriteLine(scope String()..Append(Ansi.Reset)); // Ensure reset
        
        String s = scope .();
        Ansi.Color(s, Theme.Primary);
        s.Append(Ansi.Bold);
        s.Append(Title);
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
        Dictionary<String, List<BenchmarkResult>> categories = scope .();
        List<List<BenchmarkResult>> lists = scope .();

        for (let res in results)
        {
            String comparisonSet = res.Entry.ReportOptions.ComparisonSet;
            if (String.IsNullOrEmpty(comparisonSet))
                continue;

            if (!categories.ContainsKey(comparisonSet))
            {
                let list = new List<BenchmarkResult>();
                lists.Add(list);
                categories[comparisonSet] = list;
            }
            categories[comparisonSet].Add(res);
        }

        defer {
            for (let list in lists)
                delete list;
        }

        if (categories.Count == 0)
        {
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

            if (!baselineRes.HasValue)
                continue;

            let b = baselineRes.Value;

            for (let c in entries)
            {
                if (c.Entry.IsBaseline)
                    continue;

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
        if (entry.SetupFunc != null)
            entry.SetupFunc();
        defer
        {
            if (entry.TeardownFunc != null)
                entry.TeardownFunc();
        }

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
        List<double> timePerOpNs = scope .();
        List<double> throughputPerSecond = scope .();

        bool hasThroughput = entry.ReportOptions.EnableThroughput &&
            entry.ReportOptions.ThroughputWorkPerIteration > 0 &&
            !String.IsNullOrEmpty(entry.ReportOptions.ThroughputUnit);

        for (let m in measurements)
        {
            double nsPerOp = (m / entry.Iterations) * 1000000.0;
            timePerOpNs.Add(nsPerOp);

            if (hasThroughput)
            {
                double throughput = 0;
                if (nsPerOp > 0)
                    throughput = (entry.ReportOptions.ThroughputWorkPerIteration * 1000000000.0) / nsPerOp;
                throughputPerSecond.Add(throughput);
            }
        }

        MetricStats timeStats = CalculateMetricStats(timePerOpNs);
        MetricStats throughputStats = .(0, 0, 0, 0);
        if (hasThroughput)
            throughputStats = CalculateMetricStats(throughputPerSecond);

        return .(entry,
            timeStats.Mean,
            timeStats.Error,
            timeStats.StdDev,
            timeStats.Median,
            hasThroughput,
            entry.ReportOptions.ThroughputUnit,
            throughputStats.Mean,
            throughputStats.Error,
            throughputStats.StdDev,
            throughputStats.Median);
    }

    private static MetricStats CalculateMetricStats(List<double> values)
    {
        if (values.Count == 0)
            return .(0, 0, 0, 0);

        double total = 0;
        for (let value in values)
            total += value;

        double mean = total / values.Count;

        double stdDev = 0;
        if (values.Count > 1)
        {
            double sumSquares = 0;
            for (let value in values)
            {
                double diff = value - mean;
                sumSquares += diff * diff;
            }
            stdDev = Math.Sqrt(sumSquares / (values.Count - 1));
        }

        double error = stdDev / Math.Sqrt(values.Count);

        values.Sort();
        double median = values[values.Count / 2];

        return .(mean, error, stdDev, median);
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

        List<BenchmarkResult> ordered = scope .();
        BuildOrderedResults(results, ordered, false);

        for (let res in ordered)
        {
            String method = scope String();
            Ansi.Color(method, Theme.Primary);
            method.Append(GetDisplayName(res));
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

    private static void PrintThroughputTable(List<BenchmarkResult> results)
    {
        List<BenchmarkResult> throughputResults = scope .();
        for (let res in results)
        {
            if (res.HasThroughput)
                throughputResults.Add(res);
        }

        if (throughputResults.Count == 0)
            return;

        Console.WriteLine();

        String throughputHeader = scope .();
        Ansi.Color(throughputHeader, Theme.Secondary);
        throughputHeader.Append("Throughput");
        throughputHeader.Append(Ansi.Reset);
        Console.WriteLine(throughputHeader);

        let table = scope Table();
        table.AddColumn("Method");
        table.AddColumn("Mean", true);
        table.AddColumn("Error", true);
        table.AddColumn("StdDev", true);
        table.AddColumn("Median", true);

        List<BenchmarkResult> ordered = scope .();
        BuildOrderedResults(throughputResults, ordered, true);

        for (let res in ordered)
        {
            String method = scope String();
            Ansi.Color(method, Theme.Primary);
            method.Append(GetDisplayName(res));
            method.Append(Ansi.Reset);

            String mean = FormatThroughput(res.ThroughputMean, res.ThroughputUnit);
            String error = FormatThroughput(res.ThroughputError, res.ThroughputUnit);
            String stdDev = FormatThroughput(res.ThroughputStdDev, res.ThroughputUnit);
            String median = FormatThroughput(res.ThroughputMedian, res.ThroughputUnit);

            table.AddRow(method, mean, error, stdDev, median);

            delete mean;
            delete error;
            delete stdDev;
            delete median;
        }

        table.Render();
    }

    private static void BuildOrderedResults(List<BenchmarkResult> source, List<BenchmarkResult> output, bool sortForThroughput)
    {
        Dictionary<String, List<BenchmarkResult>> linkedSets = scope .();
        List<List<BenchmarkResult>> linkedSetLists = scope .();
        HashSet<String> emittedSets = scope .();

        for (let res in source)
        {
            String linkedSet = res.Entry.ReportOptions.LinkedSet;
            if (!res.Entry.ReportOptions.SortByPerformance || String.IsNullOrEmpty(linkedSet))
                continue;

            if (!linkedSets.ContainsKey(linkedSet))
            {
                let list = new List<BenchmarkResult>();
                linkedSetLists.Add(list);
                linkedSets[linkedSet] = list;
            }

            linkedSets[linkedSet].Add(res);
        }

        defer {
            for (let list in linkedSetLists)
                delete list;
        }

        for (let res in source)
        {
            String linkedSet = res.Entry.ReportOptions.LinkedSet;
            if (!res.Entry.ReportOptions.SortByPerformance || String.IsNullOrEmpty(linkedSet))
            {
                output.Add(res);
                continue;
            }

            if (emittedSets.Contains(linkedSet))
                continue;

            emittedSets.Add(linkedSet);
            let setResults = linkedSets[linkedSet];
            SortResultsByPerformance(setResults, sortForThroughput);

            for (let setRes in setResults)
                output.Add(setRes);
        }
    }

    private static void SortResultsByPerformance(List<BenchmarkResult> results, bool sortForThroughput)
    {
        bool higherIsBetter = sortForThroughput;

        for (int i = 0; i < results.Count; i++)
        {
            int bestIndex = i;
            double bestMetric = GetPerformanceMetric(results[i], sortForThroughput);

            for (int j = i + 1; j < results.Count; j++)
            {
                double metric = GetPerformanceMetric(results[j], sortForThroughput);
                if (higherIsBetter)
                {
                    if (metric > bestMetric)
                    {
                        bestMetric = metric;
                        bestIndex = j;
                    }
                }
                else
                {
                    if (metric < bestMetric)
                    {
                        bestMetric = metric;
                        bestIndex = j;
                    }
                }
            }

            if (bestIndex != i)
            {
                BenchmarkResult temp = results[i];
                results[i] = results[bestIndex];
                results[bestIndex] = temp;
            }
        }
    }

    private static double GetPerformanceMetric(BenchmarkResult result, bool sortForThroughput)
    {
        if (sortForThroughput)
            return result.ThroughputMean;
        return result.Mean;
    }

    private static String FormatTime(double ns)
    {
        if (ns >= 1000000000.0)
            return new String()..AppendF($"{ns / 1000000000.0:F4} s");
        if (ns >= 1000000.0)
            return new String()..AppendF($"{ns / 1000000.0:F4} ms");
        if (ns >= 1000.0)
            return new String()..AppendF($"{ns / 1000.0:F4} us");
        return new String()..AppendF($"{ns:F4} ns");
    }

    private static String FormatThroughput(double throughput, String unit)
    {
        String throughputUnit = String.IsNullOrEmpty(unit) ? "ops/s" : unit;

        if (throughput >= 1000000000.0)
            return new String()..AppendF($"{throughput / 1000000000.0:F4} G {throughputUnit}");
        if (throughput >= 1000000.0)
            return new String()..AppendF($"{throughput / 1000000.0:F4} M {throughputUnit}");
        if (throughput >= 1000.0)
            return new String()..AppendF($"{throughput / 1000.0:F4} K {throughputUnit}");
        return new String()..AppendF($"{throughput:F4} {throughputUnit}");
    }

    private static StringView GetDisplayName(BenchmarkResult result)
    {
        if (!String.IsNullOrEmpty(result.Entry.Metadata.DisplayName))
            return result.Entry.Metadata.DisplayName;
        return result.Name;
    }
}
