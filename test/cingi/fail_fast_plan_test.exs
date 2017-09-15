defmodule CingiFailFastPlanTest do
	use ExUnit.Case

	describe "fail fast" do
		setup do
			Helper.run_mission_report("test/mission_plans/fail_fast.yaml")
		end

		test "right output", ctx do
			assert ["two"] = ctx.output
		end

		test "right exit_code", ctx do
			assert 5 = ctx.exit_code
		end
	end
end
