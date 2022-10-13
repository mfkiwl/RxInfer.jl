using Distributed

const ProjectFolder = joinpath(@__DIR__, "..")
const BenchmarksFolder = joinpath(ProjectFolder, "benchmarks")

const BenchmarksRxInferGroup = "rxinfer"
const BenchmarksTuringGroup = "turing"

# We add two groups by default, `baseline` and `develop`
# `baseline` uses the released version of the RxInfer
# `develop` group uses the development version of the RxInfer core packages 
# `turing` uses the released version of the Turing

const groups = Dict(
    # "baseline" => readdir(joinpath(BenchmarksFolder, BenchmarksProjectGroup)),
    "develop" => readdir(joinpath(BenchmarksFolder, BenchmarksRxInferGroup), join = true),
    "turing"  => readdir(joinpath(BenchmarksFolder, BenchmarksTuringGroup), join = true)
)

const groupsinit = Dict(
    # "baseline" => () -> begin 
    #     Pkg.add("RxInfer")
    #     Pkg.instantiate()
    #     Pkg.precompile()
    # end,
    "develop" => () -> begin 
        Pkg.develop(PackageSpec(path = ProjectFolder))
        Pkg.develop(PackageSpec(path = joinpath(Pkg.devdir(), "ReactiveMP.jl")))
        Pkg.develop(PackageSpec(path = joinpath(Pkg.devdir(), "GraphPPL.jl"))) 
        Pkg.develop(PackageSpec(path = joinpath(Pkg.devdir(), "Rocket.jl"))) 
    end,
    "turing" => () -> begin 
        Pkg.add("Turing")
    end
)

# We create a separate worker for each group to avoid code incompatibility
const workerids = addprocs(length(groups))

# Mapping between the name of the group and worker id
const workergroups = Dict(key => workerids[i] for (i, (key, _)) in enumerate(groups))

@everywhere struct BenchmarkResult
    group     :: String
    filename  :: String
    benchmark 
end

@everywhere function perform_benchmark(group, path)

    # Create an anonymous isolated module 
    mod  = Module()

    # Import `BenchmarkTools` in that module 
    Core.eval(mod, :(using BenchmarkTools))

    # This expression will be `eval`uated in the anonymous module
    expr = quote 
        Base.include($mod, $path) 
        return @benchmark run_benchmark()
    end

    # Extract the file name from the path
    name      = first(splitext(last(splitpath(path))))
    # Evaluate the actual benchmark
    benchmark = Core.eval(mod, expr)

    return BenchmarkResult(group, name, benchmark)
end

@everywhere using Pkg
@everywhere using BenchmarkTools

const benchmarks = map(collect(workergroups)) do (group, workerid)
    f = let initcallback = groupsinit[group], benchmarks = groups[group]
        () -> begin 
            mktempdir() do path 
                # Activate temporary environment inside the worker
                Pkg.activate(path)

                # Instantiate the environment with the correct packages set
                initcallback()
                Pkg.instantiate() 
                Pkg.precompile()

                # Perform benchmarks for each file in the directory
                results = map((b) -> perform_benchmark(group, b), benchmarks) 

                # Deactivate the temporary environment
                Pkg.activate()

                # Pkg.gc at the end will cleanup the environment's packages
                rm(joinpath(path, "Project.toml"))
                rm(joinpath(path, "Manifest.toml"))

                return results
            end
        end
    end
    return remotecall(f, workerid)
end

const results = map(fetch, benchmarks) 

println(results)

Pkg.gc()
