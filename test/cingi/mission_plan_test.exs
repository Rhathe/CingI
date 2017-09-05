defmodule CingiMissionPlansTest do
	use ExUnit.Case
	alias Cingi.Headquarters

	test "runs inputs file" do
		res = Helper.create_mission_report([file: "test/mission_plans/inputs.plan"])
		Headquarters.resume(res[:hq_pid])
		mission = Helper.check_exit_code(res[:mission_pid])
		output = mission.output
			|> Enum.map(&(&1[:data]))
			|> Enum.join("\n")
			|> String.split("\n", trim: true)

		{initial, next} = Enum.split output, 9
		{firstthird, next} = Enum.partition(next, &(case &1 do; "first, third: " <> _ -> true; _ -> false; end))
		{second, next} = Enum.partition(next, &(case &1 do; "second: " <> _ -> true; _ -> false; end))
		{within, next} = Enum.partition(next, &(case &1 do; "with in: " <> _ -> true; _ -> false; end))
		{without, next} = Enum.partition(next, &(case &1 do; "without in: " <> _ -> true; _ -> false; end))

		assert [
			"first1",
			"first2",
			"first3",
			"second1",
			"second2",
			"third1",
			"third2",
			"third3",
			"third4",
		] = Enum.sort(initial)

		assert [
			"first, third: first1",
			"first, third: first2",
			"first, third: first3",
			"first, third: third1",
			"first, third: third2",
			"first, third: third3",
			"first, third: third4",
		] = firstthird

		assert [
			"second: second1",
			"second: second2",
		] = second

		assert [
			"with in: first1",
			"with in: first2",
			"with in: first3",
			"with in: second1",
			"with in: second2",
			"with in: third1",
			"with in: third2",
			"with in: third3",
			"with in: third4",
		] = Enum.sort(within)

		assert [
			"without in: first1",
			"without in: first2",
			"without in: first3",
			"without in: second1",
			"without in: second2",
			"without in: third1",
			"without in: third2",
			"without in: third3",
			"without in: third4",
		] = Enum.sort(without)

		assert [] = next
	end

	test "runs when file" do
		res = Helper.create_mission_report([file: "test/mission_plans/when.plan"])
		Headquarters.resume(res[:hq_pid])
		mission = Helper.wait_for_finished(res[:mission_pid])
		output = mission.output
			|> Enum.map(&(&1[:data]))
			|> Enum.join("\n")
			|> String.split("\n", trim: true)

		assert [
			"first",
			"second",
			a, b, c, d,
			"runs because parallel group exited with 0",
			"end",
		]  = output

		assert [
			"runs because of exit code 1",
			"runs because of failure",
			"runs because of outputs",
			"runs regardless",
		] = Enum.sort([a, b, c, d])
	end

	describe "runs outputs file" do
		setup do
			res = Helper.create_mission_report([file: "test/mission_plans/outputs.plan"])
			Headquarters.resume(res[:hq_pid])
			mission = Helper.wait_for_finished(res[:mission_pid])
			output = mission.output
				|> Enum.map(&(&1[:data]))
				|> Enum.join("\n")
				|> String.split("\n", trim: true)
			[output: output]
		end

		test "right amount of output", ctx do
			assert 13 = length(ctx.output)
		end

		test "first does not go through", ctx do
			assert "first1" not in ctx.output
			assert "first2" not in ctx.output
			assert "first3" not in ctx.output
		end

		test "second and third goes through", ctx do
			assert [
				"second1",
				"second2",
				"third2",
				"third3"
			] = ctx.output |> Enum.slice(0, 4) |> Enum.sort()
		end

		test "third filters indices", ctx do
			assert "third1" not in ctx.output
			assert "third4" not in ctx.output
		end

		test "hidden inputs can still be taken", ctx do
			firsts = Enum.filter(ctx.output, &(case &1 do; "first: " <> _ -> true; _ -> false end))
			assert "first: first3" in firsts
			assert "first: first1" not in firsts
			assert "first: first2" not in firsts
		end

		test "selective input has thirds first", ctx do
			outputs = Enum.filter(ctx.output, &(case &1 do; "third, second: " <> _ -> true; _ -> false end))
			assert [
				"third, second: third2",
				"third, second: third3",
				"third, second: second1",
				"third, second: second2",
			] = outputs
		end

		test "normal input", ctx do
			outputs = Enum.filter(ctx.output, &(case &1 do; "normal: " <> _ -> true; _ -> false end))
			assert [
				"normal: second1",
				"normal: second2",
				"normal: third2",
				"normal: third3",
			] = Enum.sort(outputs)
		end
	end
end
