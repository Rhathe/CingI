defmodule CingiMissionPlansTest do
	use ExUnit.Case
	alias Cingi.Headquarters

	test "runs inputs file" do
		res = Helper.create_mission_report([file: "test/mission_plans/inputs.plan"])
		pid = res[:pid]
		Headquarters.resume(pid)
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
end
