defmodule Cingi.Outpost do
	@moduledoc """
	Outposts are processes set up by commanders to connect to headquarters
	and receive missions. Outposts have to set up the environment,
	like a workspace folder, or can be set up inside docker containers
	"""

	alias Cingi.Outpost
	use GenServer

	defstruct [
		setup: nil
	]

	# Client API

	def start_link(opts) do
		GenServer.start_link(__MODULE__, opts)
	end

	# Server Callbacks

	def init(_) do
		{:ok, %Outpost{}}
	end
end
