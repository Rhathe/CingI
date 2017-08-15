defmodule Cingi.Headquarters do
	alias Cingi.Headquarters
	alias Cingi.MissionStatement
	use GenServer

	defstruct [
		mission_reports: [],
		queued_missions: [],
		running_missions: [],
		finished_missions: []
	]

	def start_link(opts) do
		GenServer.start_link(__MODULE__, opts)
	end

	def send_yaml(pid, yaml_tuple) do
		GenServer.call(pid, {:yaml, yaml_tuple})
	end

	# Server Callbacks

	def init(_) do
		headquarters = %Headquarters{}
		{:ok, headquarters}
	end

	def handle_call({:yaml, yaml_tuple}, _from, headquarters) do
		missionReport = MissionStatement.start_link(yaml_tuple ++ [headquarters: self()])
		reports = headquarters[:mission_reports] ++ missionReport
		{:reply, missionReport, %Headquarters{headquarters | mission_reports: reports}}
	end
end
