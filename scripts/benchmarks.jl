using Distributed

const BenchmarksFolder = joinpath(@__DIR__, "..", "benchmarks")

struct BenchmarkResult
    group
    filename
    benchmark 
end

struct BenchmarksRunner 
    groups

    BenchmarksRunner() = begin 
        groups = readdir(BenchmarksFolder)
        return new(groups)
    end
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
