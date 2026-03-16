module TestIndustrialLoad

using Test

include(joinpath(@__DIR__, "utilities.jl"))

test_path = "industrial_load"
test_setup = Dict(
    "Trans_Loss_Segments" => 1,
    "UCommit" => 0,
    "StorageLosses" => 1,
    "ParameterScale" => 1,
    "WriteOutputs" => "annual",
)

settings = GenX.default_settings()
merge!(settings, test_setup)

inputs = @warn_error_logger GenX.load_inputs(settings, test_path)
@test !isempty(inputs["INDUSTRIAL_LOAD"])
@test GenX.industrial_load(inputs["RESOURCES"]) == inputs["INDUSTRIAL_LOAD"]

EP, _, _ = redirect_stdout(devnull) do
    run_genx_case_testing(test_path, test_setup)
end

@test primal_status(EP) == MOI.FEASIBLE_POINT

output_path = joinpath(results_path, "industrial_load_outputs")
isdir(output_path) && rm(output_path, force = true, recursive = true)
mkpath(output_path)
redirect_stdout(devnull) do
    GenX.write_industrial_load_summary(output_path, inputs, settings, EP)
    GenX.write_power_balance(output_path, inputs, settings, EP)
    GenX.write_charge(output_path, inputs, settings, EP)
    GenX.write_costs(output_path, inputs, settings, EP)
end

summary_path = joinpath(output_path, "industrial_load_summary.csv")
power_balance_path = joinpath(output_path, "power_balance.csv")
charge_path = joinpath(output_path, "charge.csv")
costs_path = joinpath(output_path, "costs.csv")

@test isfile(summary_path)
@test isfile(power_balance_path)
@test isfile(charge_path)
@test isfile(costs_path)

df_summary = CSV.read(summary_path, DataFrame)
@test nrow(df_summary) == 1
@test df_summary.Resource[1] == "industrial_load"
@test df_summary.MinLoadFraction[1] == 0.4
@test df_summary.FlexibleLoadRange[1] == 0.6
@test df_summary.ExistingCapacity_MW[1] == 25.0
@test df_summary.AnnualCommodityDemand_MWhEq[1] == 125000.0

df_power_balance = CSV.read(power_balance_path, DataFrame)
@test any(df_power_balance.BalanceComponent .== "Industrial_Load_Consumption")

df_costs = CSV.read(costs_path, DataFrame)
@test any(df_costs.Costs .== "cFix")

end # module TestIndustrialLoad
