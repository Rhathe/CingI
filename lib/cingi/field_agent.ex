defmodule Cingi.FieldAgent do
	@moduledoc """
	Field agents are processes that are assigned a mission by an outpost
	Typically they run the bash command in the same environment as the outpost
	They run on the same noide as the outpost but report the output to the mission
	"""

	alias Cingi.FieldAgent
	alias Cingi.Headquarters
	alias Cingi.Outpost
	alias Cingi.Mission
	use GenServer

	defstruct [
		mission_pid: nil,
		outpost_pid: nil,
		bash_pid: nil,
	]

	# Client API

	def start_link(args \\ []) do
		GenServer.start_link(__MODULE__, args, [])
	end

	def get(pid) do
		GenServer.call(pid, :get)
	end

	def run_mission(pid) do
		GenServer.cast(pid, :run_mission)
	end

	def run_bash_process(pid) do
		GenServer.cast(pid, :run_bash_process)
	end

	# Server Callbacks

	def init(opts) do
		field_agent = struct(FieldAgent, opts)
		FieldAgent.run_mission(self())
		{:ok, field_agent}
	end

	def handle_call(:get, _from, field_agent) do
		{:reply, field_agent, field_agent}
	end

	def handle_cast(:run_bash_process, field_agent) do
		mission = Mission.get(field_agent.mission_pid)
		script = "./priv/bin/wrapper.sh"
		cmds = [mission.cmd] ++ case mission.input_file do
			nil -> []
			_ -> [mission.input_file]
		end

		# Porcelain's basic driver only takes nil or :out for err
		err = case mission.output_with_stderr do
			true -> :out
			false -> nil
		end

		proc = Porcelain.spawn(script, cmds, out: {:send, self()}, err: err)
		{:noreply, %FieldAgent{field_agent | bash_pid: proc}}
	end

	def handle_cast(:run_mission, field_agent) do
		mpid = field_agent.mission_pid
		mission = Mission.get(mpid)

		cond do
			mission.cmd -> FieldAgent.run_bash_process(self())
			mission.submissions -> Mission.run_submissions(mpid)
		end

		Mission.set_as_running(mpid, self())
		Outpost.mission_has_run(field_agent.outpost_pid, mpid)

		{:noreply, field_agent}
	end

	#########
	# INFOS #
	#########

	def handle_info({_pid, :data, :out, data}, field_agent) do
		add_to_output(field_agent, data: data, type: :out)
	end

	def handle_info({_pid, :data, :err, data}, field_agent) do
		add_to_output(field_agent, data: data, type: :err)
	end

	def handle_info({_pid, :result, result}, field_agent) do
		Mission.send_result(field_agent.mission_pid, nil, result)
		{:noreply, field_agent}
	end

	defp add_to_output(field_agent, opts) do
		time = :os.system_time(:millisecond)
		Mission.send(field_agent.mission_pid, opts ++ [timestamp: time, pid: []])
		{:noreply, field_agent}
	end
end
