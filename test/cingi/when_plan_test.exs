defmodule CingiWhenTest do
	use ExUnit.Case

	describe "when" do
		setup do
			Helper.run_mission_report("test/mission_plans/when.yaml")
		end

		test "runs correct amount of output", ctx do
			assert 10 = length(ctx.output)
		end

		test "things that should not run don't run", ctx do
			Enum.map ctx.output, &(assert not(&1 =~ "should not run"))
		end

		test "runs first few commands", ctx do
			assert ["first", "second"] = Enum.slice(ctx.output, 0, 2)
		end

		test "runs regardless, since fail_fast is false", ctx do
			assert "runs regardless" in ctx.output
		end

		test "runs correct output for exit code", ctx do
			assert "runs because of exit code 1" in ctx.output
			assert "should not run because not exit code 0" not in ctx.output
		end

		test "runs correct output for failure", ctx do
			assert "runs because of failure" in ctx.output
			assert "should not run because not success" not in ctx.output
		end

		test "runs correct output for output", ctx do
			assert "runs because of second in outputs" in ctx.output
			assert "should not run because of no first in outputs" not in ctx.output
		end

		test "runs correct output for multiple conditions", ctx do
			assert "runs because of second in outputs and exit code of 1" in ctx.output
			assert "should not run because although second in outputs, exit_code is not 2" not in ctx.output
		end

		test "runs correct output for parallel group", ctx do
			assert "runs because parallel group exited with 0" in ctx.output
			assert "should not run because parallel group was success" not in ctx.output
		end

		test "runs correct output meaning last submission does not make a nil exit code", ctx do
			assert "runs because exit code is not nil with last mission being skipped" in ctx.output
		end

		test "runs end mission because of false fail_fast", ctx do
			assert ["end"] = Enum.take(ctx.output, -1)
		end
	end
end
