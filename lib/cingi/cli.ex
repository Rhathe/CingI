defmodule Cingi.CLI do
	def main(args) do
		args |> parse_args |> process
	end

	def process([]) do
		IO.puts "No arguments given"
	end

	def process(options) do
		Cingi.Branch.link_cli(:local_branch, self())
		connect_or_headquarters(options[:file], options[:connect_to], options[:min_branch_num])
	end

	def connect_or_headquarters(file, nil, min_branch_num) do
		Cingi.Headquarters.start_link(name: {:global, :hq})
		Cingi.Headquarters.link_branch({:global, :hq}, :local_branch)
		wait_for_branches(min_branch_num)
		start_missions(file)
	end

	def connect_or_headquarters(_file, host, nil) do
		Node.connect String.to_atom(host)
		Cingi.Headquarters.link_branch({:global, :hq}, :local_branch)
		receive do
			{:report, _} -> :ok
		end
	end

	def connect_or_headquarters(_, _, _) do
		raise "Cannot have both connect_to and min_branch_num options"
	end

	def start_missions(nil) do
	end

	def start_missions(file) do
		yaml_opts = [file: file, cli_pid: self()]
		Cingi.Branch.create_report :local_branch, yaml_opts
		receive do
			{:report, _} -> :ok
		end
	end

	defp parse_args(args) do
		{options, _, _} = OptionParser.parse(args,
			switches: [
				file: :string,
				min_branch_num: :integer,
				connect_to: :string,
			]
		)
		options
	end

	def wait_for_branches(countdown) do
		countdown = countdown || 0
		case countdown do
			0 -> :ok
			n when n < 0 -> :ok
			n -> receive do
				{:branch_connect, _} -> wait_for_branches(n - 1)
			end
		end
	end
end
