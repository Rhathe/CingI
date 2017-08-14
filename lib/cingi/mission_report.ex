defmodule Cingi.MissionReport do
	alias Cingi.MissionReport
	use GenServer

	defstruct [
		map: %{},
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

	def init([:string, yaml]) do
		missionReport = %MissionReport{map: YamlElixir.read_from_string yaml}
		{:ok, missionReport}
	end

	def init([:file, path]) do
		missionReport = %MissionReport{map: YamlElixir.read_from_file path}
		{:ok, missionReport}
	end
end

