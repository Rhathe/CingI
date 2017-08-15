defmodule Cingi.MissionReport do
	alias Cingi.MissionReport
	use GenServer

	defstruct [
		map: %{},
		starting_mission: nil,
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

	# Server Callbacks

	def init([string: yaml, headquarters: hq]) do
		missionReport = %MissionReport{map: YamlElixir.read_from_string(yaml), headquarters: hq}
		{:ok, missionReport}
	end

	def init([file: path, headquarters: hq]) do
		missionReport = %MissionReport{map: YamlElixir.read_from_file(path), headquarters: hq}
		{:ok, missionReport}
	end
end

