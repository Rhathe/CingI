defmodule Cingi.Mission do
	alias Cingi.Mission
	use GenServer

	defstruct [
		cmd: nil,
		supermission_pid: nil,
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

	def send(pid, submission_pid, data) do
		GenServer.cast(pid, {submission_pid, :data, :out, data})
	end

	def finish_submission(pid, submission_pid, result) do
		GenServer.cast(pid, {submission_pid, :result, result})
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

	def handle_cast({pid, :data, :out, data}, mission) do
		handle_info({pid, :data, :out, data}, mission)
	end

	def handle_cast({pid, :result, result}, mission) do
		handle_info({pid, :result, result}, mission)
	end

	def run_cmd(cmd) do
		Porcelain.spawn("bash", [ "-c", cmd], out: {:send, self()})
		[]
	end

	def run_submissions(mission) do
		Enum.map(mission.submissions, fn submission ->
			{:ok, pid} = Mission.start_link([cmd: submission, supermission_pid: self()])
			Mission.run(pid)
			pid
		end)
	end

	def handle_call({:get}, _from, mission) do
		{:reply, mission, mission}
	end


	def handle_info({_pid, :data, :out, data}, mission) do
		if mission.supermission_pid do Mission.send(mission.supermission_pid, self(), data) end
		{:noreply, %Mission{mission | output: mission.output ++ [data]}}
	end

	def handle_info({_pid, :result, result}, mission) do
		if mission.supermission_pid do Mission.finish_submission(mission.supermission_pid, self(), result) end
		exit_codes = Enum.map(mission.submission_pids, fn m -> Mission.get(m).exit_code end)
		exit_code = cond do
			length(exit_codes) == 0 -> result.status
			true -> cond do
				nil in exit_codes -> nil
				true -> Enum.at(exit_codes, 0)
			end
		end
		{:noreply, %Mission{mission | exit_code: exit_code}}
	end
end
