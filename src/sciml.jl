"""
    MatrixOperator(A[; update_func])

Represents a time-dependent linear operator given by an AbstractMatrix. The
update function is called by `update_coefficients!` and is assumed to have
the following signature:

    update_func(A::AbstractMatrix,u,p,t) -> [modifies A]
"""
struct MatrixOperator{T,AType<:AbstractMatrix{T},F} <: AbstractSciMLLinearOperator{T}
    A::AType
    update_func::F
    MatrixOperator(A::AType; update_func=DEFAULT_UPDATE_FUNC) where{AType} =
        new{eltype(A),AType,typeof(update_func)}(A, update_func)
end

# constructors
Base.similar(L::MatrixOperator, ::Type{T}, dims::Dims) where{T} = MatrixOperator(similar(L.A, T, dims))

# traits
@forward MatrixOperator.A (
                           LinearAlgebra.issymmetric,
                           LinearAlgebra.ishermitian,
                           LinearAlgebra.isposdef,

                           issquare,
                           has_ldiv,
                           has_ldiv!,
                          )
Base.size(L::MatrixOperator) = size(L.A)
for op in (
           :adjoint,
           :transpose,
          )
    @eval function Base.$op(L::MatrixOperator)
        MatrixOperator(
                       $op(L.A);
                       update_func = (A,u,p,t) -> $op(L.update_func(L.A,u,p,t))
                      )
    end
end

has_adjoint(A::MatrixOperator) = has_adjoint(A.A)
update_coefficients!(L::MatrixOperator,u,p,t) = (L.update_func(L.A,u,p,t); L)

isconstant(L::MatrixOperator) = L.update_func == DEFAULT_UPDATE_FUNC
Base.iszero(L::MatrixOperator) = iszero(L.A)

SparseArrays.sparse(L::MatrixOperator) = sparse(L.A)

# TODO - add tests for MatrixOperator indexing
# propagate_inbounds here for the getindex fallback
Base.@propagate_inbounds Base.convert(::Type{AbstractMatrix}, L::MatrixOperator) = L.A
Base.@propagate_inbounds Base.setindex!(L::MatrixOperator, v, i::Int) = (L.A[i] = v)
Base.@propagate_inbounds Base.setindex!(L::MatrixOperator, v, I::Vararg{Int, N}) where{N} = (L.A[I...] = v)

Base.eachcol(L::MatrixOperator) = eachcol(L.A)
Base.eachrow(L::MatrixOperator) = eachrow(L.A)
Base.length(L::MatrixOperator) = length(L.A)
Base.iterate(L::MatrixOperator,args...) = iterate(L.A,args...)
Base.axes(L::MatrixOperator) = axes(L.A)
Base.eachindex(L::MatrixOperator) = eachindex(L.A)
Base.IndexStyle(::Type{<:MatrixOperator{T,AType}}) where{T,AType} = Base.IndexStyle(AType)
Base.copyto!(L::MatrixOperator, rhs) = (copyto!(L.A, rhs); L)
Base.copyto!(L::MatrixOperator, rhs::Base.Broadcast.Broadcasted{<:StaticArrays.StaticArrayStyle}) = (copyto!(L.A, rhs); L)
Base.Broadcast.broadcastable(L::MatrixOperator) = L
Base.ndims(::Type{<:MatrixOperator{T,AType}}) where{T,AType} = ndims(AType)
ArrayInterfaceCore.issingular(L::MatrixOperator) = ArrayInterfaceCore.issingular(L.A)
Base.copy(L::MatrixOperator) = MatrixOperator(copy(L.A);update_func=L.update_func)

getops(L::MatrixOperator) = (L.A)

# operator application
Base.:*(L::MatrixOperator, u::AbstractVecOrMat) = L.A * u
Base.:\(L::MatrixOperator, u::AbstractVecOrMat) = L.A \ u
LinearAlgebra.mul!(v::AbstractVecOrMat, L::MatrixOperator, u::AbstractVecOrMat) = mul!(v, L.A, u)
LinearAlgebra.mul!(v::AbstractVecOrMat, L::MatrixOperator, u::AbstractVecOrMat, α, β) = mul!(v, L.A, u, α, β)
LinearAlgebra.ldiv!(v::AbstractVecOrMat, L::MatrixOperator, u::AbstractVecOrMat) = ldiv!(v, L.A, u)
LinearAlgebra.ldiv!(L::MatrixOperator, u::AbstractVecOrMat) = ldiv!(L.A, u)

""" Diagonal Operator """
DiagonalOperator(u::AbstractVector) = MatrixOperator(Diagonal(u))
LinearAlgebra.Diagonal(L::MatrixOperator) = MatrixOperator(Diagonal(L.A))

"""
    InvertibleOperator(F)

Like MatrixOperator, but stores a Factorization instead.

Supports left division and `ldiv!` when applied to an array.
"""
# diagonal, bidiagonal, adjoint(factorization)
struct InvertibleOperator{T,FType} <: AbstractSciMLLinearOperator{T}
    F::FType

    function InvertibleOperator(F)
        @assert has_ldiv(F) | has_ldiv!(F) "$F is not invertible"
        new{eltype(F),typeof(F)}(F)
    end
end

# constructor
function LinearAlgebra.factorize(L::AbstractSciMLLinearOperator)
    fact = factorize(convert(AbstractMatrix, L))
    InvertibleOperator(fact)
end

for fact in (
             :lu, :lu!,
             :qr, :qr!,
             :cholesky, :cholesky!,
             :ldlt, :ldlt!,
             :bunchkaufman, :bunchkaufman!,
             :lq, :lq!,
             :svd, :svd!,
            )

    @eval LinearAlgebra.$fact(L::AbstractSciMLLinearOperator, args...) =
        InvertibleOperator($fact(convert(AbstractMatrix, L), args...))
    @eval LinearAlgebra.$fact(L::AbstractSciMLLinearOperator; kwargs...) =
        InvertibleOperator($fact(convert(AbstractMatrix, L); kwargs...))
end

function Base.convert(::Type{AbstractMatrix}, L::InvertibleOperator)
    if L.F isa Adjoint
        convert(AbstractMatrix,L.F')'
    else
        convert(AbstractMatrix, L.F)
    end
end

# traits
Base.size(L::InvertibleOperator) = size(L.F)
Base.adjoint(L::InvertibleOperator) = InvertibleOperator(L.F')
LinearAlgebra.opnorm(L::InvertibleOperator{T}, p=2) where{T} = one(T) / opnorm(L.F)
LinearAlgebra.issuccess(L::InvertibleOperator) = issuccess(L.F)

getops(L::InvertibleOperator) = (L.F,)

@forward InvertibleOperator.F (
                               # LinearAlgebra
                               LinearAlgebra.issymmetric,
                               LinearAlgebra.ishermitian,
                               LinearAlgebra.isposdef,

                               # SciML
                               isconstant,
                               has_adjoint,
                               has_mul,
                               has_mul!,
                               has_ldiv,
                               has_ldiv!,
                              )

# operator application
Base.:*(L::InvertibleOperator, x::AbstractVecOrMat) = L.F * x
Base.:\(L::InvertibleOperator, x::AbstractVecOrMat) = L.F \ x
LinearAlgebra.mul!(v::AbstractVecOrMat, L::InvertibleOperator, u::AbstractVecOrMat) = mul!(v, L.F, u)
LinearAlgebra.mul!(v::AbstractVecOrMat, L::InvertibleOperator, u::AbstractVecOrMat,α, β) = mul!(v, L.F, u, α, β)
LinearAlgebra.ldiv!(v::AbstractVecOrMat, L::InvertibleOperator, u::AbstractVecOrMat) = ldiv!(v, L.F, u)
LinearAlgebra.ldiv!(L::InvertibleOperator, u::AbstractVecOrMat) = ldiv!(L.F, u)

"""
    L = AffineOperator(A, b)
    L(u) = A*u + b
"""
struct AffineOperator{T,AType,bType} <: AbstractSciMLOperator{T}
    A::AType
    b::bType

    function AffineOperator(A::AbstractSciMLOperator, b::AbstractVecOrMat)
        T = promote_type(eltype.((A,b))...)
        new{T,typeof(A),typeof(b)}(A, b)
    end
end

getops(L::AffineOperator) = (L.A, L.b)
Base.size(L::AffineOperator) = size(L.A)

islinear(::AffineOperator) = false
Base.iszero(L::AffineOperator) = all(iszero, getops(L))
has_adjoint(L::AffineOperator) = all(has_adjoint, L.ops)
has_mul!(L::AffineOperator) = has_mul!(L.A)
has_ldiv(L::AffineOperator) = has_ldiv(L.A)
has_ldiv!(L::AffineOperator) = has_ldiv!(L.A)


Base.:*(L::AffineOperator, u::AbstractVecOrMat) = L.A * u + L.b
Base.:\(L::AffineOperator, u::AbstractVecOrMat) = L.A \ (u - L.b)

function LinearAlgebra.mul!(v::AbstractVecOrMat, L::AffineOperator, u::AbstractVecOrMat)
    mul!(v, L.A, u)
    axpy!(true, L.b, v)
end

function LinearAlgebra.mul!(v::AbstractVecOrMat, L::AffineOperator, u::AbstractVecOrMat, α, β)
    mul!(v, L.A, u, α, β)
    axpy!(α, L.b, v)
end

function LinearAlgebra.ldiv!(v::AbstractVecOrMat, L::AffineOperator, u::AbstractVecOrMat)
    copy!(v, u)
    ldiv!(L, v)
end

function LinearAlgebra.ldiv!(L::AffineOperator, u::AbstractVecOrMat)
    axpy!(-true, L.b, u)
    ldiv!(L.A, u)
end

"""
    Matrix free operators (given by a function)
"""
struct FunctionOperator{isinplace,T,F,Fa,Fi,Fai,Tr,P,Tt,C} <: AbstractSciMLOperator{T}
    """ Function with signature op(u, p, t) and (if isinplace) op(du, u, p, t) """
    op::F
    """ Adjoint operator"""
    op_adjoint::Fa
    """ Inverse operator"""
    op_inverse::Fi
    """ Adjoint inverse operator"""
    op_adjoint_inverse::Fai
    """ Traits """
    traits::Tr
    """ Parameters """
    p::P
    """ Time """
    t::Tt
    """ Is cache set? """
    isset::Bool
    """ Cache """
    cache::C

    function FunctionOperator(op,
                              op_adjoint,
                              op_inverse,
                              op_adjoint_inverse,
                              traits,
                              p,
                              t,
                              isset,
                              cache
                             )

        iip = traits.isinplace
        T   = traits.T

        isset = cache !== nothing

        new{iip,
            T,
            typeof(op),
            typeof(op_adjoint),
            typeof(op_inverse),
            typeof(op_adjoint_inverse),
            typeof(traits),
            typeof(p),
            typeof(t),
            typeof(cache),
           }(
             op,
             op_adjoint,
             op_inverse,
             op_adjoint_inverse,
             traits,
             p,
             t,
             isset,
             cache,
            )
    end
end

function FunctionOperator(op;

                          # necessary
                          isinplace=nothing,
                          T=nothing,
                          size=nothing,

                          # optional
                          op_adjoint=nothing,
                          op_inverse=nothing,
                          op_adjoint_inverse=nothing,

                          p=nothing,
                          t=nothing,

                          cache=nothing,

                          # traits
                          opnorm=nothing,
                          issymmetric=false,
                          ishermitian=false,
                          isposdef=false,
                         )

    isinplace isa Nothing  && @error "Please provide a funciton signature
    by specifying `isinplace` as either `true`, or `false`.
    If `isinplace = false`, the signature is `op(u, p, t)`,
    and if `isinplace = true`, the signature is `op(du, u, p, t)`.
    Further, it is assumed that the function call would be nonallocating
    when called in-place"
    T isa Nothing  && @error "Please provide a Number type for the Operator"
    size isa Nothing  && @error "Please provide a size (m, n)"

    isreal = T <: Real
    adjointable = ishermitian | (isreal & issymmetric)
    invertible  = !(op_inverse isa Nothing)

    if adjointable & (op_adjoint isa Nothing) 
        op_adjoint = op
    end

    if invertible & (op_adjoint_inverse isa Nothing)
        op_adjoint_inverse = op_inverse
    end

    t = t isa Nothing ? zero(T) : t

    traits = (;
              opnorm = opnorm,
              issymmetric = issymmetric,
              ishermitian = ishermitian,
              isposdef = isposdef,

              isinplace = isinplace,
              T = T,
              size = size,
             )

    isset = cache !== nothing

    FunctionOperator(
                     op,
                     op_adjoint,
                     op_inverse,
                     op_adjoint_inverse,
                     traits,
                     p,
                     t,
                     isset,
                     cache,
                    )
end

function update_coefficients!(L::FunctionOperator, u, p, t)
    @set! L.p = p
    @set! L.t = t
    L
end

Base.size(L::FunctionOperator) = L.traits.size
function Base.adjoint(L::FunctionOperator)

    if ishermitian(L) | (isreal(L) & issymmetric(L))
        return L
    end

    if !(has_adjoint(L))
        return AdjointOperator(L)
    end

    op = L.op_adjoint
    op_adjoint = L.op

    op_inverse = L.op_adjoint_inverse
    op_adjoint_inverse = L.op_inverse

    traits = (L.traits[1:end-1]..., size=reverse(size(L)))

    p = L.p
    t = L.t

    cache = issquare(L) ? cache : nothing
    isset = cache !== nothing


    FuncitonOperator(op,
                     op_adjoint,
                     op_inverse,
                     op_adjoint_inverse,
                     traits,
                     p,
                     t,
                     isset,
                     cache
                    )
end

function LinearAlgebra.opnorm(L::FunctionOperator, p)
    L.traits.opnorm === nothing && error("""
      M.opnorm is nothing, please define opnorm as a function that takes one
      argument. E.g., `(p::Real) -> p == Inf ? 100 : error("only Inf norm is
      defined")`
    """)
    opn = L.opnorm
    return opn isa Number ? opn : M.opnorm(p)
end
LinearAlgebra.issymmetric(L::FunctionOperator) = L.traits.issymmetric
LinearAlgebra.ishermitian(L::FunctionOperator) = L.traits.ishermitian
LinearAlgebra.isposdef(L::FunctionOperator) = L.traits.isposdef

getops(::FunctionOperator) = ()
has_adjoint(L::FunctionOperator) = !(L.op_adjoint isa Nothing)
has_mul(L::FunctionOperator{iip}) where{iip} = !iip
has_mul!(L::FunctionOperator{iip}) where{iip} = iip
has_ldiv(L::FunctionOperator{iip}) where{iip} = !iip & !(L.op_inverse isa Nothing)
has_ldiv!(L::FunctionOperator{iip}) where{iip} = iip & !(L.op_inverse isa Nothing)

# operator application
Base.:*(L::FunctionOperator, u::AbstractVecOrMat) = L.op(u, L.p, L.t)
Base.:\(L::FunctionOperator, u::AbstractVecOrMat) = L.op_inverse(u, L.p, L.t)

function cache_self(L::FunctionOperator, u::AbstractVecOrMat)
    @set! L.cache = similar(u)
    L
end

function LinearAlgebra.mul!(v::AbstractVecOrMat, L::FunctionOperator, u::AbstractVecOrMat)
    L.op(v, u, L.p, L.t)
end

function LinearAlgebra.mul!(v::AbstractVecOrMat, L::FunctionOperator, u::AbstractVecOrMat, α, β)
    @assert L.isset "cache needs to be set up for operator of type $(typeof(L)).
    set up cache by calling cache_operator(L::AbstractSciMLOperator, u::AbstractVecOrMat)"
    copy!(L.cache, v)
    mul!(v, L, u)
    lmul!(α, v)
    axpy!(β, L.cache, v)
end

function LinearAlgebra.ldiv!(v::AbstractVecOrMat, L::FunctionOperator, u::AbstractVecOrMat)
    L.op_inverse(v, u, L.p, L.t)
end

function LinearAlgebra.ldiv!(L::FunctionOperator, u::AbstractVecOrMat)
    @assert L.isset "cache needs to be set up for operator of type $(typeof(L)).
    set up cache by calling cache_operator(L::AbstractSciMLOperator, u::AbstractVecOrMat)"
    copy!(L.cache, u)
    ldiv!(u, L, L.cache)
end

"""
    Lazy Tensor Product Operator

    TensorProductOperator(A, B) = A ⊗ B

    (A ⊗ B)(u) = vec(B * U * transpose(A))

    where U is a lazy representation of the vector u as
    a matrix with the appropriate size.
"""
struct TensorProductOperator{T,O,I,C} <: AbstractSciMLOperator{T}
    outer::O
    inner::I

    cache::C
    isset::Bool

    function TensorProductOperator(out, in, cache, isset)
        T = promote_type(eltype.((out, in))...)
        isset = cache !== nothing
        new{T,
            typeof(out),
            typeof(in),
            typeof(cache)
           }(
             out, in, cache, isset
            )
    end
end

function TensorProductOperator(out, in; cache = nothing)
    isset = cache !== nothing
    TensorProductOperator(out, in, cache, isset)
end

# constructors
TensorProductOperator(op::AbstractSciMLOperator) = op
TensorProductOperator(op::AbstractMatrix) = MatrixOperator(op)
TensorProductOperator(ops...) = reduce(TensorProductOperator, ops)
TensorProductOperator(Io::IdentityOperator{No}, Ii::IdentityOperator{Ni}) where{No,Ni} = IdentityOperator{No*Ni}()

# overload ⊗ (\otimes)
⊗(ops::Union{AbstractMatrix,AbstractSciMLOperator}...) = TensorProductOperator(ops...)

# TODO - overload Base.kron
#Base.kron(ops::Union{AbstractMatrix,AbstractSciMLOperator}...) = TensorProductOperator(ops...)

# convert to matrix
Base.kron(ops::AbstractSciMLOperator...) = kron(convert.(AbstractMatrix, ops)...)

function Base.convert(::Type{AbstractMatrix}, L::TensorProductOperator)
    kron(convert(AbstractMatrix, L.outer), convert(AbstractMatrix, L.inner))
end

function SparseArrays.sparse(L::TensorProductOperator)
    kron(sparse(L.outer), sparse(L.inner))
end

#LinearAlgebra.opnorm(L::TensorProductOperator) = prod(opnorm, L.ops)

Base.size(L::TensorProductOperator) = size(L.inner) .* size(L.outer)

for op in (
           :adjoint,
           :transpose,
          )
    @eval function Base.$op(L::TensorProductOperator)
        TensorProductOperator(
                              $op(L.outer),
                              $op(L.inner);
                              cache = issquare(L.inner) ? L.cache : nothing
                             )
    end
end

getops(L::TensorProductOperator) = (L.outer, L.inner)
islinear(L::TensorProductOperator) = islinear(L.outer) & islinear(L.inner)
Base.iszero(L::TensorProductOperator) = iszero(L.outer) | iszero(L.inner)
has_adjoint(L::TensorProductOperator) = has_adjoint(L.outer) & has_adjoint(L.inner)
has_mul!(L::TensorProductOperator) = has_mul!(L.outer) & has_mul!(L.inner)
has_ldiv(L::TensorProductOperator) = has_ldiv(L.outer) & has_ldiv(L.inner)
has_ldiv!(L::TensorProductOperator) = has_ldiv!(L.outer) & has_ldiv!(L.inner)

# operator application
# TODO - try permutedims!(dst,src,(2,1,...))
for op in (
           :*, :\,
          )
    @eval function Base.$op(L::TensorProductOperator, u::AbstractVecOrMat)
        mi, ni = size(L.inner)
        mo, no = size(L.outer)
        m , n  = size(L)
        k = size(u, 2)

        perm = (2, 1, 3)

        U = _reshape(u, (ni, no*k))
        C = $op(L.inner, U)

        V = if k > 1
            V = if L.outer isa IdentityOperator
                copy(C)
            else
                C = _reshape(C, (mi, no, k))
                C = permutedims(C, perm)
                C = _reshape(C, (no, mi*k))

                V = $op(L.outer, C)
                V = _reshape(V, (mo, mi, k))
                V = permutedims(V, perm)
                V
            end

            V
        else
            transpose($op(L.outer, transpose(C)))
        end

        u isa AbstractMatrix ? _reshape(V, (m, k)) : _reshape(V, (m,))
    end
end

function cache_self(L::TensorProductOperator, u::AbstractVecOrMat)
    mi, _  = size(L.inner)
    mo, no = size(L.outer)
    k = size(u, 2)

    c1 = similar(u, (mi, no*k))  # c1 = L.inner * u
    c2 = similar(u, (no, mi, k)) # permut (2, 1, 3)
    c3 = similar(u, (mo, mi*k))  # c3 = L.outer * c2
    c4 = similar(u, (mo*mi, k))  # cache v in 5 arg mul!

    @set! L.cache = (c1, c2, c3, c4,)
    L
end

function cache_internals(L::TensorProductOperator, u::AbstractVecOrMat) where{D}
    if !(L.isset)
        L = cache_self(L, u)
    end

    mi, ni = size(L.inner)
    _ , no = size(L.outer)
    k = size(u, 2)

    uinner = _reshape(u, (ni, no*k))
    uouter = L.cache[2]

    @set! L.inner = cache_operator(L.inner, uinner)
    @set! L.outer = cache_operator(L.outer, uouter)
    L
end

function LinearAlgebra.mul!(v::AbstractVecOrMat, L::TensorProductOperator, u::AbstractVecOrMat)
    @assert L.isset "cache needs to be set up for operator of type $(typeof(L)).
    set up cache by calling cache_operator(L::AbstractSciMLOperator, u::AbstractArray)"

    mi, ni = size(L.inner)
    mo, no = size(L.outer)
    k = size(u, 2)

    perm = (2, 1, 3)
    C1, C2, C3, _ = L.cache
    U = _reshape(u, (ni, no*k))

    """
        v .= kron(B, A) * u
        V .= A * U * B'
    """

    # C .= A * U
    mul!(C1, L.inner, U)

    # V .= U * B' <===> V' .= B * C'
    if k>1
        if L.outer isa IdentityOperator
            copyto!(v, C1)
        else
            C1 = _reshape(C1, (mi, no, k))
            permutedims!(C2, C1, perm)
            C2 = _reshape(C2, (no, mi*k))
            mul!(C3, L.outer, C2)
            C3 = _reshape(C3, (mo, mi, k))
            V  = _reshape(v , (mi, mo, k))
            permutedims!(V, C3, perm)
        end
    else
        V  = _reshape(v, (mi, mo))
        C1 = _reshape(C1, (mi, no))
        mul!(transpose(V), L.outer, transpose(C1))
    end

    v
end

function LinearAlgebra.mul!(v::AbstractVecOrMat, L::TensorProductOperator, u::AbstractVecOrMat, α, β)
    @assert L.isset "cache needs to be set up for operator of type $(typeof(L)).
    set up cache by calling cache_operator(L::AbstractSciMLOperator, u::AbstractArray)"

    mi, ni = size(L.inner)
    mo, no = size(L.outer)
    k = size(u, 2)

    perm = (2, 1, 3)
    C1, C2, C3, c4 = L.cache
    U = _reshape(u, (ni, no*k))

    """
        v .= α * kron(B, A) * u + β * v
        V .= α * (A * U * B') + β * v
    """

    # C .= A * U
    mul!(C1, L.inner, U)

    # V = α(C * B') + β(V)
    if k>1
        if L.outer isa IdentityOperator
            c1 = _reshape(C1, (m, k))
            axpby!(α, c1, β, v)
        else
            C1 = _reshape(C1, (mi, no, k))
            permutedims!(C2, C1, perm)
            C2 = _reshape(C2, (no, mi*k))
            mul!(C3, L.outer, C2)
            C3 = _reshape(C3, (mo, mi, k))
            V  = _reshape(v , (mi, mo, k))
            copy!(c4, v)
            permutedims!(V, C3, perm)
            axpby!(β, c4, α, v)
        end
    else
        V  = _reshape(v , (mi, mo))
        C1 = _reshape(C1, (mi, no))
        mul!(transpose(V), L.outer, transpose(C), α, β)
    end

    v
end

function LinearAlgebra.ldiv!(v::AbstractVecOrMat, L::TensorProductOperator, u::AbstractVecOrMat)
    @assert L.isset "cache needs to be set up for operator of type $(typeof(L)).
    set up cache by calling cache_operator(L::AbstractSciMLOperator, u::AbstractArray)"

    mi, ni = size(L.inner)
    mo, no = size(L.outer)
    k = size(u, 2)

    perm = (2, 1, 3)
    C1, C2, C3, _ = L.cache
    U = _reshape(u, (ni, no*k))

    """
        v .= kron(B, A) ldiv u
        V .= (A ldiv U) / B'
    """

    # C .= A \ U
    ldiv!(C1, L.inner, U)

    # V .= C / B' <===> V' .= B \ C'
    if k>1
        if L.outer isa IdentityOperator
            copyto!(v, C1)
        else
            C1 = _reshape(C1, (mi, no, k))
            permutedims!(C2, C1, perm)
            C2 = _reshape(C2, (no, mi*k))
            ldiv!(C3, L.outer, C2)
            C3 = _reshape(C3, (mo, mi, k))
            V  = _reshape(v , (mi, mo, k))
            permutedims!(V, C3, perm)
        end
    else
        V  = _reshape(v , (mi, mo))
        C1 = _reshape(C1, (mi, no))
        ldiv!(transpose(V), L.outer, transpose(C1))
    end

    v
end

function LinearAlgebra.ldiv!(L::TensorProductOperator, u::AbstractVecOrMat)
    @assert L.isset "cache needs to be set up for operator of type $(typeof(L)).
    set up cache by calling cache_operator(L::AbstractSciMLOperator, u::AbstractArray)"

    ni = size(L.inner, 1)
    no = size(L.outer, 1)
    k  = size(u, 2)

    perm = (2, 1, 3)
    C = L.cache[1]
    U = _reshape(u, (ni, no*k))

    """
        u .= kron(B, A) ldiv u
        U .= (A ldiv U) / B'
    """

    # U .= A \ U
    ldiv!(L.inner, U)

    # U .= U / B' <===> U' .= B \ U'
    if k>1 & !(L.outer isa IdentityOperator)
        U = _reshape(U, (ni, no, k))
        C = _reshape(C, (no, ni, k))
        permutedims!(C, U, perm)
        ldiv!(L.outer, C)
        permutedims!(U, C, perm)
    else
        ldiv!(L.outer, transpose(U))
    end

    u
end
#
