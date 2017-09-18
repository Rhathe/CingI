defmodule Cingi.Mixfile do
	use Mix.Project

	def project do
		[
			app: :cingi,
			name: "CingI",
			version: "0.1.0",
			elixir: "~> 1.5",
			escript: [
				main_module: Cingi.CLI,
				emu_args: "-noinput",
			],
			source_url: "https://github.com/Rhathe/CingI",
			start_permanent: Mix.env == :prod,
			deps: deps(),
			package: package(),
			description: """
			Continuous-ing Integration (...core). A distributed pipeline-based
			command line task runner providing the core functionality for a CI server.
			""",
		]
	end

	# Run "mix help compile.app" to learn about applications.
	def application do
		[
			applications: [
				:porcelain,
				:yaml_elixir,
				:gproc,
			],
			extra_applications: [:logger],
			mod: {Cingi, []},
		]
	end

	# Run "mix help deps" to learn about dependencies.
	defp deps do
		[
			{:porcelain, "~> 2.0"},
			{:yaml_elixir, "~> 1.3.1"},
			{:temp, "~> 0.4"},
			{:gproc, "~> 0.5.0"},
		]
	end

	defp package do
		[
			maintainers: ["Ramon Sandoval"],
			licenses: ["MIT"],
			links: %{github: "https://github.com/Rhathe/CingI"},
			files: ~w(lib priv README.md config c-ing-i-logo.svg LICENSE),
		]
	end
end
