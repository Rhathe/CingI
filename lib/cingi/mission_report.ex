defmodule Cingi.MissionReport do
	alias Cingi.MissionReport
	use GenServer

	defstruct [
		mission_statements: %{},
		headquarters: nil,
		missions: %{}
	]

	# Client API

	def start_link(opts) do
		GenServer.start_link(__MODULE__, opts)
	end

	def get(pid) do
		GenServer.call(pid, {:get})
	end

	def initialized_mission(pid, opts) do
		GenServer.call(pid, opts)
	end

	# Server Callbacks

	def init([string: yaml, headquarters: hq]) do
		report = start_missions(YamlElixir.read_from_string(yaml), hq)
		{:ok, report}
	end

	def init([file: path, headquarters: hq]) do
		report = start_missions(YamlElixir.read_from_file(path), hq)
		{:ok, report}
	end

	def start_missions(map, hq) do
		missionReport = %MissionReport{mission_statements: map, headquarters: hq}
		Mission.start_link([decoded_yml: missionReport, mission_report_pid: self()])
		missionReport
	end

	def handle_cast({:mission_init, mission_pid, _}, _from, report) do
		missions = report[:missions] ++ [mission_pid]
		{:noreply, %MissionReport{report | missions: missions}}
	end
end
