defmodule CingiOutpostPlansTest do
	use ExUnit.Case

	describe "simple outpost plan" do
		setup do
			Helper.run_mission_report("test/mission_plans/outposts/simple.plan")
		end

		test "right amount of output", ctx do
			assert 8 = length(ctx.output)
		end

		test "directory changes from setup", ctx do
			assert "dir /tmp" in ctx.output
		end

		test "static env works", ctx do
			assert "TEST: test_value" in ctx.output
		end

		test "env key is set", ctx do
			assert "ENV1: env1_value" in ctx.output
		end

		test "env val is set", ctx do
			assert "ENV3: VAL2" in ctx.output
		end

		test "env key and val is set", ctx do
			assert "ENV2: VAL1" in ctx.output
		end

		test "missing key is not set", ctx do
			assert "MISSING_KEY: " in ctx.output
		end
	end

	describe "env and dir outpost plan" do
		setup do
			Helper.run_mission_report("test/mission_plans/outposts/env_and_dir.plan")
		end

		test "right amount of output", ctx do
			assert 9 = length(ctx.output)
		end

		test "directory changes from utpost", ctx do
			assert "start pwd: /" in ctx.output
			assert "newdir pwd: /tmp" in ctx.output
			assert "end pwd: /" in ctx.output
		end

		test "env set by outpost", ctx do
			assert "START, TEST_OUTPOSTS: test_outposts_value" in ctx.output
		end

		test "env carries through in submissions", ctx do
			assert "TEST_OUTPOSTS 1: test_outposts_value" in ctx.output
		end

		test "env is added in sub outposts", ctx do
			assert "TEST_OUTPOSTS 2: test_outposts_2_value" in ctx.output
			assert "TEST_OUTPOSTS 3: test_outposts_3_value" in ctx.output
		end

		test "env is overriden in sub outpost", ctx do
			assert "TEST_OUTPOSTS 4: test_outposts_override" in ctx.output
		end

		test "env does not get reset by sub outposts", ctx do
			assert "END, TEST_OUTPOSTS: test_outposts_value" in ctx.output
		end
	end
end
