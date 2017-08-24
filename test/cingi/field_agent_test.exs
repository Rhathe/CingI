defmodule CingiFieldAgentTest do
	use ExUnit.Case
	alias Cingi.FieldAgent
	alias Cingi.Mission
	alias Cingi.Outpost
	doctest FieldAgent

	describe "with a blank outpost" do
		setup [:blank_outpost]

		test "runs with mission args", ctx do
			{fpid, mpid} = fa_with_cmd("echo blah", ctx.outpost_pid)
			Helper.check_exit_code mpid

			assert %{
				cmd: "echo blah",
				output: [[data: "blah\n", type: :out, timestamp: _, pid: []]],
				finished: true,
				running: false,
				exit_code: 0,
				field_agent_pid: ^fpid,
			} = Mission.get(mpid)
		end

		test "runs no mission args", ctx do
			{fpid, mpid} = fa_with_cmd("echo", ctx.outpost_pid)
			Helper.check_exit_code mpid

			assert %{
				cmd: "echo",
				output: [[data: "\n", type: :out, timestamp: _, pid: []]],
				finished: true,
				running: false,
				exit_code: 0,
				field_agent_pid: ^fpid,
			} = Mission.get(mpid)
		end

		test "runs mission with appropriate running/finished flag", ctx do
			{fpid, mpid} = fa_with_cmd("ncat -l -i 1 9000", ctx.outpost_pid)
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
				output: [[data: "blah", type: :out, timestamp: _, pid: []]],
				finished: true,
				running: false,
				exit_code: 0,
				field_agent_pid: ^fpid,
			} = Mission.get(mpid)
		end

		test "runs mission with args and ampersands", ctx do
			{fpid, mpid} = fa_with_cmd("echo blah1 && sleep 0.1 && echo blah2", ctx.outpost_pid)
			Helper.check_exit_code mpid

			assert %{
				cmd: "echo blah1 && sleep 0.1 && echo blah2",
				output: [
					[data: "blah1\n", type: :out, timestamp: _, pid: []],
					[data: "blah2\n", type: :out, timestamp: _, pid: []]
				],
				finished: true,
				running: false,
				exit_code: 0,
				field_agent_pid: ^fpid,
			} = Mission.get(mpid)
		end
	end

	defp blank_outpost(_) do
		{:ok, pid} = Outpost.start_link
		[outpost_pid: pid]
	end

	defp fa_with_cmd(cmd, opid) do
		{:ok, mpid} = Mission.start_link [cmd: cmd]
		{:ok, fpid} = FieldAgent.start_link(mission_pid: mpid, outpost_pid: opid)
		{fpid, mpid}
	end
end
