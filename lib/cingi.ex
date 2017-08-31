defmodule Cingi do
	# See https://hexdocs.pm/elixir/Application.html
	# for more information on OTP Applications
	@moduledoc false

	use Application

	def start(_type, _args) do
		# List all child processes to be supervised
		children = [
			# Starts a worker by calling: Cingi.Worker.start_link(arg)
			{Cingi.Branch, name: :local_branch},
		]

		# See https://hexdocs.pm/elixir/Supervisor.html
		# for other strategies and supported options
		opts = [strategy: :one_for_one, name: Cingi.Supervisor]
		send(self(), :register_name)

		Supervisor.start_link(children, opts)
	end
end
