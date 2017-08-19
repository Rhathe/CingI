defmodule Cingi.MissionReport do
	alias Cingi.MissionReport
	alias Cingi.Headquarters
	use GenServer

	defstruct [
		plan: %{},
		headquarters: nil,
		missions: []
	]

	# Client API

	def start_link(opts) do
		GenServer.start_link(__MODULE__, opts)
	end

	def initialized_mission(pid, mission_pid) do
		GenServer.cast(pid, {:mission_init, mission_pid})
	end

	def init_mission(pid, opts) do
		GenServer.cast(pid, {:init_mission, opts})
	end

	def get(pid) do
		GenServer.call(pid, :get)
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
		name = Map.get(map, "name", "MAIN")
		map = Map.put(map, "name", name)
		MissionReport.init_mission(self(), [decoded_yaml: map])
		%MissionReport{plan: map, headquarters: hq}
	end

	def handle_cast({:init_mission, opts}, report) do
		opts = opts ++ [report_pid: self()]
		Headquarters.init_mission(report.headquarters, opts)
		{:noreply, report}
	end

	def handle_cast({:mission_init, mission_pid}, report) do
		missions = report.missions ++ [mission_pid]
		{:noreply, %MissionReport{report | missions: missions}}
	end

	def handle_call(:get, _from, report) do
		{:reply, report, report}
	end
end
