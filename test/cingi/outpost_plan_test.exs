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

		test "directory changes from outpost", ctx do
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

	describe "nested setup outpost plan" do
		setup do
			Helper.run_mission_report("test/mission_plans/outposts/setup.yaml")
		end

		setup ctx do
			reports = ctx.res[:branch_pid]
				|> Cingi.Branch.get
				|> (fn(b) -> b.mission_reports end).()
				|> Enum.map(&Cingi.MissionReport.get/1)
			[reports: reports]
		end

		setup ctx do
			setup_output = ctx.reports
				|> Enum.slice(1, 3)
				|> Enum.map(&(Enum.at(&1.missions, 0)))
				|> Enum.map(&Cingi.Mission.get/1)
				|> Enum.map(&Helper.get_output/1)
			[setup_output: setup_output]
		end

		test "right amount of output", ctx do
			assert 13 = length(ctx.output)
		end

		test "right amount of mission plans", ctx do
			assert 4 = length(ctx.reports)
		end

		test "top outpost starts first, because of the mission that runs before the outpost mission", ctx do
			assert "top setup" = ctx.setup_output |> Enum.at(0) |> Enum.at(0)
		end

		test "bottom outpost starts second, outposts are not started until run by a command", ctx do
			assert "bottom setup" = ctx.setup_output |> Enum.at(1) |> Enum.at(0)
		end

		test "middle outpost runs last, triggered by bottom outpost needing environement to run in", ctx do
			assert "middle setup" = ctx.setup_output |> Enum.at(2) |> Enum.at(0)
		end

		test "top setup has no envs set", ctx do
			assert [
				"top setup",
				"top setup TMP_DIR_1: ",
				"top setup TMP_DIR_2: ",
				"top setup TMP_DIR_3: ",
				"{\"dir\": \"/tmp/tmp." <> _,
			] = Enum.at(ctx.setup_output, 0)
		end

		test "middle setup inherited envs and dir from top", ctx do
			assert [
				"middle setup",
				"middle setup pwd: /tmp/tmp." <> key1,
				"middle setup TMP_DIR_1: /tmp/tmp." <> key2,
				"middle setup TMP_DIR_2: /tmp/tmp." <> key3,
				"middle setup TMP_DIR_3: /tmp/tmp." <> key4,
				"{\"dir\": \"/tmp/tmp." <> key5,
			] = Enum.at(ctx.setup_output, 2)

			# Top set all TMP_DIR envs as the working directory
			assert key1 == key2
			assert key1 == key3
			assert key1 == key4

			# Middle setting new working directory as subdirectory
			assert key5 =~ key1
			assert key5 != key1
		end

		test "bottom setup inherited envs and dir from middle", ctx do
			assert [
				"bottom setup",
				"bottom setup pwd: /tmp/tmp." <> key1,
				"bottom setup TMP_DIR_1: /tmp/tmp." <> key2,
				"bottom setup TMP_DIR_2: /tmp/tmp." <> key3,
				"bottom setup TMP_DIR_3: first_override",
			] = Enum.at(ctx.setup_output, 1)

			assert key1 == key3 # Current directory matches env override
			assert key1 =~ key2 # Current directory is subdirectory of original directory
			assert key1 != key2 # Exclusively subdirectory
		end

		test "top missions set in tmp directory from top outpost", ctx do
			output = Enum.at(ctx.output, 0)
			assert "top pwd: /tmp/tmp." <> key = output
			assert Regex.match?(~r/^[a-zA-Z0-9]+$/, key)
		end

		test "middle missions set in tmp directory from middle outpost", ctx do
			output = Enum.at(ctx.output, 5)
			assert "middle pwd: /tmp/tmp." <> key = output
			assert Regex.match?(~r/^[a-zA-Z0-9]+\/tmp\.[a-zA-Z0-9]+$/, key)
		end

		test "bottom missions set in tmp directory from middle outpost", ctx do
			output = Enum.at(ctx.output, 1)
			assert "bottom pwd: /tmp/tmp." <> key = output
			assert Regex.match?(~r/^[a-zA-Z0-9]+\/tmp\.[a-zA-Z0-9]+$/, key)
		end

		test "top missions get envs set in outpost", ctx do
			assert [
				"top TMP_DIR_1: /tmp/tmp." <> k1,
				"top TMP_DIR_2: /tmp/tmp." <> k2,
				"top TMP_DIR_3: /tmp/tmp." <> k3,
			] = Enum.slice(ctx.output, 10, 3)

			assert k1 == k2
			assert k1 == k3
		end

		test "middle missions get envs set in outpost", ctx do
			assert [
				"middle TMP_DIR_1: /tmp/tmp." <> k1,
				"middle TMP_DIR_2: /tmp/tmp." <> k2,
				"middle TMP_DIR_3: first_override",
			] = Enum.slice(ctx.output, 6, 3)

			# Middle setting env as new subdirectory
			assert k2 =~ k1
			assert k1 != k2
		end

		test "bottom missions get envs set in outpost", ctx do
			assert [
				"bottom TMP_DIR_1: /tmp/tmp." <> k1,
				"bottom TMP_DIR_2: /tmp/tmp." <> k2,
				"bottom TMP_DIR_3: second_override",
			] = Enum.slice(ctx.output, 2, 3)

			# Middle setting env as new subdirectory
			assert k2 =~ k1
			assert k1 != k2
		end

		test "can run files made in outpost setup", ctx do
			assert "inside_tmp_dir" = Enum.at(ctx.output, 9)
		end
	end

	describe "setup fail outpost plan" do
		setup do
			Helper.run_mission_report("test/mission_plans/outposts/setup_fail.yaml")
		end

		test "right output", ctx do
			assert ["should run"] = ctx.output
		end

		test "right exit code", ctx do
			assert 137 = ctx.exit_code
		end
	end
end
