defmodule Cingi do
	# See https://hexdocs.pm/elixir/Application.html
	# for more information on OTP Applications
	@moduledoc false

	use Application

	def start(_type, _args) do
		name = {:global, Node.self}

		# List all child processes to be supervised
		children = [
			# Starts a worker by calling: Cingi.Worker.start_link(arg)
			{Cingi.Branch, name: name},
		]

		# See https://hexdocs.pm/elixir/Supervisor.html
		# for other strategies and supported options
		opts = [strategy: :one_for_one, name: Cingi.Supervisor]
		send(self(), :register_name)
		ret = Supervisor.start_link(children, opts)

		pid = GenServer.whereis name
		Process.register pid, :local_branch
		ret
	end
end
