defmodule Cingi.Mission do
	alias Cingi.Mission
	use GenServer

	defstruct [
		cmd: nil,
		submissions: nil,
		submission_pids: [],
		output: [],
		running: false,
		parallel: false,
		exit_code: nil
	]

	# Client API

	def start_link(opts) do
		GenServer.start_link(__MODULE__, opts)
	end

	def run(pid) do
		GenServer.cast(pid, {:run})
	end

	def get(pid) do
		GenServer.call(pid, {:get})
	end

	# Server Callbacks

	def init(opts) do
		mission = struct(Mission, opts)
		cond do
			mission.cmd -> :ok
			mission.submissions -> :ok
		end
		{:ok, mission}
	end

	def handle_cast({:run}, mission) do
		submission_pids = cond do
			mission.cmd -> run_cmd(mission.cmd)
			mission.submissions -> run_submissions(mission)
		end
		{:noreply, %Mission{mission | running: true, submission_pids: submission_pids}}
	end

	def run_cmd(cmd) do
		Porcelain.spawn("bash", [ "-c", cmd], out: {:send, self()})
		[]
	end

	def run_submissions(mission) do
		Enum.map(mission.submissions, fn submission ->
			{:ok, pid} = Mission.start_link([cmd: submission])
			Mission.run(pid)
			pid
		end)
	end

	def handle_call({:get}, _from, mission) do
		{:reply, mission, mission}
	end

	def handle_info({_pid, :data, :out, data}, mission) do
		{:noreply, %Mission{mission | output: mission.output ++ [data]}}
	end

	def handle_info({_pid, :result, result}, mission) do
		{:noreply, %Mission{mission | exit_code: result.status}}
	end
end
