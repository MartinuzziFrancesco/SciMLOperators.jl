using Test, LinearAlgebra, Random, SparseArrays, DiffEqOperators
using DiffEqBase
using DiffEqBase: isconstant
using DiffEqOperators: DiffEqScaledOperator, DiffEqOperatorCombination, DiffEqOperatorComposition

@testset "Operator Composition" begin
  # Structure
  Lfull = Matrix(L)
  @test opnorm(L) ≈ opnorm(Lfull)
  @test size(L) == size(Lfull)
  @test L[1,2] ≈ Lfull[1,2]
  Lsparse = sparse(L)
  @test Lsparse == Lfull
  u = [1.0, 2.0]; du = zeros(2)
  @test L * u ≈ Lfull * u
  mul!(du, L, u); @test du ≈ Lfull * u
  Lf = factorize(L)
  ldiv!(du, Lf, u); @test Lfull * du ≈ u
  @test exp(L) ≈ exp(Lfull)
end

@testset "Mutable Composite Operators" begin
  A = zeros(2,2); fA = (A,u,p,t) -> fill!(A, t)
  B = zeros(2,2); fB = (B,u,p,t) -> fill!(B, 2t)
  L = DiffEqArrayOperator(A; update_func=fA) * DiffEqArrayOperator(B; update_func=fB)
  @test isconstant(L) == false
  u = [1.0, 2.0]
  t = 1.1
  @test L(u,nothing,t) ≈ fill(t, (2,2)) * (fill(2t, (2,2)) * u)
end
