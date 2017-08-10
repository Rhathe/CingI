defmodule CingiBasherTest do
	use ExUnit.Case
	alias Cingi.Basher
	doctest Basher

	test "creates basher" do
		pid = create_basher("echo")
		assert Basher.get(pid) == %Basher{cmd: "echo", output: [], running: false}
	end

	test "runs basher no args" do
		pid = create_basher("echo")
		Basher.run(pid)
		check_exit_code(pid)
		assert Basher.get(pid) == %Basher{cmd: "echo", output: ["\n"], running: true, exit_code: 0}
	end

	test "runs basher with args" do
		pid = create_basher("echo blah")
		Basher.run(pid)
		check_exit_code(pid)
		assert Basher.get(pid) == %Basher{cmd: "echo blah", output: ["blah\n"], running: true, exit_code: 0}
	end

	test "runs basher with args and ampersands" do
		pid = create_basher("echo blah && echo blah2")
		Basher.run(pid)
		check_exit_code(pid)
		assert Basher.get(pid) == %Basher{cmd: "echo blah && echo blah2", output: ["blah\nblah2\n"], running: true, exit_code: 0}
	end

	defp create_basher(cmd) do
		{:ok, pid} = Basher.start_link(cmd)
		pid
	end

	defp check_exit_code(pid) do
		basher = Basher.get(pid)
		case basher.exit_code do
			Null -> check_exit_code(pid)
			_ -> basher.exit_code
		end
	end
end
