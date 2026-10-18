using System;

namespace BeefBench;

delegate void BenchmarkCaseIntVariantFactory(BenchmarkCaseBuilder builder, int32 value);
delegate void BenchmarkCaseStringVariantFactory(BenchmarkCaseBuilder builder, StringView value);

class BenchmarkSuiteBuilder
{
    private String mSuiteName ~ delete _;
    private String mCategory ~ delete _;
    private int mIterations = 1000;
    private int mWarmupCount = 5;
    private int mMeasurementCount = 15;

    public this(StringView suiteName)
    {
        mSuiteName = new .(suiteName);
    }

    public Self Category(StringView category)
    {
        delete mCategory;
        mCategory = new .(category);
        return this;
    }

    public Self Iterations(int iterations)
    {
        mIterations = iterations;
        return this;
    }

    public Self WarmupCount(int count)
    {
        mWarmupCount = count;
        return this;
    }

    public Self MeasurementCount(int count)
    {
        mMeasurementCount = count;
        return this;
    }

    public BenchmarkCaseBuilder Case(StringView caseName)
    {
        return new .(this, caseName);
    }

    public String CopySuiteName()
    {
        if (mSuiteName == null)
            return null;
        return new .(mSuiteName);
    }

    public String CopyDefaultCategory()
    {
        if (mCategory == null)
            return null;
        return new .(mCategory);
    }

    public int DefaultIterations => mIterations;
    public int DefaultWarmupCount => mWarmupCount;
    public int DefaultMeasurementCount => mMeasurementCount;
}

class BenchmarkCaseBuilder
{
    private String mSuiteName ~ delete _;
    private String mDefaultCategory ~ delete _;
    private String mCaseName ~ delete _;
    private String mCategory ~ delete _;
    private String mDisplayName ~ delete _;
    private String mTags ~ delete _;
    private String mDimensions ~ delete _;
    private String mLinkedSet ~ delete _;
    private String mComparisonSet ~ delete _;
    private String mThroughputUnit ~ delete _;
    private int mIterations;
    private int mWarmupCount;
    private int mMeasurementCount;
    private bool mIsBaseline;
    private bool mSortByPerformance;
    private bool mEnableThroughput;
    private double mThroughputWorkPerIteration;

    private this()
    {
    }

    public this(BenchmarkSuiteBuilder suite, StringView caseName)
    {
        mSuiteName = suite.CopySuiteName();
        mDefaultCategory = suite.CopyDefaultCategory();
        mCaseName = new .(caseName);
        mIterations = suite.DefaultIterations;
        mWarmupCount = suite.DefaultWarmupCount;
        mMeasurementCount = suite.DefaultMeasurementCount;
    }

    public BenchmarkCaseBuilder Clone()
    {
        BenchmarkCaseBuilder clone = new .();
        clone.mSuiteName = CopyString(mSuiteName);
        clone.mDefaultCategory = CopyString(mDefaultCategory);
        clone.mCaseName = CopyString(mCaseName);
        clone.mCategory = CopyString(mCategory);
        clone.mDisplayName = CopyString(mDisplayName);
        clone.mTags = CopyString(mTags);
        clone.mDimensions = CopyString(mDimensions);
        clone.mLinkedSet = CopyString(mLinkedSet);
        clone.mComparisonSet = CopyString(mComparisonSet);
        clone.mThroughputUnit = CopyString(mThroughputUnit);
        clone.mIterations = mIterations;
        clone.mWarmupCount = mWarmupCount;
        clone.mMeasurementCount = mMeasurementCount;
        clone.mIsBaseline = mIsBaseline;
        clone.mSortByPerformance = mSortByPerformance;
        clone.mEnableThroughput = mEnableThroughput;
        clone.mThroughputWorkPerIteration = mThroughputWorkPerIteration;
        return clone;
    }

    public Self Category(StringView category)
    {
        delete mCategory;
        mCategory = new .(category);
        return this;
    }

    public Self DisplayName(StringView displayName)
    {
        delete mDisplayName;
        mDisplayName = new .(displayName);
        return this;
    }

    public Self Tag(StringView tag)
    {
        AppendMetadata(ref mTags, tag, ',');
        return this;
    }

    public Self Dimension(StringView name, StringView value)
    {
        String pair = scope String();
        pair.Append(name);
        pair.Append('=');
        pair.Append(value);
        AppendMetadata(ref mDimensions, pair, ',');
        return this;
    }

    public Self DimensionInt(StringView name, int32 value)
    {
        String valueString = scope String();
        valueString.AppendF($"{value}");
        return Dimension(name, valueString);
    }

    public Self LinkedSet(StringView linkedSet)
    {
        delete mLinkedSet;
        mLinkedSet = new .(linkedSet);
        return this;
    }

    public Self ComparisonSet(StringView comparisonSet)
    {
        delete mComparisonSet;
        mComparisonSet = new .(comparisonSet);
        return this;
    }

    public Self Baseline(bool isBaseline = true)
    {
        mIsBaseline = isBaseline;
        return this;
    }

    public Self SortByPerformance(bool sortByPerformance = true)
    {
        mSortByPerformance = sortByPerformance;
        return this;
    }

    public Self Throughput(double workPerIteration, StringView unit)
    {
        mEnableThroughput = true;
        mThroughputWorkPerIteration = workPerIteration;
        delete mThroughputUnit;
        mThroughputUnit = new .(unit);
        return this;
    }

    public Self Iterations(int iterations)
    {
        mIterations = iterations;
        return this;
    }

    public Self WarmupCount(int count)
    {
        mWarmupCount = count;
        return this;
    }

    public Self MeasurementCount(int count)
    {
        mMeasurementCount = count;
        return this;
    }

    public void Register(StringView benchmarkName, BenchmarkFunc func)
    {
        String category = GetCategory();
        String linkedSet = CopyOrFallback(mLinkedSet, category);
        String comparisonSet = CopyOrFallback(mComparisonSet, category);

        BenchmarkReportOptions reportOptions = .(
            linkedSet,
            mSortByPerformance,
            comparisonSet,
            mEnableThroughput,
            mThroughputWorkPerIteration,
            CopyString(mThroughputUnit));

        BenchmarkMetadata metadata = .(
            CopyString(mSuiteName),
            CopyString(mCaseName),
            CopyStringOrFallback(mDisplayName, benchmarkName),
            CopyString(mTags),
            CopyString(mDimensions));

        BenchmarkRegistry.Register(
            new String(benchmarkName),
            func,
            mIterations,
            mWarmupCount,
            mMeasurementCount,
            category,
            mIsBaseline,
            reportOptions,
            metadata);
    }

    public void RegisterVariant(StringView benchmarkName, BenchmarkFunc func, bool isBaseline = false)
    {
        let variant = Clone();
        defer delete variant;
        variant.DisplayName(benchmarkName);
        variant.Baseline(isBaseline);
        variant.Register(benchmarkName, func);
    }

    public void RegisterVariant(StringView benchmarkName, BenchmarkFunc func, StringView dimensionName, StringView dimensionValue, bool isBaseline = false)
    {
        let variant = Clone();
        defer delete variant;
        variant.DisplayName(benchmarkName);
        variant.Dimension(dimensionName, dimensionValue);
        variant.Baseline(isBaseline);
        variant.Register(benchmarkName, func);
    }

    public void RegisterVariant(StringView benchmarkName, BenchmarkFunc func, StringView firstDimensionName, StringView firstDimensionValue, StringView secondDimensionName, StringView secondDimensionValue, bool isBaseline = false)
    {
        let variant = Clone();
        defer delete variant;
        variant.DisplayName(benchmarkName);
        variant.Dimension(firstDimensionName, firstDimensionValue);
        variant.Dimension(secondDimensionName, secondDimensionValue);
        variant.Baseline(isBaseline);
        variant.Register(benchmarkName, func);
    }

    public void RegisterIntRangeVariants(StringView dimensionName, int32 startInclusive, int32 endInclusive, BenchmarkCaseIntVariantFactory factory)
    {
        for (int32 value = startInclusive; value <= endInclusive; value++)
        {
            let variant = Clone();
            defer delete variant;
            variant.DimensionInt(dimensionName, value);
            factory(variant, value);
        }
    }

    public void RegisterStringVariants(StringView dimensionName, StringView[] values, BenchmarkCaseStringVariantFactory factory)
    {
        for (let value in values)
        {
            let variant = Clone();
            defer delete variant;
            variant.Dimension(dimensionName, value);
            factory(variant, value);
        }
    }

    private String GetCategory()
    {
        if (mCategory != null)
            return new .(mCategory);

        if (mDefaultCategory != null)
            return new .(mDefaultCategory);

        return new .(mCaseName);
    }

    private static void AppendMetadata(ref String target, StringView value, char8 separator)
    {
        if (target == null)
        {
            target = new .(value);
            return;
        }

        target.Append(separator);
        target.Append(value);
    }

    private static String CopyString(String source)
    {
        if (source == null)
            return null;
        return new .(source);
    }

    private static String CopyOrFallback(String primary, String fallback)
    {
        if (primary != null)
            return new .(primary);
        if (fallback != null)
            return new .(fallback);
        return null;
    }

    private static String CopyStringOrFallback(String primary, StringView fallback)
    {
        if (primary != null)
            return new .(primary);
        return new .(fallback);
    }
}
