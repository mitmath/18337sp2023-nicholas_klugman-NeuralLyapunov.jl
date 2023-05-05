struct NeuralLyapunovSpecifications
    structure::NeuralLyapunovStructure
    minimzation_condition::AbstractLyapunovMinimizationCondition
    decrease_condition::AbstractLyapunovDecreaseCondition
end

"""
    NeuralLyapunovStructure

Specifies the structure of the neural Lyapunov function and its derivative.

Allows the user to define the Lyapunov in terms of the neural network to 
structurally enforce Lyapunov conditions. 
V(phi::Function, state, fixed_point) takes in the neural network, the state,
and the fixed_point, and outputs the value of the Lyapunov function at state
V̇(phi::Function, J_phi::Function, f::Function, state, fixed_point) takes in the
neural network, the jacobian of the neural network, the dynamics (as a function
of the state alone), the state, and the fixed_point, and outputs the time 
derivative of the Lyapunov function at state.
"""
struct NeuralLyapunovStructure
    V::Function
    V̇::Function
end

"""
    UnstructuredNeuralLyapunov()

Creates a NeuralLyapunovStructure where the Lyapunov function is the neural
network evaluated at state. This does not structurally enforce any Lyapunov 
conditions.
"""
function UnstructuredNeuralLyapunov()
    NeuralLyapunovStructure(
        (phi, state, fixed_point) -> phi(state), 
        (phi, grad_phi, f, state, fixed_point) -> grad_phi(state) ⋅ f(state)
        )
end

"""
    NonnegativeNeuralLyapunov(δ, pos_def)

Creates a NeuralLyapunovStructure where the Lyapunov function is the L2 norm of
the neural network output plus a constant δ times a function pos_def.

The condition that the Lyapunov function must be minimized uniquely at the
fixed point can be represented as V(fixed_point) = 0, V(state) > 0 when 
state != fixed_point. This structure ensures V(state) >= 0. Further, if δ > 0
and pos_def(fixed_point) = 0, but pos_def(state) > 0 when state != fixed_point,
this ensures taht V(state) > 0 when state != fixed_point. This does not enforce
V(fixed_point) = 0, so that condition must included in the neural Lyapunov loss
function.
"""
function NonnegativeNeuralLyapunov(
    δ::Real = 0.0, 
    pos_def::Function = (state, fixed_point) -> log(1.0 + (state - fixed_point) ⋅ (state - fixed_point))
    )
    if δ == 0.0
        NeuralLyapunovStructure(
            (phi, state, fixed_point) -> phi(state) ⋅ phi(state), 
            (phi, J_phi, f, state, fixed_point) -> 2 * dot(phi(state), J_phi(state), f(state))
            )
    else
        NeuralLyapunovStructure(
            (phi, state, fixed_point) -> phi(state) ⋅ phi(state) + δ * pos_def(state, fixed_point), 
            (phi, J_phi, f, state, fixed_point) -> 2 * dot(phi(state), J_phi(state), f(state)) + δ * ForwardDiff.gradient((x) -> pos_def(x, fixed_point), state) ⋅ f(state)
            )
    end
end

abstract type AbstractLyapunovMinimizationCondition end

"""
    get_condition(cond::AbstractLyapunovMinimizationCondition)

Returns a function of V, dVdt, state, and fixed_point that is greater than zero
when the Lyapunov minimization condition is met and less than zero when it is 
violated
"""
function get_condition(cond::AbstractLyapunovMinimizationCondition)
    error("get_condition not implemented for AbstractLyapunovMinimizationCondition of type $(typeof(cond))")
end

"""
    LyapunovMinimizationCondition

Specifies the form of the Lyapunov conditions to be used.

If check_nonnegativity is true, training will attempt to enforce
    V ≥ strength(state, fixed_point)
If check_fixed_point is true, then training will attempt to enforce 
    V(fixed_point) = 0

# Examples

The condition that the Lyapunov function must be minimized uniquely at the
fixed point can be represented as V(fixed_point) = 0, V(state) > 0 when 
state != fixed_point. This could be enfored by V ≥ ||state - fixed_point||^2,
which would be represented, with check_nonnegativity = true, by
    strength(state, fixed_point) = ||state - fixed_point||^2,
paired with V(fixed_point) = 0, which can be enforced with 
    check_fixed_point = true

If V were structured such that it is always nonnegative, then V(fixed_point) = 0
is all that must be enforced in training for the Lyapunov function to be 
uniquely minimized at fixed_point. So, in that case, we would use 
    check_nonnegativity = false;  check_fixed_point = true
"""
struct LyapunovMinimizationCondition <: AbstractLyapunovMinimizationCondition
    check_nonnegativity::Bool
    strength::Function
    check_fixed_point::Bool
end

function get_condition(cond::LyapunovMinimizationCondition)
    if cond.check_nonnegativity
        return (V, x, fixed_point) -> V(x) - cond.strength(x, fixed_point)
    else
        return nothing
    end
end

"""
    StrictlyPositiveDefinite(C; check_fixed_point)

Constructs a LyapunovMinimizationCondition representing 
    V(state) ≥ C * ||state - fixed_point||^2
If check_fixed_point is true, then training will also attempt to enforce 
    V(fixed_point) = 0
"""
function StrictlyPositiveDefinite(C::Real = 1e-6; check_fixed_point = true)
    LyapunovMinimizationCondition(
        true,
        (state, fixed_point) -> C * (state - fixed_point) ⋅ (state - fixed_point),
        check_fixed_point
    )
end

"""
    PositiveSemiDefinite(check_fixed_point)

Constructs a LyapunovMinimizationCondition representing 
    V(state) ≥ 0
If check_fixed_point is true, then training will also attempt to enforce 
    V(fixed_point) = 0
"""
function PositiveSemiDefinite(check_fixed_point = true)
    LyapunovMinimizationCondition(
        true,
        (state, fixed_point) -> 0.0,
        check_fixed_point
    )
end

"""
    DontCheckNonnegativity(check_fixed_point)

Constructs a LyapunovMinimizationCondition which represents not checking for 
nonnegativity of the Lyapunov function. This is appropriate in cases where this
condition has been structurally enforced.

It is still possible to check for V(fixed_point) = 0, even in this case, for
example if V is structured to be positive for state != fixed_point, but it is
not guaranteed structurally that V(fixed_point) = 0.
"""
function DontCheckNonnegativity(check_fixed_point = false)
    LyapunovMinimizationCondition(
        false,
        nothing,
        check_fixed_point
    )    
end

abstract type AbstractLyapunovDecreaseCondition end

"""
    get_condition(cond::AbstractLyapunovDecreaseCondition)

Returns a function of V, dVdt, state, and fixed_point that is less than zero
when the Lyapunov decrease condition is met and greater than zero when it is 
violated
"""
function get_condition(cond::AbstractLyapunovDecreaseCondition)
    error("get_condition not implemented for AbstractLyapunovDecreaseCondition of type $(typeof(cond))")
end

"""
LyapunovDecreaseCondition(decrease, strength, check_fixed_point)

Specifies the form of the Lyapunov conditions to be used; training will enforce
    decrease(V, dVdt) ≤ strength(state, fixed_point)
If check_fixed_point is false, then training assumes dVdt(fixed_point) = 0, but
if check_fixed_point is true, then training will enforce dVdt(fixed_point) = 0.

If the dynamics truly have a fixed point at fixed_point and dVdt has been 
defined properly in terms of the dynamics, then dVdt(fixed_point) will be 0 and
there is no need to enforce dVdt(fixed_point) = 0, so check_fixed_point defaults
to false.

# Examples:

Asymptotic decrease can be enforced by requiring
    dVdt < -C |state - fixed_point|^2,
which corresponds to
    decrease = (V, dVdt) -> dVdt
    strength = (x, x0) -> -C * (x - x0) ⋅ (x - x0)

Exponential decrease of rate k is proven by dVdt ≤ - k * V, so corresponds to
    decrease = (V, dVdt) -> dVdt + k * V
    strength = (x, x0) -> 0.0
"""
struct LyapunovDecreaseCondition <: AbstractLyapunovDecreaseCondition
    check_decrease::Bool
    decrease::Function
    strength::Function
    check_fixed_point::Bool
end

function get_condition(cond::LyapunovDecreaseCondition)
    if cond.check_decrease
        return (V, dVdt, x, fixed_point) -> cond.decrease(V, dVdt) - cond.strength(x, fixed_point)
    else
        return nothing
    end
end

"""
    AsymptoticDecrease(strict; check_fixed_point, C)

Constructs a LyapunovDecreaseCondition corresponding to asymptotic decrease.

If strict is false, the condition is dV/dt < 0, and if strict is true, the 
condition is dV/dt < - C | state - fixed_point |^2
"""
function AsymptoticDecrease(strict::Bool = false; check_fixed_point::Bool = false, C::Real = 1e-6)
    if strict
        return LyapunovDecreaseCondition(
            true,
            (V, dVdt) -> dVdt, 
            (x, x0) -> -C * (x - x0) ⋅ (x - x0),
            check_fixed_point
            )
    else
        return LyapunovDecreaseCondition(
            true,
            (V, dVdt) -> dVdt, 
            (x, x0) -> 0.0,
            check_fixed_point
            )
    end
end

"""
    ExponentialDecrease(k, strict; check_fixed_point, C)

Constructs a LyapunovDecreaseCondition corresponding to exponential decrease of rate k.

If strict is false, the condition is dV/dt < -k * V, and if strict is true, the 
condition is dV/dt < -k * V - C * ||state - fixed_point||^2
"""
function ExponentialDecrease(k::Real, strict::Bool = false; check_fixed_point::Bool = false, C::Real = 1e-6)
    if strict
        return LyapunovDecreaseCondition(
            true,
            (V, dVdt) -> dVdt + k * V, 
            (x, x0) -> -C * (x - x0) ⋅ (x - x0),
            check_fixed_point
            )
    else
        return LyapunovDecreaseCondition(
            true,
            (V, dVdt) -> dVdt + k * V, 
            (x, x0) -> 0.0,
            check_fixed_point
            )
    end
end

"""
    DontCheckDecrease(check_fixed_point = false)

Constructs a LyapunovDecreaseCondition which represents not checking for 
decrease of the Lyapunov function along system trajectories. This is appropriate
in cases when the Lyapunov decrease condition has been structurally enforced.

It is still possible to check for dV/dt = 0 at fixed_point, even in this case.
"""
function DontCheckDecrease(check_fixed_point::Bool = false)
    return LyapunovDecreaseCondition(
        false,
        nothing,
        nothing,
        check_fixed_point
    )
end