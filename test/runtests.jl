# using Revise
using Test

using Base.Threads; println("--> There are ", Threads.nthreads()," threads")

@testset "BifurcationKit" begin

    @testset "Linear Solvers" begin
        include("problems.jl")
        include("precond.jl")
        include("test_linear.jl")
    end

    @testset "Newton" begin
        include("test_newton.jl")
    end

    @testset "Continuation" begin
        include("test_bif_detection.jl")
        include("test-cont-non-vector.jl")
        include("simple_continuation.jl")
    end

    GC.gc()
    
    @testset "Normal forms" begin
        include("testNF.jl")
        include("testNF_maps.jl")
    end

    @testset "Events / User function" begin
        include("event.jl")
    end

    @testset "Fold Codim 2" begin
        include("testJacobianFoldDeflation.jl")
        include("codim2.jl")
    end

    GC.gc()
    
    @testset "Hopf Codim 2" begin
        include("testHopfMA.jl")
        include("lorenz84.jl")
        include("COModel.jl")
    end

    @testset "Periodic orbits function FD" begin
        include("test_potrap.jl")
        include("stuartLandauTrap.jl")
        include("stuartLandauCollocation.jl")
    end

    @testset "Periodic orbits function SH1" begin
        @info "Entry in test_SS.jl"
        include("test_SS.jl")
    end

    @testset "Periodic orbits function SH2" begin
        @info "Entry in poincareMap.jl"
        include("poincareMap.jl")
    end

    @testset "Periodic orbits function SH3" begin
        @info "Entry in stuartLandauSH.jl"
        include("stuartLandauSH.jl")
    end

    @testset "Periodic orbits function SH4" begin
        # for testing period doubling aBS
        @info "Entry in testLure.jl"
        include("testLure.jl")
    end
    
    GC.gc()

    @testset "codim 2 PO Shooting MF" begin
        @info "Entry in codim2PO-shooting-mf.jl"
        include("codim2PO-shooting-mf.jl")
    end

    GC.gc()
    
    @testset "codim 2 PO Shooting" begin
        @info "Entry in codim2PO-shooting.jl"
        include("codim2PO-shooting.jl")
    end

    GC.gc()

    @testset "codim 2 PO Collocation" begin
        @info "Entry in codim2PO-OColl.jl"
        include("codim2PO-OColl.jl")
    end

    @testset "Wave" begin
        @info "Entry in wave.jl"
        include("test_wave.jl")
    end
end
