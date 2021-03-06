using Combinatorics: permutations

export non0hist, binhist, genentropy, permentropy

"""
    non0hist(ε, dataset::AbstractDataset) → p
Partition a dataset into tabulated intervals (boxes) of
size `ε` and return the sum-normalized histogram in an unordered 1D form,
discarding all zero elements and bin edge information.

## Performances Notes
This method has a linearithmic time complexity (`n log(n)` for `n = length(data)`)
and a linear space complexity (`l` for `l = dimension(data)`).
This allows computation of histograms of high-dimensional
datasets and with small box sizes `ε` without memory overflow and with maximum performance.

Use [`binhist`](@ref) to retain bin edge information.
"""
non0hist(args...) = _non0hist(args...)[1]

function _non0hist(ε::Real, data::AbstractDataset{D, T}) where {D, T<:Real}
    mini = minima(data)
    L = length(data)
    hist = Vector{Float64}()
    # Reserve enough space for histogram:
    sizehint!(hist, L)

    # Map each datapoint to its bin edge and sort the resulting list:
    bins = map(point -> floor.(Int, (point - mini)/ε), data)
    sort!(bins, alg=QuickSort)

    # Fill the histogram by counting consecutive equal bins:
    prev_bin, count = bins[1], 0
    for bin in bins
        if bin == prev_bin
            count += 1
        else
            push!(hist, count/L)
            prev_bin = bin
            count = 1
        end
    end
    push!(hist, count/L)

    # Shrink histogram capacity to fit its size:
    sizehint!(hist, length(hist))
    return hist, bins, mini
end

"""
    binhist(ε, data) → p, bins
Do the same as [`non0hist`](@ref) but also return the bin edge information.
"""
function binhist(ε, data)
    hist, bins, mini = _non0hist(ε, data)
    unique!(bins)
    b = [β .* ε .+ mini for β in bins]
    return hist, b
end


"""
    genentropy(α, ε::Real, dataset::AbstractDataset; base = e)
Compute the `α` order generalized (Rényi) entropy[^Rényi1960] of a dataset,
by first partitioning it into boxes of length `ε` using [`non0hist`](@ref).

    genentropy(α, εs::AbstractVector, dataset::AbstractDataset; base = e)
Same as `[genentropy(α, ε, dataset) for ε in εs]`.

    genentropy(α, p::AbstractArray; base = e)
Compute the entropy of an array of probabilities `p`, assuming that `p` is
sum-normalized.

Optionally use `base` for the logarithms.

## Description
Let ``p`` be an array of probabilities (summing to 1). Then the Rényi entropy is
```math
H_\\alpha(p) = \\frac{1}{1-\\alpha} \\log \\left(\\sum_i p[i]^\\alpha\\right)
```
and generalizes other known entropies,
like e.g. the information entropy
(``\\alpha = 1``, see [^Shannon1948]), the maximum entropy (``\\alpha=0``,
also known as Hartley entropy), or the correlation entropy
(``\\alpha = 2``, also known as collision entropy).

[^Rényi1960]: A. Rényi, *Proceedings of the fourth Berkeley Symposium on Mathematics, Statistics and Probability*, pp 547 (1960)

[^Shannon1948]: C. E. Shannon, Bell Systems Technical Journal **27**, pp 379 (1948)
"""
function genentropy(α::Real, ε::Real, data::AbstractDataset;
    base=Base.MathConstants.e)
    ε ≤ 0 && throw(ArgumentError("Box-size for entropy calculation must be > 0."))
    p = non0hist(ε, data)
    return genentropy(α, p; base = base)
end
genentropy(α::Real, ε::Real, matrix; base = Base.MathConstants.e) =
genentropy(α, ε, Dataset(matrix); base = base)
genentropy(α::Real, ε::AbstractVector, X::AbstractDataset; base = Base.MathConstants.e) =
[genentropy(α, e, X; base = base) for e in ε]

function genentropy(α::Real, p::AbstractArray{T}; base = e) where {T<:Real}
    α < 0 && throw(ArgumentError("Order of generalized entropy must be ≥ 0."))
    if α ≈ 0
        return log(base, length(p)) #Hartley entropy, max-entropy
    elseif α ≈ 1
        return -sum( x*log(base, x) for x in p ) #Shannon entropy
    elseif isinf(α)
        return -log(base, maximum(p)) #Min entropy
    else
        return (1/(1-α))*log(base, sum(x^α for x in p) ) #Renyi α entropy
    end
end



"""
    permentropy(x::AbstractVector, order [, interval=1]; base = e)

Compute the permutation entropy[^Brandt2002] of given `order`
from the `x` timeseries.

Optionally, `interval` can be specified to
use `x[t0:interval:t1]` when calculating permutation of the
sliding windows between `t0` and `t1 = t0 + interval * (order - 1)`.

Optionally use `base` for the logarithms.

[^Bandt2002]: C. Bandt, & B. Pompe, [Phys. Rev. Lett. **88** (17), pp 174102 (2002)](http://doi.org/10.1103/PhysRevLett.88.174102)
"""
function permentropy(
        time_series::AbstractArray{T, 1}, orderi::Integer,
        interval::Integer = 1;
        base=Base.MathConstants.e) where {T}

    orderi > 255 && throw(ArgumentError("order = $orderi is too large, "*
              "must be smaller than $(Int(typemax(UInt8)))."))
    order = UInt8(orderi)
    # To use `searchsortedfirst`, we need each permutation to be
    # "comparable" (ordered) type.  Let's use NTuple here:
    PermType = NTuple{Int(order), UInt8}

    perms = map(PermType, permutations(1:order))
    count = zeros(UInt64, length(perms))

    for t in 1:length(time_series) - interval * order + 1
        sample = @view time_series[t:interval:t + interval * (order - 1)]
        i = searchsortedfirst(perms, PermType(sortperm(sample)))
        count[i] += 1
    end

    # To compute `p log(p)` correctly for `p = 0`, we first discard
    # cases with zero occurrence.  They don't contribute to the final
    # sum hence to the entropy:
    nonzero = [c for c in count if c != 0]

    p = nonzero ./ sum(nonzero)
    return -sum(p .* log.(base, p))
end
