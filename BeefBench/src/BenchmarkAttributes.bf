using System;
using System.Collections;

namespace Benchmarks.Framework;

[AttributeUsage(.Class)]
struct BenchmarkSuiteAttribute : Attribute, IOnTypeInit
{
    public StringView SuiteName;

    public this(StringView suiteName)
    {
        SuiteName = suiteName;
    }

    [Comptime]
    public void OnTypeInit(Type type, Self* prev)
    {
        String suiteName = scope .(SuiteName);
        String generated = scope .();
        generated.AppendF($"public static StringView GeneratedBenchmarkSuiteName => \"{suiteName}\";\n");
        Compiler.EmitTypeBody(type, generated);
    }
}

[AttributeUsage(.Method)]
struct BenchmarkCaseAttribute : Attribute
{
    public StringView CaseName;
    public StringView Category;
    public StringView Model;
    public bool Scaling;

    public this(StringView caseName, StringView category = null, StringView model = null, bool scaling = false)
    {
        CaseName = caseName;
        Category = category;
        Model = model;
        Scaling = scaling;
    }
}

[AttributeUsage(.Method)]
struct BenchmarkVariantsAttribute : Attribute
{
    public StringView DimensionName;
    public StringView CsvValues;

    public this(StringView dimensionName, StringView csvValues)
    {
        DimensionName = dimensionName;
        CsvValues = csvValues;
    }

    [Comptime]
    public List<String> GetValues()
    {
        List<String> values = scope .();
        String current = scope .();
        for (char8 c in CsvValues)
        {
            if (c == ',')
            {
                AddTrimmed(values, current);
                current.Clear();
                continue;
            }

            current.Append(c);
        }

        AddTrimmed(values, current);
        return values;
    }

    [Comptime]
    private static void AddTrimmed(List<String> values, String current)
    {
        int start = 0;
        while (start < current.Length && current[start].IsWhiteSpace)
            start++;

        int end = current.Length - 1;
        while (end >= start && current[end].IsWhiteSpace)
            end--;

        if (end < start)
            return;

        values.Add(new .(current.Substring(start, end - start + 1)));
    }
}

[AttributeUsage(.Method)]
struct BenchmarkRangeAttribute : Attribute
{
    public StringView DimensionName;
    public int32 StartInclusive;
    public int32 EndInclusive;

    public this(StringView dimensionName, int32 startInclusive, int32 endInclusive)
    {
        DimensionName = dimensionName;
        StartInclusive = startInclusive;
        EndInclusive = endInclusive;
    }
}

[AttributeUsage(.Class)]
struct GenerateBenchmarkRegistrationsAttribute : Attribute, IOnTypeInit
{
    [Comptime]
    public void OnTypeInit(Type type, Self* prev)
    {
        String suiteName = scope .("benchmarks");

        String generated = scope .();
        generated.Append("public static void GeneratedRegisterBenchmarks()\n{\n");
        generated.Append(scope $"    let suite = scope Benchmarks.Framework.BenchmarkSuiteBuilder(\"{suiteName}\");\n");
        generated.Append("    suite.Iterations(1);\n");
        generated.Append("    suite.WarmupCount(3);\n");
        generated.Append("    suite.MeasurementCount(15);\n");
        generated.Append("}\n");
        Compiler.EmitTypeBody(type, generated);
    }
}

[AttributeUsage(.Class)]
// NOTE: Use a unique generic id per generated family on a type. This keeps
// emitted helper implementation names deterministic and avoids collisions.
struct GenerateVariantBenchmarkFamilyAttribute<TId> : Attribute, IOnTypeInit where TId : const int32
{
    public StringView GeneratedMethodName;
    public StringView CaseName;
    public StringView Category;
    public StringView Model;
    public StringView ThroughputExpression;
    public StringView BenchmarkNamePrefix;
    public StringView BenchmarkMethodPrefix;
    public StringView CsvVariants;
    public int32 BaselineIndex;
    public bool Scaling;

    public this(StringView generatedMethodName, StringView caseName, StringView category, StringView model, StringView throughputExpression, StringView benchmarkNamePrefix, StringView benchmarkMethodPrefix, StringView csvVariants, int32 baselineIndex = -1, bool scaling = false)
    {
        GeneratedMethodName = generatedMethodName;
        CaseName = caseName;
        Category = category;
        Model = model;
        ThroughputExpression = throughputExpression;
        BenchmarkNamePrefix = benchmarkNamePrefix;
        BenchmarkMethodPrefix = benchmarkMethodPrefix;
        CsvVariants = csvVariants;
        BaselineIndex = baselineIndex;
        Scaling = scaling;
    }

    [Comptime]
    public void OnTypeInit(Type type, Self* prev)
    {
        String methodName = scope .();
        methodName.Append("__GeneratedBenchmarkFamilyImpl_");
        methodName.AppendF($"{TId}");

        String generated = scope .();
        generated.AppendF($"private static void {methodName}()\n{{\n");
        generated.AppendF($"    let benchmarkCase = CreateAtomicQueueCase(\"{CaseName}\", \"{Category}\", \"{Model}\", {ThroughputExpression}, {(Scaling ? "true" : "false")});\n");
        generated.Append("    defer delete benchmarkCase;\n");

        String current = scope .();
        int32 variantIndex = 0;
        for (char8 c in CsvVariants)
        {
            if (c == ',')
            {
                EmitVariant(generated, current, variantIndex++);
                current.Clear();
                continue;
            }

            current.Append(c);
        }

        EmitVariant(generated, current, variantIndex);

        generated.Append("}\n");
        generated.AppendF($"private static void {GeneratedMethodName}() => {methodName}();\n");
        Compiler.EmitTypeBody(type, generated);
    }

    [Comptime]
    private void EmitVariant(String generated, String current, int32 variantIndex)
    {
        String trimmed = scope .();
        AppendTrimmed(trimmed, current);
        if (trimmed.Length == 0)
            return;

        bool isBaseline = variantIndex == BaselineIndex;
        generated.AppendF($"    benchmarkCase.RegisterVariant(\"{BenchmarkNamePrefix}{trimmed}\", new => {BenchmarkMethodPrefix}{trimmed}, {(isBaseline ? "true" : "false")});\n");
    }

    [Comptime]
    private static void AppendTrimmed(String output, String current)
    {
        int start = 0;
        while (start < current.Length && current[start].IsWhiteSpace)
            start++;

        int end = current.Length - 1;
        while (end >= start && current[end].IsWhiteSpace)
            end--;

        if (end < start)
            return;

        output.Append(current.Substring(start, end - start + 1));
    }
}

[AttributeUsage(.Class)]
// Emits a generated family-registration method that calls an existing runtime
// scaling helper for each listed variant.
struct GenerateScalingBenchmarkFamiliesAttribute<TId> : Attribute, IOnTypeInit where TId : const int32
{
    public StringView GeneratedMethodName;
    public StringView HelperMethodName;
    public StringView CsvVariants;
    public int32 BaselineIndex;

    public this(StringView generatedMethodName, StringView helperMethodName, StringView csvVariants, int32 baselineIndex = -1)
    {
        GeneratedMethodName = generatedMethodName;
        HelperMethodName = helperMethodName;
        CsvVariants = csvVariants;
        BaselineIndex = baselineIndex;
    }

    [Comptime]
    public void OnTypeInit(Type type, Self* prev)
    {
        String methodName = scope .();
        methodName.Append("__GeneratedScalingFamiliesImpl_");
        methodName.AppendF($"{TId}");

        String generated = scope .();
        generated.AppendF($"private static void {methodName}()\n{{\n");

        String current = scope .();
        int32 variantIndex = 0;
        for (char8 c in CsvVariants)
        {
            if (c == ',')
            {
                EmitVariant(generated, current, variantIndex++);
                current.Clear();
                continue;
            }

            current.Append(c);
        }

        EmitVariant(generated, current, variantIndex);
        generated.Append("}\n");
        generated.AppendF($"private static void {GeneratedMethodName}() => {methodName}();\n");
        Compiler.EmitTypeBody(type, generated);
    }

    [Comptime]
    private void EmitVariant(String generated, String current, int32 variantIndex)
    {
        String trimmed = scope .();
        AppendTrimmed(trimmed, current);
        if (trimmed.Length == 0)
            return;

        bool isBaseline = variantIndex == BaselineIndex;
        generated.AppendF($"    {HelperMethodName}(\"{trimmed}\", .{trimmed}, {(isBaseline ? "true" : "false")});\n");
    }

    [Comptime]
    private static void AppendTrimmed(String output, String current)
    {
        int start = 0;
        while (start < current.Length && current[start].IsWhiteSpace)
            start++;

        int end = current.Length - 1;
        while (end >= start && current[end].IsWhiteSpace)
            end--;

        if (end < start)
            return;

        output.Append(current.Substring(start, end - start + 1));
    }
}

[AttributeUsage(.Class)]
// Convenience wrapper that emits the full AtomicQueue base-family registration set.
struct GenerateAtomicQueueBaseFamiliesAttribute : Attribute, IOnTypeInit
{
    [Comptime]
    public void OnTypeInit(Type type, Self* prev)
    {
        String generated = scope .();
        EmitVariantFamily(generated, "GeneratedRegisterSpscFamily", "__GeneratedBenchmarkFamilyImpl_101", "spsc", "AtomicQueue_SPSC", "SPSC", "BenchmarkMessages", "beef,spsc,", "BenchmarkSpsc_", "AtomicQueue,AtomicQueueB,OptimistAtomicQueue,OptimistAtomicQueueB,AtomicQueue2,AtomicQueueB2,OptimistAtomicQueue2,OptimistAtomicQueueB2,QueueSPSC,OptimistQueueSPSC", 0);
        EmitVariantFamily(generated, "GeneratedRegisterMpmcFamily", "__GeneratedBenchmarkFamilyImpl_102", "mpmc", "AtomicQueue_MPMC", "MPMC", "BenchmarkMessages", "beef,mpmc,", "BenchmarkMpmc_", "LockBasedQueue,AtomicQueue,AtomicQueueB,OptimistAtomicQueue,OptimistAtomicQueueB,AtomicQueue2,AtomicQueueB2,OptimistAtomicQueue2,OptimistAtomicQueueB2,QueueMPMC,OptimistQueueMPMC,QueueMPMCCell,OptimistQueueMPMCCell,OptimizedQueueMPMC,OptimistOptimizedQueueMPMC,HyperQueueMPMC,OptimistHyperQueueMPMC,BlazeQueueMPMC,OptimistBlazeQueueMPMC", 0);
        EmitVariantFamily(generated, "GeneratedRegisterMpscFamily", "__GeneratedBenchmarkFamilyImpl_103", "mpsc", "AtomicQueue_MPSC", "MPSC", "BenchmarkMessages", "beef,mpsc,", "BenchmarkMpsc_", "LockBasedQueue,AtomicQueue,AtomicQueueB,AtomicQueue2,OptimistAtomicQueue,OptimistAtomicQueueB,OptimistAtomicQueue2,AtomicQueueB2,OptimistAtomicQueueB2,QueueMPMC,OptimistQueueMPMC,QueueMPMCCell,OptimistQueueMPMCCell,OptimizedQueueMPMC,OptimistOptimizedQueueMPMC,HyperQueueMPMC,OptimistHyperQueueMPMC,BlazeQueueMPMC,OptimistBlazeQueueMPMC,AtomicQueueMutex,OptimistAtomicQueueMutex,AtomicQueueMutexB,OptimistAtomicQueueMutexB,SimpleAtomicQueueB2,SimpleOptimistAtomicQueueB2", 0);
        Compiler.EmitTypeBody(type, generated);
    }

    [Comptime]
    private static void EmitVariantFamily(String generated, StringView wrapperName, StringView implName, StringView caseName, StringView category, StringView model, StringView throughputExpr, StringView namePrefix, StringView methodPrefix, StringView csvVariants, int32 baselineIndex)
    {
        generated.AppendF($"private static void {implName}()\n{{\n");
        generated.AppendF($"    let benchmarkCase = CreateAtomicQueueCase(\"{caseName}\", \"{category}\", \"{model}\", {throughputExpr}, false);\n");
        generated.Append("    defer delete benchmarkCase;\n");
        EmitVariantLines(generated, namePrefix, methodPrefix, csvVariants, baselineIndex);
        generated.Append("}\n");
        generated.AppendF($"private static void {wrapperName}() => {implName}();\n");
    }

    [Comptime]
    private static void EmitVariantLines(String generated, StringView benchmarkNamePrefix, StringView benchmarkMethodPrefix, StringView csvVariants, int32 baselineIndex)
    {
        String current = scope .();
        int32 variantIndex = 0;
        for (char8 c in csvVariants)
        {
            if (c == ',')
            {
                EmitOneVariantLine(generated, benchmarkNamePrefix, benchmarkMethodPrefix, current, variantIndex++ == baselineIndex);
                current.Clear();
                continue;
            }

            current.Append(c);
        }

        EmitOneVariantLine(generated, benchmarkNamePrefix, benchmarkMethodPrefix, current, variantIndex == baselineIndex);
    }

    [Comptime]
    private static void EmitOneVariantLine(String generated, StringView benchmarkNamePrefix, StringView benchmarkMethodPrefix, String current, bool isBaseline)
    {
        String trimmed = scope .();
        AppendTrimmedCsvValue(trimmed, current);
        if (trimmed.Length == 0)
            return;

        generated.AppendF($"    benchmarkCase.RegisterVariant(\"{benchmarkNamePrefix}{trimmed}\", new => {benchmarkMethodPrefix}{trimmed}, {(isBaseline ? "true" : "false")});\n");
    }

    [Comptime]
    private static void AppendTrimmedCsvValue(String output, String current)
    {
        int start = 0;
        while (start < current.Length && current[start].IsWhiteSpace)
            start++;

        int end = current.Length - 1;
        while (end >= start && current[end].IsWhiteSpace)
            end--;

        if (end < start)
            return;

        output.Append(current.Substring(start, end - start + 1));
    }
}

[AttributeUsage(.Class)]
// Convenience wrapper that emits the full AtomicQueue scaling-family registration set.
struct GenerateAtomicQueueScalingFamiliesAttribute : Attribute, IOnTypeInit
{
    [Comptime]
    public void OnTypeInit(Type type, Self* prev)
    {
        String generated = scope .();
        EmitScalingFamily(generated, "GeneratedRegisterMpmcScalingFamilies", "__GeneratedScalingFamiliesImpl_104", "RegisterMpmcScalingFamily", "LockBasedQueue,AtomicQueue,AtomicQueueB,AtomicQueue2,AtomicQueueB2,OptimistAtomicQueue,OptimistAtomicQueueB,OptimistAtomicQueue2,OptimistAtomicQueueB2,QueueMPMC,OptimistQueueMPMC,QueueMPMCCell,OptimistQueueMPMCCell,OptimizedQueueMPMC,OptimistOptimizedQueueMPMC,HyperQueueMPMC,OptimistHyperQueueMPMC,BlazeQueueMPMC,OptimistBlazeQueueMPMC", 0);
        EmitScalingFamily(generated, "GeneratedRegisterMpscScalingFamilies", "__GeneratedScalingFamiliesImpl_105", "RegisterMpscScalingFamily", "LockBasedQueue,AtomicQueue,AtomicQueueB,AtomicQueue2,OptimistAtomicQueue,OptimistAtomicQueueB,OptimistAtomicQueue2,AtomicQueueB2,OptimistAtomicQueueB2,QueueMPMC,OptimistQueueMPMC,QueueMPMCCell,OptimistQueueMPMCCell,OptimizedQueueMPMC,OptimistOptimizedQueueMPMC,HyperQueueMPMC,OptimistHyperQueueMPMC,BlazeQueueMPMC,OptimistBlazeQueueMPMC,AtomicQueueMutex,OptimistAtomicQueueMutex,AtomicQueueMutexB,OptimistAtomicQueueMutexB,SimpleAtomicQueueB2,SimpleOptimistAtomicQueueB2", 0);
        Compiler.EmitTypeBody(type, generated);
    }

    [Comptime]
    private static void EmitScalingFamily(String generated, StringView wrapperName, StringView implName, StringView helperName, StringView csvVariants, int32 baselineIndex)
    {
        generated.AppendF($"private static void {implName}()\n{{\n");
        EmitScalingLines(generated, helperName, csvVariants, baselineIndex);
        generated.Append("}\n");
        generated.AppendF($"private static void {wrapperName}() => {implName}();\n");
    }

    [Comptime]
    private static void EmitScalingLines(String generated, StringView helperName, StringView csvVariants, int32 baselineIndex)
    {
        String current = scope .();
        int32 variantIndex = 0;
        for (char8 c in csvVariants)
        {
            if (c == ',')
            {
                EmitOneScalingLine(generated, helperName, current, variantIndex++ == baselineIndex);
                current.Clear();
                continue;
            }

            current.Append(c);
        }

        EmitOneScalingLine(generated, helperName, current, variantIndex == baselineIndex);
    }

    [Comptime]
    private static void EmitOneScalingLine(String generated, StringView helperName, String current, bool isBaseline)
    {
        String trimmed = scope .();
        AppendTrimmedCsvValue(trimmed, current);
        if (trimmed.Length == 0)
            return;

        generated.AppendF($"    {helperName}(\"{trimmed}\", .{trimmed}, {(isBaseline ? "true" : "false")});\n");
    }

    [Comptime]
    private static void AppendTrimmedCsvValue(String output, String current)
    {
        int start = 0;
        while (start < current.Length && current[start].IsWhiteSpace)
            start++;

        int end = current.Length - 1;
        while (end >= start && current[end].IsWhiteSpace)
            end--;

        if (end < start)
            return;

        output.Append(current.Substring(start, end - start + 1));
    }
}

[AttributeUsage(.Class)]
// Emits the repetitive specialized scaling overload bodies that Beef cannot
// currently share cleanly through unconstrained generics.
struct GenerateAtomicQueueScalingOverloadsAttribute : Attribute, IOnTypeInit
{
    [Comptime]
    public void OnTypeInit(Type type, Self* prev)
    {
        String generated = scope .();
        EmitMpmcOverload(generated, "BlazeQueueMPMC<uint32, 65536>", false, false);
        EmitMpmcOverload(generated, "QueueMPMCCell<uint32, 65536>", true, false);
        EmitMpmcOverload(generated, "OptimizedQueueMPMC<uint32, 65536>", false, false);
        EmitMpmcOverload(generated, "HyperQueueMPMC<uint32, 65536>", false, false);
        EmitMpmcOverload(generated, "QueueMPMC<uint32, 65536>", false, false);
        EmitMpscOverload(generated, "AtomicQueueMutex<uint32, 65536>", false);
        EmitMpscOverload(generated, "AtomicQueueMutexB<uint32>", false);
        EmitMpscOverload(generated, "AtomicQueueSimpleB2<uint32>", true);
        Compiler.EmitTypeBody(type, generated);
    }

    [Comptime]
    private static void EmitMpmcOverload(String generated, StringView queueType, bool useSimplePause, bool useLockBasedLogic)
    {
        generated.AppendF($"private static void RunMpmcScaling({queueType} queue, bool retryMode, int32 producers, int32 consumers, int32 messagesPerProducer)\n{{\n");
        generated.Append("    Runtime.Assert(producers > 0);\n");
        generated.Append("    Runtime.Assert(consumers > 0);\n");
        generated.Append("    Runtime.Assert(messagesPerProducer > 0);\n\n");
        generated.Append("    uint64[] sums = new uint64[consumers];\n");
        generated.Append("    defer delete sums;\n\n");
        generated.Append("    QueueBenchmarkBarrier barrier = scope .();\n");
        generated.Append("    List<Thread> threads = scope .();\n\n");
        generated.Append("    for (int32 i < producers)\n    {\n");
        generated.Append("        Thread thread = new Thread(new [=]() =>\n            {\n");
        generated.Append("                barrier.Wait();\n                for (uint32 value = (uint32)messagesPerProducer; value > 0; value--)\n                {\n");
        generated.Append("                    if (retryMode)\n                    {\n                        while (!queue.TryPush(value))\n");
        generated.Append("                            Thread.SpinWait(1);\n");
        generated.Append("                    }\n                    else\n                        queue.Push(value);\n                }\n            });\n");
        generated.Append("        threads.Add(thread);\n        thread.Start(false);\n    }\n\n");
        generated.Append("    for (int32 i < consumers)\n    {\n        int32 consumerIndex = i;\n");
        generated.Append("        Thread thread = new Thread(new [=]() =>\n            {\n                barrier.Wait();\n                uint64 sum = 0;\n                for (;;)\n                {\n                    uint32 value;\n                    if (retryMode)\n                    {\n                        value = 0;\n                        while (!queue.TryPop(ref value))\n");
        generated.Append("                            Thread.SpinWait(1);\n");
        generated.Append("                    }\n                    else\n                        value = queue.Pop();\n\n                    if (value == StopMessage)\n                        break;\n\n                    sum += value;\n                }\n\n                sums[consumerIndex] = sum;\n            });\n");
        generated.Append("        threads.Add(thread);\n        thread.Start(false);\n    }\n\n");
        generated.Append("    barrier.Release((uint32)(producers + consumers));\n\n");
        generated.Append("    for (int32 i < producers)\n    {\n        threads[i].Join();\n        delete threads[i];\n    }\n\n");
        generated.Append("    for (int32 i < consumers)\n    {\n        if (retryMode)\n        {\n            while (!queue.TryPush(StopMessage))\n");
        generated.Append("                Thread.SpinWait(1);\n");
        generated.Append("        }\n        else\n            queue.Push(StopMessage);\n    }\n\n");
        generated.Append("    for (int32 i = producers; i < threads.Count; i++)\n    {\n        threads[i].Join();\n        delete threads[i];\n    }\n\n");
        generated.Append("    uint64 total = 0;\n    for (uint64 sum in sums)\n        total += sum;\n\n");
        generated.Append("    Runtime.Assert(total == ExpectedSum(messagesPerProducer, producers));\n}\n");
    }

    [Comptime]
    private static void EmitMpscOverload(String generated, StringView queueType, bool useSimplePause)
    {
        generated.AppendF($"private static void RunMpscScaling({queueType} queue, bool retryMode, int32 producers, int32 messagesPerProducer)\n{{\n");
        generated.Append("    uint64[] sums = new uint64[1];\n");
        generated.Append("    defer delete sums;\n\n");
        generated.Append("    QueueBenchmarkBarrier barrier = scope .();\n");
        generated.Append("    List<Thread> threads = scope .();\n\n");
        generated.Append("    for (int32 i < producers)\n    {\n");
        generated.Append("        Thread thread = new Thread(new [=]() =>\n            {\n                barrier.Wait();\n                for (uint32 value = (uint32)messagesPerProducer; value > 0; value--)\n                {\n                    if (retryMode)\n                    {\n                        while (!queue.TryPush(value))\n");
        generated.Append("                            Thread.SpinWait(1);\n");
        generated.Append("                    }\n                    else\n                        queue.Push(value);\n                }\n            });\n");
        generated.Append("        threads.Add(thread);\n        thread.Start(false);\n    }\n\n");
        generated.Append("        Thread consumer = new Thread(new [=]() =>\n        {\n            barrier.Wait();\n            uint64 sum = 0;\n            for (;;)\n            {\n                uint32 value;\n                if (retryMode)\n                {\n                    value = 0;\n                    while (!queue.TryPop(ref value))\n");
        generated.Append("                        Thread.SpinWait(1);\n");
        generated.Append("                }\n                else\n                    value = queue.Pop();\n\n                if (value == StopMessage)\n                    break;\n                sum += value;\n            }\n\n            sums[0] = sum;\n        });\n");
        generated.Append("    threads.Add(consumer);\n    consumer.Start(false);\n\n");
        generated.Append("    barrier.Release((uint32)(producers + 1));\n\n");
        generated.Append("    for (int32 i < producers)\n    {\n        threads[i].Join();\n        delete threads[i];\n    }\n\n");
        generated.Append("    if (retryMode)\n    {\n        while (!queue.TryPush(StopMessage))\n");
        generated.Append("            Thread.SpinWait(1);\n");
        generated.Append("    }\n    else\n        queue.Push(StopMessage);\n\n");
        generated.Append("    threads[producers].Join();\n    delete threads[producers];\n\n");
        generated.Append("    Runtime.Assert(sums[0] == ExpectedSum(messagesPerProducer, producers));\n}\n");
    }
}

[AttributeUsage(.Class)]
// Emits the verbose benchmark wrapper methods and target-dispatch methods so the
// benchmark file can focus on the core run loops.
struct GenerateAtomicQueueExecutionGlueAttribute : Attribute, IOnTypeInit
{
    [Comptime]
    public void OnTypeInit(Type type, Self* prev)
    {
        String generated = scope .();
        EmitScalingDispatchers(generated);
        EmitBenchmarkWrappers(generated);
        Compiler.EmitTypeBody(type, generated);
    }

    [Comptime]
    private static void EmitScalingDispatchers(String generated)
    {
        generated.Append("private static void BenchmarkMpmcScaling(ScalingTarget target, int32 threadCount, int32 messagesPerProducer)\n{\n    switch (target)\n    {\n");
        generated.Append("    case .LockBasedQueue: { let queue = new LockBasedQueue<uint32>(ThroughputSize); defer delete queue; RunMpmcScaling(queue, threadCount, threadCount, messagesPerProducer); }\n");
        generated.Append("    case .AtomicQueue: { let queue = new AtomicQueue<uint32, 65536, 3>(0U); defer delete queue; RunMpmcScaling(queue, true, threadCount, threadCount, messagesPerProducer); }\n");
        generated.Append("    case .AtomicQueueB: { let queue = new AtomicQueueB<uint32, 2>(ThroughputSize, 0U); defer delete queue; RunMpmcScaling(queue, true, threadCount, threadCount, messagesPerProducer); }\n");
        generated.Append("    case .AtomicQueue2: { let queue = new AtomicQueue2<uint32, 65536, 3>(); defer delete queue; RunMpmcScaling(queue, true, threadCount, threadCount, messagesPerProducer); }\n");
        generated.Append("    case .AtomicQueueB2: { let queue = new AtomicQueueB2<uint32, 2>(ThroughputSize); defer delete queue; RunMpmcScaling(queue, true, threadCount, threadCount, messagesPerProducer); }\n");
        generated.Append("    case .OptimistAtomicQueue: { let queue = new AtomicQueue<uint32, 65536, 3>(0U); defer delete queue; RunMpmcScaling(queue, false, threadCount, threadCount, messagesPerProducer); }\n");
        generated.Append("    case .OptimistAtomicQueueB: { let queue = new AtomicQueueB<uint32, 2>(ThroughputSize, 0U); defer delete queue; RunMpmcScaling(queue, false, threadCount, threadCount, messagesPerProducer); }\n");
        generated.Append("    case .OptimistAtomicQueue2: { let queue = new AtomicQueue2<uint32, 65536, 3>(); defer delete queue; RunMpmcScaling(queue, false, threadCount, threadCount, messagesPerProducer); }\n");
        generated.Append("    case .OptimistAtomicQueueB2: { let queue = new AtomicQueueB2<uint32, 2>(ThroughputSize); defer delete queue; RunMpmcScaling(queue, false, threadCount, threadCount, messagesPerProducer); }\n");
        generated.Append("    case .QueueMPMC: { let queue = new QueueMPMC<uint32, 65536>(); defer delete queue; RunMpmcScaling(queue, true, threadCount, threadCount, messagesPerProducer); }\n");
        generated.Append("    case .OptimistQueueMPMC: { let queue = new QueueMPMC<uint32, 65536>(); defer delete queue; RunMpmcScaling(queue, false, threadCount, threadCount, messagesPerProducer); }\n");
        generated.Append("    case .QueueMPMCCell: { let queue = new QueueMPMCCell<uint32, 65536>(); defer delete queue; RunMpmcScaling(queue, true, threadCount, threadCount, messagesPerProducer); }\n");
        generated.Append("    case .OptimistQueueMPMCCell: { let queue = new QueueMPMCCell<uint32, 65536>(); defer delete queue; RunMpmcScaling(queue, false, threadCount, threadCount, messagesPerProducer); }\n");
        generated.Append("    case .OptimizedQueueMPMC: { let queue = new OptimizedQueueMPMC<uint32, 65536>(); defer delete queue; RunMpmcScaling(queue, true, threadCount, threadCount, messagesPerProducer); }\n");
        generated.Append("    case .OptimistOptimizedQueueMPMC: { let queue = new OptimizedQueueMPMC<uint32, 65536>(); defer delete queue; RunMpmcScaling(queue, false, threadCount, threadCount, messagesPerProducer); }\n");
        generated.Append("    case .HyperQueueMPMC: { let queue = new HyperQueueMPMC<uint32, 65536>(); defer delete queue; RunMpmcScaling(queue, true, threadCount, threadCount, messagesPerProducer); }\n");
        generated.Append("    case .OptimistHyperQueueMPMC: { let queue = new HyperQueueMPMC<uint32, 65536>(); defer delete queue; RunMpmcScaling(queue, false, threadCount, threadCount, messagesPerProducer); }\n");
        generated.Append("    case .BlazeQueueMPMC: { let queue = new BlazeQueueMPMC<uint32, 65536>(); defer delete queue; RunMpmcScaling(queue, true, threadCount, threadCount, messagesPerProducer); }\n");
        generated.Append("    case .OptimistBlazeQueueMPMC: { let queue = new BlazeQueueMPMC<uint32, 65536>(); defer delete queue; RunMpmcScaling(queue, false, threadCount, threadCount, messagesPerProducer); }\n");
        generated.Append("    }\n}\n");

        generated.Append("private static void BenchmarkMpscScaling(MpscScalingTarget target, int32 producerCount, int32 messagesPerProducer)\n{\n    switch (target)\n    {\n");
        generated.Append("    case .LockBasedQueue: { let queue = new LockBasedQueue<uint32>(ThroughputSize); defer delete queue; RunMpscScaling(queue, producerCount, messagesPerProducer); }\n");
        generated.Append("    case .AtomicQueue: { let queue = new AtomicQueue<uint32, 65536, 3>(0U); defer delete queue; RunMpmcScaling(queue, true, producerCount, 1, messagesPerProducer); }\n");
        generated.Append("    case .AtomicQueueB: { let queue = new AtomicQueueB<uint32, 2>(ThroughputSize, 0U); defer delete queue; RunMpscScaling(queue, true, producerCount, messagesPerProducer); }\n");
        generated.Append("    case .AtomicQueue2: { let queue = new AtomicQueue2<uint32, 65536, 3>(); defer delete queue; RunMpmcScaling(queue, true, producerCount, 1, messagesPerProducer); }\n");
        generated.Append("    case .OptimistAtomicQueue: { let queue = new AtomicQueue<uint32, 65536, 3>(0U); defer delete queue; RunMpmcScaling(queue, false, producerCount, 1, messagesPerProducer); }\n");
        generated.Append("    case .OptimistAtomicQueueB: { let queue = new AtomicQueueB<uint32, 2>(ThroughputSize, 0U); defer delete queue; RunMpscScaling(queue, false, producerCount, messagesPerProducer); }\n");
        generated.Append("    case .OptimistAtomicQueue2: { let queue = new AtomicQueue2<uint32, 65536, 3>(); defer delete queue; RunMpmcScaling(queue, false, producerCount, 1, messagesPerProducer); }\n");
        generated.Append("    case .AtomicQueueB2: { let queue = new AtomicQueueB2<uint32, 2>(ThroughputSize); defer delete queue; RunMpscScaling(queue, true, producerCount, messagesPerProducer); }\n");
        generated.Append("    case .OptimistAtomicQueueB2: { let queue = new AtomicQueueB2<uint32, 2>(ThroughputSize); defer delete queue; RunMpscScaling(queue, false, producerCount, messagesPerProducer); }\n");
        generated.Append("    case .QueueMPMC: { let queue = new QueueMPMC<uint32, 65536>(); defer delete queue; RunMpmcScaling(queue, true, producerCount, 1, messagesPerProducer); }\n");
        generated.Append("    case .OptimistQueueMPMC: { let queue = new QueueMPMC<uint32, 65536>(); defer delete queue; RunMpmcScaling(queue, false, producerCount, 1, messagesPerProducer); }\n");
        generated.Append("    case .QueueMPMCCell: { let queue = new QueueMPMCCell<uint32, 65536>(); defer delete queue; RunMpmcScaling(queue, true, producerCount, 1, messagesPerProducer); }\n");
        generated.Append("    case .OptimistQueueMPMCCell: { let queue = new QueueMPMCCell<uint32, 65536>(); defer delete queue; RunMpmcScaling(queue, false, producerCount, 1, messagesPerProducer); }\n");
        generated.Append("    case .OptimizedQueueMPMC: { let queue = new OptimizedQueueMPMC<uint32, 65536>(); defer delete queue; RunMpmcScaling(queue, true, producerCount, 1, messagesPerProducer); }\n");
        generated.Append("    case .OptimistOptimizedQueueMPMC: { let queue = new OptimizedQueueMPMC<uint32, 65536>(); defer delete queue; RunMpmcScaling(queue, false, producerCount, 1, messagesPerProducer); }\n");
        generated.Append("    case .HyperQueueMPMC: { let queue = new HyperQueueMPMC<uint32, 65536>(); defer delete queue; RunMpmcScaling(queue, true, producerCount, 1, messagesPerProducer); }\n");
        generated.Append("    case .OptimistHyperQueueMPMC: { let queue = new HyperQueueMPMC<uint32, 65536>(); defer delete queue; RunMpmcScaling(queue, false, producerCount, 1, messagesPerProducer); }\n");
        generated.Append("    case .BlazeQueueMPMC: { let queue = new BlazeQueueMPMC<uint32, 65536>(); defer delete queue; RunMpmcScaling(queue, true, producerCount, 1, messagesPerProducer); }\n");
        generated.Append("    case .OptimistBlazeQueueMPMC: { let queue = new BlazeQueueMPMC<uint32, 65536>(); defer delete queue; RunMpmcScaling(queue, false, producerCount, 1, messagesPerProducer); }\n");
        generated.Append("    case .AtomicQueueMutex: { let queue = new AtomicQueueMutex<uint32, 65536>(); defer delete queue; RunMpscScaling(queue, true, producerCount, messagesPerProducer); }\n");
        generated.Append("    case .OptimistAtomicQueueMutex: { let queue = new AtomicQueueMutex<uint32, 65536>(); defer delete queue; RunMpscScaling(queue, false, producerCount, messagesPerProducer); }\n");
        generated.Append("    case .AtomicQueueMutexB: { let queue = new AtomicQueueMutexB<uint32>(ThroughputSize); defer delete queue; RunMpscScaling(queue, true, producerCount, messagesPerProducer); }\n");
        generated.Append("    case .OptimistAtomicQueueMutexB: { let queue = new AtomicQueueMutexB<uint32>(ThroughputSize); defer delete queue; RunMpscScaling(queue, false, producerCount, messagesPerProducer); }\n");
        generated.Append("    case .SimpleAtomicQueueB2: { let queue = new AtomicQueueSimpleB2<uint32>(ThroughputSize); defer delete queue; RunMpscScaling(queue, true, producerCount, messagesPerProducer); }\n");
        generated.Append("    case .SimpleOptimistAtomicQueueB2: { let queue = new AtomicQueueSimpleB2<uint32>(ThroughputSize); defer delete queue; RunMpscScaling(queue, false, producerCount, messagesPerProducer); }\n");
        generated.Append("    }\n}\n");
    }

    [Comptime]
    private static void EmitBenchmarkWrappers(String generated)
    {
        generated.Append("private static void BenchmarkSpsc_AtomicQueue() { let queue = new AtomicQueue<uint32, 65536, 8>(0U); defer delete queue; RunSpsc(queue, true); }\n");
        generated.Append("private static void BenchmarkMpmc_LockBasedQueue() { let queue = new LockBasedQueue<uint32>(ThroughputSize); defer delete queue; RunMpmcScaling(queue, MpmcProducers, MpmcConsumers, BenchmarkMessages / MpmcProducers); }\n");
        generated.Append("private static void BenchmarkMpmc_AtomicQueue() { let queue = new AtomicQueue<uint32, 65536, 3>(0U); defer delete queue; RunMpmc(queue, true); }\n");
        generated.Append("private static void BenchmarkMpsc_AtomicQueue() { let queue = new AtomicQueue<uint32, 65536, 3>(0U); defer delete queue; RunMpmcScaling(queue, true, MpmcProducers, 1, BenchmarkMessages / MpmcProducers); }\n");
        generated.Append("private static void BenchmarkSpsc_AtomicQueueB() { let queue = new AtomicQueueB<uint32, 8>(ThroughputSize, 0U); defer delete queue; RunSpsc(queue, true); }\n");
        generated.Append("private static void BenchmarkMpmc_AtomicQueueB() { let queue = new AtomicQueueB<uint32, 2>(ThroughputSize, 0U); defer delete queue; RunMpmc(queue, true); }\n");
        generated.Append("private static void BenchmarkMpsc_AtomicQueueB() { let queue = new AtomicQueueB<uint32, 2>(ThroughputSize, 0U); defer delete queue; RunMpsc(queue, true); }\n");
        generated.Append("private static void BenchmarkSpsc_OptimistAtomicQueue() { let queue = new AtomicQueue<uint32, 65536, 8>(0U); defer delete queue; RunSpsc(queue, false); }\n");
        generated.Append("private static void BenchmarkMpmc_OptimistAtomicQueue() { let queue = new AtomicQueue<uint32, 65536, 3>(0U); defer delete queue; RunMpmc(queue, false); }\n");
        generated.Append("private static void BenchmarkMpsc_OptimistAtomicQueue() { let queue = new AtomicQueue<uint32, 65536, 3>(0U); defer delete queue; RunMpmcScaling(queue, false, MpmcProducers, 1, BenchmarkMessages / MpmcProducers); }\n");
        generated.Append("private static void BenchmarkSpsc_OptimistAtomicQueueB() { let queue = new AtomicQueueB<uint32, 8>(ThroughputSize, 0U); defer delete queue; RunSpsc(queue, false); }\n");
        generated.Append("private static void BenchmarkMpmc_OptimistAtomicQueueB() { let queue = new AtomicQueueB<uint32, 2>(ThroughputSize, 0U); defer delete queue; RunMpmc(queue, false); }\n");
        generated.Append("private static void BenchmarkMpsc_OptimistAtomicQueueB() { let queue = new AtomicQueueB<uint32, 2>(ThroughputSize, 0U); defer delete queue; RunMpsc(queue, false); }\n");
        generated.Append("private static void BenchmarkSpsc_AtomicQueue2() { let queue = new AtomicQueue2<uint32, 65536, 8>(); defer delete queue; RunSpsc(queue, true); }\n");
        generated.Append("private static void BenchmarkMpmc_AtomicQueue2() { let queue = new AtomicQueue2<uint32, 65536, 3>(); defer delete queue; RunMpmc(queue, true); }\n");
        generated.Append("private static void BenchmarkMpsc_AtomicQueue2() { let queue = new AtomicQueue2<uint32, 65536, 3>(); defer delete queue; RunMpmcScaling(queue, true, MpmcProducers, 1, BenchmarkMessages / MpmcProducers); }\n");
        generated.Append("private static void BenchmarkSpsc_AtomicQueueB2() { let queue = new AtomicQueueB2<uint32, 8>(ThroughputSize); defer delete queue; RunSpsc(queue, true); }\n");
        generated.Append("private static void BenchmarkMpmc_AtomicQueueB2() { let queue = new AtomicQueueB2<uint32, 2>(ThroughputSize); defer delete queue; RunMpmc(queue, true); }\n");
        generated.Append("private static void BenchmarkMpsc_AtomicQueueB2() { let queue = new AtomicQueueB2<uint32, 2>(ThroughputSize); defer delete queue; RunMpsc(queue, true); }\n");
        generated.Append("private static void BenchmarkSpsc_OptimistAtomicQueue2() { let queue = new AtomicQueue2<uint32, 65536, 8>(); defer delete queue; RunSpsc(queue, false); }\n");
        generated.Append("private static void BenchmarkMpmc_OptimistAtomicQueue2() { let queue = new AtomicQueue2<uint32, 65536, 3>(); defer delete queue; RunMpmc(queue, false); }\n");
        generated.Append("private static void BenchmarkMpsc_OptimistAtomicQueue2() { let queue = new AtomicQueue2<uint32, 65536, 3>(); defer delete queue; RunMpmcScaling(queue, false, MpmcProducers, 1, BenchmarkMessages / MpmcProducers); }\n");
        generated.Append("private static void BenchmarkSpsc_OptimistAtomicQueueB2() { let queue = new AtomicQueueB2<uint32, 8>(ThroughputSize); defer delete queue; RunSpsc(queue, false); }\n");
        generated.Append("private static void BenchmarkMpmc_OptimistAtomicQueueB2() { let queue = new AtomicQueueB2<uint32, 2>(ThroughputSize); defer delete queue; RunMpmc(queue, false); }\n");
        generated.Append("private static void BenchmarkMpsc_OptimistAtomicQueueB2() { let queue = new AtomicQueueB2<uint32, 2>(ThroughputSize); defer delete queue; RunMpsc(queue, false); }\n");
        generated.Append("private static void BenchmarkSpsc_QueueSPSC() { let queue = new QueueSPSC<uint32, 65536>(); defer delete queue; RunSpsc(queue, true); }\n");
        generated.Append("private static void BenchmarkSpsc_OptimistQueueSPSC() { let queue = new QueueSPSC<uint32, 65536>(); defer delete queue; RunSpsc(queue, false); }\n");
        generated.Append("private static void BenchmarkMpmc_QueueMPMC() { let queue = new QueueMPMC<uint32, 65536>(); defer delete queue; RunMpmc(queue, true); }\n");
        generated.Append("private static void BenchmarkMpsc_QueueMPMC() { let queue = new QueueMPMC<uint32, 65536>(); defer delete queue; RunMpmcScaling(queue, true, MpmcProducers, 1, BenchmarkMessages / MpmcProducers); }\n");
        generated.Append("private static void BenchmarkMpmc_OptimistQueueMPMC() { let queue = new QueueMPMC<uint32, 65536>(); defer delete queue; RunMpmc(queue, false); }\n");
        generated.Append("private static void BenchmarkMpsc_OptimistQueueMPMC() { let queue = new QueueMPMC<uint32, 65536>(); defer delete queue; RunMpmcScaling(queue, false, MpmcProducers, 1, BenchmarkMessages / MpmcProducers); }\n");
        generated.Append("private static void BenchmarkMpmc_QueueMPMCCell() { let queue = new QueueMPMCCell<uint32, 65536>(); defer delete queue; RunMpmc(queue, true); }\n");
        generated.Append("private static void BenchmarkMpsc_QueueMPMCCell() { let queue = new QueueMPMCCell<uint32, 65536>(); defer delete queue; RunMpmcScaling(queue, true, MpmcProducers, 1, BenchmarkMessages / MpmcProducers); }\n");
        generated.Append("private static void BenchmarkMpmc_OptimistQueueMPMCCell() { let queue = new QueueMPMCCell<uint32, 65536>(); defer delete queue; RunMpmc(queue, false); }\n");
        generated.Append("private static void BenchmarkMpsc_OptimistQueueMPMCCell() { let queue = new QueueMPMCCell<uint32, 65536>(); defer delete queue; RunMpmcScaling(queue, false, MpmcProducers, 1, BenchmarkMessages / MpmcProducers); }\n");
        generated.Append("private static void BenchmarkMpmc_OptimizedQueueMPMC() { let queue = new OptimizedQueueMPMC<uint32, 65536>(); defer delete queue; RunMpmc(queue, true); }\n");
        generated.Append("private static void BenchmarkMpsc_OptimizedQueueMPMC() { let queue = new OptimizedQueueMPMC<uint32, 65536>(); defer delete queue; RunMpmcScaling(queue, true, MpmcProducers, 1, BenchmarkMessages / MpmcProducers); }\n");
        generated.Append("private static void BenchmarkMpmc_OptimistOptimizedQueueMPMC() { let queue = new OptimizedQueueMPMC<uint32, 65536>(); defer delete queue; RunMpmc(queue, false); }\n");
        generated.Append("private static void BenchmarkMpsc_OptimistOptimizedQueueMPMC() { let queue = new OptimizedQueueMPMC<uint32, 65536>(); defer delete queue; RunMpmcScaling(queue, false, MpmcProducers, 1, BenchmarkMessages / MpmcProducers); }\n");
        generated.Append("private static void BenchmarkMpmc_HyperQueueMPMC() { let queue = new HyperQueueMPMC<uint32, 65536>(); defer delete queue; RunMpmc(queue, true); }\n");
        generated.Append("private static void BenchmarkMpsc_HyperQueueMPMC() { let queue = new HyperQueueMPMC<uint32, 65536>(); defer delete queue; RunMpmcScaling(queue, true, MpmcProducers, 1, BenchmarkMessages / MpmcProducers); }\n");
        generated.Append("private static void BenchmarkMpmc_OptimistHyperQueueMPMC() { let queue = new HyperQueueMPMC<uint32, 65536>(); defer delete queue; RunMpmc(queue, false); }\n");
        generated.Append("private static void BenchmarkMpsc_OptimistHyperQueueMPMC() { let queue = new HyperQueueMPMC<uint32, 65536>(); defer delete queue; RunMpmcScaling(queue, false, MpmcProducers, 1, BenchmarkMessages / MpmcProducers); }\n");
        generated.Append("private static void BenchmarkMpmc_BlazeQueueMPMC() { let queue = new BlazeQueueMPMC<uint32, 65536>(); defer delete queue; RunMpmc(queue, true); }\n");
        generated.Append("private static void BenchmarkMpsc_BlazeQueueMPMC() { let queue = new BlazeQueueMPMC<uint32, 65536>(); defer delete queue; RunMpmcScaling(queue, true, MpmcProducers, 1, BenchmarkMessages / MpmcProducers); }\n");
        generated.Append("private static void BenchmarkMpmc_OptimistBlazeQueueMPMC() { let queue = new BlazeQueueMPMC<uint32, 65536>(); defer delete queue; RunMpmc(queue, false); }\n");
        generated.Append("private static void BenchmarkMpsc_OptimistBlazeQueueMPMC() { let queue = new BlazeQueueMPMC<uint32, 65536>(); defer delete queue; RunMpmcScaling(queue, false, MpmcProducers, 1, BenchmarkMessages / MpmcProducers); }\n");
        generated.Append("private static void BenchmarkMpsc_AtomicQueueMutex() { let queue = new AtomicQueueMutex<uint32, 65536>(); defer delete queue; RunMpsc(queue, true); }\n");
        generated.Append("private static void BenchmarkMpsc_OptimistAtomicQueueMutex() { let queue = new AtomicQueueMutex<uint32, 65536>(); defer delete queue; RunMpsc(queue, false); }\n");
        generated.Append("private static void BenchmarkMpsc_AtomicQueueMutexB() { let queue = new AtomicQueueMutexB<uint32>(ThroughputSize); defer delete queue; RunMpsc(queue, true); }\n");
        generated.Append("private static void BenchmarkMpsc_OptimistAtomicQueueMutexB() { let queue = new AtomicQueueMutexB<uint32>(ThroughputSize); defer delete queue; RunMpsc(queue, false); }\n");
        generated.Append("private static void BenchmarkMpsc_SimpleAtomicQueueB2() { let queue = new AtomicQueueSimpleB2<uint32>(ThroughputSize); defer delete queue; RunMpsc(queue, true); }\n");
        generated.Append("private static void BenchmarkMpsc_SimpleOptimistAtomicQueueB2() { let queue = new AtomicQueueSimpleB2<uint32>(ThroughputSize); defer delete queue; RunMpsc(queue, false); }\n");
        generated.Append("private static void BenchmarkMpsc_LockBasedQueue() { let queue = new LockBasedQueue<uint32>(ThroughputSize); defer delete queue; RunMpsc(queue); }\n");
    }
}
