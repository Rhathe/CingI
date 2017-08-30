defmodule Cingi.Headquarters do
	@moduledoc """
	Headquarters manage all the branches within the cluster
	and assign mission to branches based on capacity.
	There should only be one Headquarters at each cluster.
	If a branch is started without a Headquarters, and
	doesn't intend to connect to an existing cluster,
	a Headquarters should be created for it.
	"""

	alias Cingi.Headquarters
	use GenServer

	defstruct [
		node: nil,
		branch_pids: [],
	]

	def start_link(_ \\ []) do
		GenServer.start_link(__MODULE__, [], name: {:global, :headquarters})
	end

	def get_or_create() do
		if not GenServer.whereis {:global, :headquarters} do start_link() end
		GenServer.call {:global, :headquarters}, :get
	end

	# Server Callbacks

	def init(_) do
		headquarters = %Headquarters{node: Node.self}
		{:ok, headquarters}
	end

	def handle_call(:get, _from, hq) do
		{:reply, hq, hq}
	end
end
