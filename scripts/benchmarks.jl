using Distributed

const BenchmarksFolder = joinpath(@__DIR__, "..", "benchmarks")
const BenchmarksBaselineGroup = "rxinfer"

struct BenchmarkResult
    group     :: String
    filename  :: String
    benchmark 
end

struct BenchmarksRunner 
    jobschannel
    resultschannel
    exschannel

    BenchmarksRunner() = begin 
        jobschannel = RemoteChannel(() -> Channel(Inf), myid()) # Channel for jobs
        resultschannel = RemoteChannel(() -> Channel(Inf), myid()) # Channel for results
        exschannel = RemoteChannel(() -> Channel(Inf), myid()) # Channel for exceptions
        return new(jobschannel, resultschannel, exschannel)
    end
end

const runner = BenchmarksRunner()

function Base.run(runner::BenchmarksRunner)
    @info "Reading `groups` in the `benchmarks` folder"

    # We add two groups by default, `baseline` and `develop`
    # `baseline` uses the released version of the RxInfer
    # `develop` group uses the development version of the RxInfer core packages 
    # the remaining groups should be taken from the remaining `folders`
    groups = Dict(
        "baseline" => readdir(joinpath(BenchmarksFolder, BenchmarksBaselineGroup)),
        "develop" => readdir(joinpath(BenchmarksFolder, BenchmarksBaselineGroup))
    )

    for group in readdir(BenchmarksFolder)
        if !isequal(group, BenchmarksBaselineGroup)
            !haskey(groups, group) || error("Cannot add the group `$(group)` twice")
            groups[group] = readdir(joinpath(BenchmarksFolder, group))
        end
    end

    return groups 
end

function perform_benchmark(group, filename)

    # Create an anonymous isolated module 
    mod  = Module()

    # Import `BenchmarkTools` in that module 
    Core.eval(mod, :(using BenchmarkTools))

    # This expression will be `eval`uated in the anonymous module
    expr = quote 
        Base.include($mod, $filename) 
        return @benchmark run_benchmark()
    end

    benchmark = Core.eval(mod, expr)

    return BenchmarkResult(group, filename, benchmark)
end