function write_industrial_load_summary(path::AbstractString,
        inputs::Dict,
        setup::Dict,
        EP::Model)
    INDUSTRIAL_LOAD = inputs["INDUSTRIAL_LOAD"]
    isempty(INDUSTRIAL_LOAD) && return nothing

    gen = inputs["RESOURCES"]
    weight = inputs["omega"]
    power_scale = setup["ParameterScale"] == 1 ? ModelScalingFactor : 1.0
    cost_per_mwyr_scale = setup["ParameterScale"] == 1 ? ModelScalingFactor : 1.0
    cost_per_mwhyr_scale = setup["ParameterScale"] == 1 ? ModelScalingFactor : 1.0

    capacity_mw = value.(EP[:eTotalCap][INDUSTRIAL_LOAD]) .* power_scale
    annual_consumption_mwh = value.(EP[:vUSE_IND][INDUSTRIAL_LOAD, :]).data * weight .* power_scale
    annualized_fixed_cost_per_mwyr = (inv_cost_per_mwyr.(gen[INDUSTRIAL_LOAD]) .+
                                      fixed_om_cost_per_mwyr.(gen[INDUSTRIAL_LOAD])) .* cost_per_mwyr_scale
    annualized_fixed_cost_per_kwyr = annualized_fixed_cost_per_mwyr ./ ModelScalingFactor
    inventory_cost_per_mwhyr_human = inventory_cost_per_mwhyr.(gen[INDUSTRIAL_LOAD]) .* cost_per_mwhyr_scale
    inventory_cost_adder_per_mwyr = inventory_cost_per_mwhyr_human .* inventory_mwh_per_mw.(gen[INDUSTRIAL_LOAD])

    annualized_fixed_cost_per_mwh_annual = Vector{Union{Missing, Float64}}(missing,
        length(INDUSTRIAL_LOAD))
    for (i, y) in enumerate(INDUSTRIAL_LOAD)
        annual_mwh = annual_mwh_per_mwyr(gen[y])
        if annual_mwh > 0
            annualized_fixed_cost_per_mwh_annual[i] =
                annualized_fixed_cost_per_mwyr[i] / annual_mwh
        end
    end

    df = DataFrame(
        Resource = resource_name.(gen[INDUSTRIAL_LOAD]),
        Zone = zone_id.(gen[INDUSTRIAL_LOAD]),
        Region = region.(gen[INDUSTRIAL_LOAD]),
        Cluster = cluster.(gen[INDUSTRIAL_LOAD]),
        Capacity_MW = capacity_mw,
        AnnualConsumption_MWh = annual_consumption_mwh,
        CapacityFactor = annual_consumption_mwh ./ (capacity_mw .* sum(weight)),
        AnnualizedFixedCost_per_kWyr = annualized_fixed_cost_per_kwyr,
        AnnualizedFixedCost_per_MWh_annual = annualized_fixed_cost_per_mwh_annual,
        MinStableLoad = min_power.(gen[INDUSTRIAL_LOAD]),
        InventoryCost_per_MWhyr = inventory_cost_per_mwhyr_human,
        InventoryEquivalentHours = inventory_mwh_per_mw.(gen[INDUSTRIAL_LOAD]),
        InventoryCostAdder_per_MWyr = inventory_cost_adder_per_mwyr,
        MinUpTimeHours = min_up_time_hours.(gen[INDUSTRIAL_LOAD]),
        MinDownTimeHours = min_down_time_hours.(gen[INDUSTRIAL_LOAD]),
        RampUpPctPerHour = ramp_up_fraction.(gen[INDUSTRIAL_LOAD]),
        RampDownPctPerHour = ramp_down_fraction.(gen[INDUSTRIAL_LOAD]),
        IndustrialValue_per_MWh = industrial_value_per_mwh.(gen[INDUSTRIAL_LOAD]) .* cost_per_mwhyr_scale,
    )
    CSV.write(joinpath(path, "industrial_load_summary.csv"), df)
    return df
end
