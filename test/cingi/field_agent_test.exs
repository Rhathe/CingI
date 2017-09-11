defmodule CingiFieldAgentTest do
	use ExUnit.Case
	alias Cingi.FieldAgent
	alias Cingi.Mission
	alias Cingi.Outpost
	doctest FieldAgent

	import ExUnit.CaptureIO

	describe "with a mock outpost" do
		setup [:mock_outpost]

		test "constructs with yaml command", ctx do
			{_, mpid} = fa_with_plan("echo 1", ctx.outpost_pid)
			mission = Mission.get(mpid)
			assert mission.key == "echo_1"
			assert mission.cmd == "echo 1"
			assert mission.submissions == nil
		end

		test "constructs with yaml map", ctx do
			{_, mpid} = fa_with_plan(%{
				"name" => "mission_1",
				"missions" => "echo 1",
			}, ctx.outpost_pid)
			mission = Mission.get(mpid)
			assert mission.key == "mission_1"
			assert mission.cmd == "echo 1"
			assert mission.submissions == nil
		end

		test "constructs with yaml map and just command, key is missions", ctx do
			{_, mpid} = fa_with_plan(%{
				"missions" => "echo 1",
			}, ctx.outpost_pid)
			mission = Mission.get(mpid)
			assert mission.key == "echo_1"
			assert mission.cmd == "echo 1"
			assert mission.submissions == nil
		end

		test "constructs with yaml map and just command, keys are missions", ctx do
			{_, mpid} = fa_with_plan(%{
				"missions" => %{
					"missions" => "echo 1"
				}
			}, ctx.outpost_pid)
			mission = Mission.get(mpid)
			assert mission.key == ""
			assert mission.cmd == nil
			assert mission.submissions == %{"missions" => "echo 1"}
		end

		test "constructs with yaml map and array of commands", ctx do
			{_, mpid} = fa_with_plan(%{
				"name" => "mission_1",
				"missions" => ["echo 1", "echo 2"],
			}, ctx.outpost_pid)
			mission = Mission.get(mpid)
			assert mission.key == "mission_1"
			assert mission.cmd == nil
			assert mission.submissions == [{"echo 1", 0}, {"echo 2", 1}]
		end

		test "constructs with yaml map and map of commands", ctx do
			{_, mpid} = fa_with_plan(%{
				"name" => "mission_1",
				"missions" => %{
					"submission 1" => "echo 1",
					"submission 2" => %{
						"name" => "new submission 2",
						"missions" => "echo 2"
					}
				},
			}, ctx.outpost_pid)
			mission = Mission.get(mpid)
			assert mission.key == "mission_1"
			assert mission.cmd == nil
			assert mission.submissions == %{
				"submission 1" => "echo 1",
				"submission 2" => %{
					"name" => "new submission 2",
					"missions" => "echo 2"
				}
			}
		end
	end

	describe "with a blank outpost, running mission" do
		setup [:blank_outpost]

		test "runs with mission args", ctx do
			{fpid, mpid} = fa_with_plan("echo blah", ctx.outpost_pid)
			Helper.check_exit_code mpid

			assert %{
				cmd: "echo blah",
				output: [[data: "blah\n", type: :out, timestamp: _, field_agent_pid: _, pid: []]],
				finished: true,
				running: false,
				exit_code: 0,
				field_agent_pid: ^fpid,
			} = Mission.get(mpid)
		end

		test "runs no mission args", ctx do
			{fpid, mpid} = fa_with_plan("echo", ctx.outpost_pid)
			Helper.check_exit_code mpid

			assert %{
				cmd: "echo",
				output: [[data: "\n", type: :out, timestamp: _, field_agent_pid: _, pid: []]],
				finished: true,
				running: false,
				exit_code: 0,
				field_agent_pid: ^fpid,
			} = Mission.get(mpid)
		end

		test "runs mission with appropriate running/finished flag", ctx do
			{fpid, mpid} = fa_with_plan("ncat -l -i 1 9000", ctx.outpost_pid)
			FieldAgent.get(fpid) # flush

			assert %{
				cmd: "ncat -l -i 1 9000",
				output: [],
				finished: false,
				running: true,
				exit_code: nil,
				field_agent_pid: ^fpid,
			} = Mission.get(mpid)

			Porcelain.spawn("bash", [ "-c", "echo -n blah | ncat localhost 9000"])
			Helper.check_exit_code mpid

			assert %{
				cmd: "ncat -l -i 1 9000",
				output: [[data: "blah", type: :out, timestamp: _, field_agent_pid: _, pid: []]],
				finished: true,
				running: false,
				exit_code: 0,
				field_agent_pid: ^fpid,
			} = Mission.get(mpid)
		end

		test "runs mission with args and ampersands", ctx do
			{fpid, mpid} = fa_with_plan("echo blah1 && sleep 0.1 && echo blah2", ctx.outpost_pid)
			Helper.check_exit_code mpid

			assert %{
				cmd: "echo blah1 && sleep 0.1 && echo blah2",
				output: [
					[data: "blah1\n", type: :out, timestamp: _, field_agent_pid: _, pid: []],
					[data: "blah2\n", type: :out, timestamp: _, field_agent_pid: _, pid: []]
				],
				finished: true,
				running: false,
				exit_code: 0,
				field_agent_pid: ^fpid,
			} = Mission.get(mpid)
		end

		test "replaces empty mission with an easy exit command", ctx do
			execute = fn ->
				{_, mpid} = fa_with_plan(nil, ctx.outpost_pid)
				Helper.check_exit_code mpid

				assert %{
					cmd: "exit 199",
					mission_plan: %{},
					output: [],
					input_file: "$IN",
					submissions_num: 0,
					running: false,
				} = Mission.get(mpid)
			end

			assert capture_io(:stderr, execute) =~ "Must have cmd or submissions, got %{}"
		end

		test "kills bash process", ctx do
			{fpid, mpid} = fa_with_plan("ncat -l -i 2 19009", ctx.outpost_pid)
			FieldAgent.stop fpid
			Helper.check_exit_code mpid

			assert %{
				cmd: "ncat -l -i 2 19009",
				output: [],
				finished: true,
				running: false,
				exit_code: 137,
				field_agent_pid: ^fpid,
			} = Mission.get(mpid)
		end

		test "killing mission kills submission process", ctx do
			opid = ctx.outpost_pid
			{:ok, mpid1} = Mission.start_link [mission_plan: %{"missions" => ["echo 1"]}]
			{:ok, fpid1} = FieldAgent.start_link(mission_pid: mpid1, outpost_pid: opid)

			Mission.run_submissions(mpid1)
			FieldAgent.stop fpid1

			{:ok, mpid2} = Mission.start_link [mission_plan: "sleep 1; exit 198", supermission_pid: mpid1]
			{:ok, fpid2} = FieldAgent.start_link(mission_pid: mpid2, outpost_pid: opid)

			Helper.check_exit_code mpid2

			assert %{
				cmd: "sleep 1; exit 198",
				output: [],
				finished: true,
				running: false,
				exit_code: 137,
				field_agent_pid: ^fpid2,
			} = Mission.get(mpid2)
		end
	end

	defp mock_outpost(_) do
		{:ok, pid} = MockGenServer.start_link
		[outpost_pid: pid]
	end

	defp blank_outpost(_) do
		{:ok, pid} = Outpost.start_link
		[outpost_pid: pid]
	end

	defp fa_with_plan(plan, opid) do
		{:ok, mpid} = Mission.start_link [mission_plan: plan]
		{:ok, fpid} = FieldAgent.start_link(mission_pid: mpid, outpost_pid: opid)
		Helper.wait_for_valid_mission(mpid)
		{fpid, mpid}
	end
end
