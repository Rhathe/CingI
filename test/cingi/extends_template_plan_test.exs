defmodule CingiExtendsTemplatePlanTest do
	use ExUnit.Case

	import ExUnit.CaptureIO

	describe "extends template" do
		setup do
			execute = fn() ->
				ctx = Helper.run_mission_report("test/mission_plans/extends/template.yaml")
				send self(), {:ctx, ctx}
			end

			assert capture_io(:stderr, execute) =~ "Template key no_mission_plan doesn't exist in the hierarchy"

			receive do
				{:ctx, ctx} -> ctx
			end
		end

		test "right amount of output", ctx do
			assert 7 = length(ctx.output)
		end

		test "extends correct template in supermission", ctx do
			assert "one" = Enum.at(ctx.output, 0)
		end

		test "extends template within template", ctx do
			assert "onetwo" = Enum.at(ctx.output, 1)
		end

		test "once extended, can extend templates in new context", ctx do
			assert "three" = Enum.at(ctx.output, 2)
		end

		test "extends template two missions up", ctx do
			assert "two" = Enum.at(ctx.output, 3)
		end

		test "extends supermission template, not template in same mission", ctx do
			assert "four" = Enum.at(ctx.output, 4)
			assert "four shouldn't be here" not in ctx.output
		end

		test "extends template that extends another template", ctx do
			assert "nested_complete" = Enum.at(ctx.output, 5)
		end

		test "if no template found, exit", ctx do
			assert "premature end" = Enum.at(ctx.output, 6)
			assert "unreachable end" not in ctx.output
			assert 199 = ctx.exit_code
		end
	end
end
