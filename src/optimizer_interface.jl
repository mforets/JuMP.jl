#  Copyright 2017, Iain Dunning, Joey Huchette, Miles Lubin, and contributors
#  This Source Code Form is subject to the terms of the Mozilla Public
#  License, v. 2.0. If a copy of the MPL was not distributed with this
#  file, You can obtain one at http://mozilla.org/MPL/2.0/.

function error_if_direct_mode(model::Model, func::Symbol)
    if mode(model) == Direct
        error("The `$func` function is not supported in Direct mode.")
    end
end

# These methods directly map to CachingOptimizer methods.
# They cannot be called in Direct mode.
function MOIU.resetoptimizer!(model::Model, optimizer::MOI.AbstractOptimizer,
                              bridge_constraints::Bool=true)
    error_if_direct_mode(model, :resetoptimizer!)
    MOIU.resetoptimizer!(backend(model), optimizer)
end

function MOIU.resetoptimizer!(model::Model)
    error_if_direct_mode(model, :resetoptimizer!)
    MOIU.resetoptimizer!(backend(model))
end

function MOIU.dropoptimizer!(model::Model)
    error_if_direct_mode(model, :dropoptimizer!)
    MOIU.dropoptimizer!(backend(model))
end

function MOIU.attachoptimizer!(model::Model)
    error_if_direct_mode(model, :attachoptimizer!)
    MOIU.attachoptimizer!(backend(model))
end

function set_optimizer(model::Model, optimizer_factory::OptimizerFactory;
                       bridge_constraints::Bool=true)
    error_if_direct_mode(model, :set_optimizer)
    optimizer = optimizer_factory()
    if bridge_constraints
        # The names are handled by the first caching optimizer.
        # If default_copy_to without names is supported, no need for a second
        # cache.
        if !MOIU.supports_default_copy_to(optimizer, false)
            if mode(model) == Manual
                # TODO figure out what to do in manual mode with the two caches
                error("Bridges in Manual mode with an optimizer not supporting `default_copy_to` is not supported yet")
            end
            universal_fallback = MOIU.UniversalFallback(JuMPMOIModel{Float64}())
            optimizer = MOIU.CachingOptimizer(universal_fallback, optimizer)
        end
        optimizer = MOI.Bridges.fullbridgeoptimizer(optimizer, Float64)
    end
    MOIU.resetoptimizer!(model, optimizer)
end

"""
    optimize!(model::Model,
              optimizer_factory::Union{Nothing, OptimizerFactory}=nothing;
              ignore_optimize_hook=(model.optimize_hook === nothing))

Optimize the model. If `optimizer_factory` is not `nothing`, it first sets the
optimizer to a new one created using the optimizer factory. The factory can be
created using the [`with_optimizer`](@ref) function.

## Examples

The optimizer factory can either be given in the [`Model`](@ref) constructor
as follows:
```julia
model = Model(with_optimizer(GLPK.Optimizer))
# ...fill model with variables, constraints and objectives...
# Solve the model with GLPK
JuMP.optimize!(model)
```
or in the `optimize!` call as follows:
```julia
model = Model()
# ...fill model with variables, constraints and objectives...
# Solve the model with GLPK
JuMP.optimize!(model, with_optimizer(GLPK.Optimizer))
```
"""
function optimize!(model::Model,
                   optimizer_factory::Union{Nothing, OptimizerFactory}=nothing;
                   bridge_constraints::Bool=true,
                   ignore_optimize_hook=(model.optimize_hook === nothing))
    # The nlp_data is not kept in sync, so re-set it here.
    # TODO: Consider how to handle incremental solves.
    if model.nlp_data !== nothing
        MOI.set(model, MOI.NLPBlock(), create_nlp_block_data(model))
        empty!(model.nlp_data.nlconstr_duals)
    end

    if optimizer_factory !== nothing
        if mode(model) == Direct
            error("An optimizer factory cannot be provided at the `optimize` call in Direct mode.")
        end
        if MOIU.state(backend(model)) != MOIU.NoOptimizer
            error("An optimizer factory cannot both be provided in the `Model` constructor and at the `optimize` call.")
        end
        set_optimizer(model, optimizer_factory,
                      bridge_constraints=bridge_constraints)
        MOIU.attachoptimizer!(model)
    end

    # If the user or an extension has provided an optimize hook, call
    # that instead of solving the model ourselves
    if !ignore_optimize_hook
        return model.optimize_hook(model)
    end

    MOI.optimize!(backend(model))

    return
end
