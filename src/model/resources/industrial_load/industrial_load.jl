@doc raw"""
    industrial_load!(EP::Model, inputs::Dict, setup::Dict)

This function defines the operating constraints for industrial load resources. Industrial
loads are electricity-consuming resources that can represent electro-intensive processes
such as electrolytic refining, grinding mills, or other flexible process loads.

The current implementation activates three dimensions in the optimization:
1. electricity consumption is subtracted from zonal power balance,
2. minimum stable load is enforced through ``\phi^{min}``,
3. backend material inventory cost is represented as an annual fixed adder using the
   product inventory depth in MWh-equivalent per MW of industrial capacity.

Minimum up/down time and ramp-rate fields are loaded and reported, but intentionally not
imposed as constraints in this version.
"""
function industrial_load!(EP::Model, inputs::Dict, setup::Dict)
    println("Industrial Load Module")

    omega = inputs["omega"]
    gen = inputs["RESOURCES"]

    T = inputs["T"]
    Z = inputs["Z"]
    INDUSTRIAL_LOAD = inputs["INDUSTRIAL_LOAD"]

    @variable(EP, vUSE_IND[y = INDUSTRIAL_LOAD, t in 1:T] >= 0)

    INDUSTRIAL_LOAD_BY_ZONE = map(1:Z) do z
        intersect(INDUSTRIAL_LOAD, resources_in_zone_by_rid(gen, z))
    end

    @expression(EP, ePowerBalanceIndustrialLoad[t in 1:T, z in 1:Z],
        sum(EP[:vUSE_IND][y, t] for y in INDUSTRIAL_LOAD_BY_ZONE[z]))
    add_similar_to_expression!(EP[:ePowerBalance], -1.0, ePowerBalanceIndustrialLoad)

    @expression(EP,
        eCVarIndustrialLoad[y in INDUSTRIAL_LOAD, t in 1:T],
        omega[t] * var_om_cost_per_mwh_in(gen[y]) * EP[:vUSE_IND][y, t])
    @expression(EP,
        eTotalCVarIndustrialLoadT[t in 1:T],
        sum(eCVarIndustrialLoad[y, t] for y in INDUSTRIAL_LOAD; init = 0))
    @expression(EP,
        eTotalCVarIndustrialLoad,
        sum(eTotalCVarIndustrialLoadT[t] for t in 1:T))
    add_to_expression!(EP[:eObj], eTotalCVarIndustrialLoad)

    @expression(EP,
        eCInvIndustrialLoad[y in INDUSTRIAL_LOAD],
        inventory_cost_per_mwhyr(gen[y]) *
        inventory_mwh_per_mw(gen[y]) *
        EP[:eTotalCap][y])
    @expression(EP,
        eTotalCInvIndustrialLoad,
        sum(eCInvIndustrialLoad[y] for y in INDUSTRIAL_LOAD; init = 0))
    add_to_expression!(EP[:eObj], eTotalCInvIndustrialLoad)

    @expression(EP,
        eIndustrialValue[y in INDUSTRIAL_LOAD, t in 1:T],
        omega[t] * industrial_value_per_mwh(gen[y]) * EP[:vUSE_IND][y, t])
    @expression(EP,
        eTotalIndustrialValueT[t in 1:T],
        sum(eIndustrialValue[y, t] for y in INDUSTRIAL_LOAD; init = 0))
    @expression(EP,
        eTotalIndustrialValue,
        sum(eTotalIndustrialValueT[t] for t in 1:T))
    add_to_expression!(EP[:eObj], -1.0, eTotalIndustrialValue)

    @constraints(EP,
        begin
            [y in INDUSTRIAL_LOAD, t in 1:T],
            EP[:vUSE_IND][y, t] >= min_power(gen[y]) * EP[:eTotalCap][y]

            [y in INDUSTRIAL_LOAD, t in 1:T],
            EP[:vUSE_IND][y, t] <= inputs["pP_Max"][y, t] * EP[:eTotalCap][y]

            [y in INDUSTRIAL_LOAD, t in 1:T],
            EP[:vP][y, t] == 0
        end)

    return EP
end
