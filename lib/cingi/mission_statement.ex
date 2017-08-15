defmodule Cingi.MissionStatement do
	alias Cingi.MissionStatement
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
		missionStatement = %MissionStatement{map: YamlElixir.read_from_string yaml}
		{:ok, missionStatement}
	end

	def init([:file, path]) do
		missionStatement = %MissionStatement{map: YamlElixir.read_from_file path}
		{:ok, missionStatement}
	end
end

