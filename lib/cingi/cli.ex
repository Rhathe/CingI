defmodule Cingi.CLI do
	def main(args) do
		args |> parse_args |> process
	end

	def process([]) do
		IO.puts "No arguments given"
	end

	def process(options) do
		yaml_opts = [file: options[:file], cli_pid: self()]
		Cingi.Headquarters.start_link(name: {:global, :hq})
		Cingi.Headquarters.link_branch({:global, :hq}, :local_branch)
		Cingi.Branch.create_report :local_branch, yaml_opts
		receive do
			{:report, _} -> :ok
		end
	end

	defp parse_args(args) do
		{options, _, _} = OptionParser.parse(args,
			switches: [
				file: :string
			]
		)
		options
	end
end
