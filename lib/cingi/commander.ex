defmodule Cingi.Commander do
	@moduledoc """
	Commanders are long running processes that are used to start missions
	They have a main_mission and a transforming_mission
	main_missions are the long running script process that output to standard out
	transforming_missions are optional missions take each line of main_mission's output,
	parses it, and returns it back to the commander ina suitable format.
	If the commander gets a line in an appropriate format, it'll
	start up a MissionReport and send it to its headquarters
	"""

	alias Cingi.Commander
	use GenServer

	defstruct [
		orders: nil,
		main_mission_pid: nil,
		transforming_mission_pid: nil,
		headquarters_pid: nil,
	]

	# Client API

	def start_link(opts) do
		GenServer.start_link(__MODULE__, opts)
	end

	# Server Callbacks

	def init(_) do
		{:ok, %Commander{}}
	end
end
