defmodule Cingi.Mixfile do
	use Mix.Project

	def project do
		[
			app: :cingi,
			version: "0.1.0",
			elixir: "~> 1.5",
			escript: [main_module: Cingi.CLI],
			start_permanent: Mix.env == :prod,
			deps: deps()
		]
	end

	# Run "mix help compile.app" to learn about applications.
	def application do
		[
			applications: [
				:porcelain,
				:yaml_elixir
			],
			extra_applications: [:logger],
			mod: {Cingi, []}
		]
	end

	# Run "mix help deps" to learn about dependencies.
	defp deps do
		[
			{:porcelain, "~> 2.0"},
			{:yaml_elixir, "~> 1.3.1"},
			{:temp, "~> 0.4"}
		]
	end
end
