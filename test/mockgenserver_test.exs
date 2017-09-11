defmodule MockGenServer do
	use GenServer

	# Client API

	def start_link(args \\ []) do
		GenServer.start_link(__MODULE__, args, [])
	end

	# Server Callbacks

	def init(opts) do
		{:ok, %{opts: opts, calls: []}}
	end

	def handle_cast(args, mock) do
		calls = mock.calls ++ [{:cast, args}]
		{:noreply, Map.merge(mock, %{calls: calls})}
	end
end
