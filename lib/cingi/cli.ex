defmodule Cingi.CLI do
	def main(args) do
		args |> parse_args |> process
	end

	def process([]) do
		IO.puts "No arguments given"
	end

	def process(options) do
		yaml_opts = [file: options[:file], cli_pid: self()]
		Cingi.Headquarters.create_report :main_hq, yaml_opts
		receive do
			{:report, report_pid} -> IO.puts "finished"
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
