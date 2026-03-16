@doc raw"""
    industrial_load!(EP::Model, inputs::Dict, setup::Dict)

This module represents an industrial production system whose original electricity demand is
treated as a fixed flat load, but which can become flexible through two endogenous
investments:

1. additional process capacity (``overcapacity``), and
2. intermediate commodity inventory (``commodity storage``).

The industrial resource consumes electricity directly from the power system. The produced
intermediate commodity is tracked in electricity-equivalent MWh, assuming no conversion
losses in this version. Annual commodity demand is anchored to the baseline fixed load
using the existing industrial capacity and the parameter ``Annual_MWh_per_MWyr``.
"""
function industrial_load!(EP::Model, inputs::Dict, setup::Dict)
    println("Industrial Load Module")

    gen = inputs["RESOURCES"]

    T = inputs["T"]
    Z = inputs["Z"]
    p = inputs["hours_per_subperiod"]
    ω = inputs["omega"]

    INDUSTRIAL_LOAD = inputs["INDUSTRIAL_LOAD"]
    NEW_CAP = inputs["NEW_CAP"]

    annual_modeled_hours = sum(ω)

    baseline_annual_demand(y) =
        existing_cap_mw(gen[y]) *
        (annual_mwh_per_mwyr(gen[y]) > 0 ? annual_mwh_per_mwyr(gen[y]) : annual_modeled_hours)

    INDUSTRIAL_LOAD_BY_ZONE = map(1:Z) do z
        intersect(INDUSTRIAL_LOAD, resources_in_zone_by_rid(gen, z))
    end

    @variable(EP, vUSE_IND[y = INDUSTRIAL_LOAD, t in 1:T] >= 0)
    @variable(EP, vS_IND[y = INDUSTRIAL_LOAD, t in 1:T] >= 0)
    @variable(EP, vCAP_INVENTORY_IND[y = INDUSTRIAL_LOAD] >= 0)

    @expression(EP,
        eIndustrialAnnualDemand[y in INDUSTRIAL_LOAD],
        baseline_annual_demand(y))
    @expression(EP,
        eIndustrialDemandPerHour[y in INDUSTRIAL_LOAD],
        EP[:eIndustrialAnnualDemand][y] / annual_modeled_hours)
    @expression(EP,
        eTotalCapInventoryIND[y in INDUSTRIAL_LOAD],
        existing_inventory_mwh(gen[y]) + EP[:vCAP_INVENTORY_IND][y])

    @expression(EP, ePowerBalanceIndustrialLoad[t in 1:T, z in 1:Z],
        sum(EP[:vUSE_IND][y, t] for y in INDUSTRIAL_LOAD_BY_ZONE[z]))
    add_similar_to_expression!(EP[:ePowerBalance], -1.0, ePowerBalanceIndustrialLoad)

    @expression(EP,
        eCOverCapIndustrial[y in INDUSTRIAL_LOAD],
        y in NEW_CAP ?
        (inv_cost_per_mwyr(gen[y]) + fixed_om_cost_per_mwyr(gen[y])) * EP[:vCAP][y] :
        0.0)
    @expression(EP,
        eTotalCOverCapIndustrial,
        sum(eCOverCapIndustrial[y] for y in INDUSTRIAL_LOAD; init = 0.0))
    add_to_expression!(EP[:eObj], eTotalCOverCapIndustrial)

    @expression(EP,
        eCInventoryIndustrial[y in INDUSTRIAL_LOAD],
        inventory_cost_per_mwhyr(gen[y]) * EP[:vCAP_INVENTORY_IND][y])
    @expression(EP,
        eTotalCInventoryIndustrial,
        sum(eCInventoryIndustrial[y] for y in INDUSTRIAL_LOAD; init = 0.0))
    add_to_expression!(EP[:eObj], eTotalCInventoryIndustrial)

    @constraint(EP,
        cIndustrialInventoryStart[y in INDUSTRIAL_LOAD, t in inputs["START_SUBPERIODS"]],
        EP[:vS_IND][y, t] ==
        EP[:vS_IND][y, hoursbefore(p, t, 1)] +
        EP[:vUSE_IND][y, t] -
        EP[:eIndustrialDemandPerHour][y])

    @constraints(EP,
        begin
            cIndustrialInventoryInterior[y in INDUSTRIAL_LOAD, t in inputs["INTERIOR_SUBPERIODS"]],
            EP[:vS_IND][y, t] ==
            EP[:vS_IND][y, t - 1] +
            EP[:vUSE_IND][y, t] -
            EP[:eIndustrialDemandPerHour][y]

            cIndustrialInventoryMax[y in INDUSTRIAL_LOAD, t in 1:T],
            EP[:vS_IND][y, t] <= EP[:eTotalCapInventoryIND][y]

            cIndustrialAnnualDemand[y in INDUSTRIAL_LOAD],
            sum(ω[t] * EP[:vUSE_IND][y, t] for t in 1:T) == EP[:eIndustrialAnnualDemand][y]

            cIndustrialMinimumLoad[y in INDUSTRIAL_LOAD, t in 1:T],
            EP[:vUSE_IND][y, t] >= min_power(gen[y]) * EP[:eTotalCap][y]

            cIndustrialMaximumLoad[y in INDUSTRIAL_LOAD, t in 1:T],
            EP[:vUSE_IND][y, t] <= EP[:eTotalCap][y]

            cIndustrialPowerVariableOff[y in INDUSTRIAL_LOAD, t in 1:T],
            EP[:vP][y, t] == 0
        end)

    return EP
end
