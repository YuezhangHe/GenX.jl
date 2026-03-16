function write_industrial_load_summary(path::AbstractString,
        inputs::Dict,
        setup::Dict,
        EP::Model)
    INDUSTRIAL_LOAD = inputs["INDUSTRIAL_LOAD"]
    isempty(INDUSTRIAL_LOAD) && return nothing

    gen = inputs["RESOURCES"]
    ω = inputs["omega"]

    power_scale = setup["ParameterScale"] == 1 ? ModelScalingFactor : 1.0
    cost_per_mwyr_scale = setup["ParameterScale"] == 1 ? ModelScalingFactor : 1.0
    cost_per_mwhyr_scale = setup["ParameterScale"] == 1 ? ModelScalingFactor : 1.0

    annual_modeled_hours = sum(ω)
    baseline_annual_demand(y) =
        existing_cap_mw(gen[y]) *
        (annual_mwh_per_mwyr(gen[y]) > 0 ? annual_mwh_per_mwyr(gen[y]) : annual_modeled_hours)

    existing_capacity_mw = existing_cap_mw.(gen[INDUSTRIAL_LOAD]) .* power_scale
    total_capacity_mw = [value(EP[:eTotalCap][y]) * power_scale for y in INDUSTRIAL_LOAD]
    overcapacity_mw = [y in inputs["NEW_CAP"] ? value(EP[:vCAP][y]) * power_scale : 0.0
                       for y in INDUSTRIAL_LOAD]
    annual_consumption_mwh = [
        sum(value(EP[:vUSE_IND][y, t]) * ω[t] for t in 1:length(ω)) * power_scale for
        y in INDUSTRIAL_LOAD
    ]
    annual_demand_mwh = baseline_annual_demand.(INDUSTRIAL_LOAD) .* power_scale
    storage_capacity_mwheq = [
        value(EP[:eTotalCapInventoryIND][y]) * power_scale for y in INDUSTRIAL_LOAD
    ]
    new_storage_capacity_mwheq = [
        value(EP[:vCAP_INVENTORY_IND][y]) * power_scale for y in INDUSTRIAL_LOAD
    ]

    overcapacity_cost_per_mwyr = (inv_cost_per_mwyr.(gen[INDUSTRIAL_LOAD]) .+
                                  fixed_om_cost_per_mwyr.(gen[INDUSTRIAL_LOAD])) .* cost_per_mwyr_scale
    overcapacity_cost_per_kwyr = overcapacity_cost_per_mwyr ./ ModelScalingFactor
    storage_cost_per_mwhyr = inventory_cost_per_mwhyr.(gen[INDUSTRIAL_LOAD]) .* cost_per_mwhyr_scale

    load_equivalent_capex_per_mwh_annual = Vector{Union{Missing, Float64}}(missing,
        length(INDUSTRIAL_LOAD))
    for (i, y) in enumerate(INDUSTRIAL_LOAD)
        annual_mwh = annual_mwh_per_mwyr(gen[y])
        if annual_mwh > 0
            load_equivalent_capex_per_mwh_annual[i] =
                overcapacity_cost_per_mwyr[i] / annual_mwh
        end
    end

    df = DataFrame(
        Resource = resource_name.(gen[INDUSTRIAL_LOAD]),
        Zone = zone_id.(gen[INDUSTRIAL_LOAD]),
        Region = region.(gen[INDUSTRIAL_LOAD]),
        Cluster = cluster.(gen[INDUSTRIAL_LOAD]),
        ExistingCapacity_MW = existing_capacity_mw,
        TotalCapacity_MW = total_capacity_mw,
        SelectedOvercapacity_MW = overcapacity_mw,
        MinLoadFraction = min_power.(gen[INDUSTRIAL_LOAD]),
        FlexibleLoadRange = 1 .- min_power.(gen[INDUSTRIAL_LOAD]),
        AnnualCommodityDemand_MWhEq = annual_demand_mwh,
        AnnualElectricityUse_MWh = annual_consumption_mwh,
        ExistingInventory_MWhEq = existing_inventory_mwh.(gen[INDUSTRIAL_LOAD]) .* power_scale,
        TotalInventory_MWhEq = storage_capacity_mwheq,
        SelectedInventory_MWhEq = new_storage_capacity_mwheq,
        OvercapacityCost_per_kWyr = overcapacity_cost_per_kwyr,
        OvercapacityCost_per_MWhAnnual = load_equivalent_capex_per_mwh_annual,
        InventoryCost_per_MWhEqYr = storage_cost_per_mwhyr,
    )
    CSV.write(joinpath(path, "industrial_load_summary.csv"), df)
    return df
end
