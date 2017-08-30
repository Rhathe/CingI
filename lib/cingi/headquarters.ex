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
		pid: nil,
		name: nil,
		branch_pids: [],
	]

	def start_link(opts \\ []) do
		GenServer.start_link(__MODULE__, opts, opts)
	end

	# Server Callbacks

	def init(opts) do
		headquarters = %Headquarters{
			node: Node.self,
			pid: self(),
			name: opts[:name],
		}
		{:ok, headquarters}
	end
end
