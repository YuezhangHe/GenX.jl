module TestIndustrialLoad

using Test

include(joinpath(@__DIR__, "utilities.jl"))

test_path = "industrial_load"
test_setup = Dict(
    "Trans_Loss_Segments" => 1,
    "UCommit" => 2,
    "StorageLosses" => 1,
    "ParameterScale" => 1,
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
end

summary_path = joinpath(output_path, "industrial_load_summary.csv")
power_balance_path = joinpath(output_path, "power_balance.csv")
charge_path = joinpath(output_path, "charge.csv")

@test isfile(summary_path)
@test isfile(power_balance_path)
@test isfile(charge_path)

df_summary = CSV.read(summary_path, DataFrame)
@test nrow(df_summary) == 1
@test df_summary.Resource[1] == "industrial_load"
@test df_summary.MinStableLoad[1] == 0.4
@test df_summary.InventoryEquivalentHours[1] == 4
@test df_summary.MinUpTimeHours[1] == 4
@test df_summary.RampUpPctPerHour[1] == 0.25

df_power_balance = CSV.read(power_balance_path, DataFrame)
@test any(df_power_balance.BalanceComponent .== "Industrial_Load_Consumption")

end # module TestIndustrialLoad
