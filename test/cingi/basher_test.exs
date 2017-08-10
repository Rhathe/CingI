defmodule CingiBasherTest do
	use ExUnit.Case
	doctest Cingi.Basher

	test "creates basher" do
		pid = create_basher("echo")
		assert Cingi.Basher.get(pid) == %Cingi.Basher{cmd: "echo", output: [], running: false}
	end

	test "runs basher no args" do
		pid = create_basher("echo")
		Cingi.Basher.run(pid)
		assert Cingi.Basher.get(pid) == %Cingi.Basher{cmd: "echo", output: [{"\n", 0}], running: true}
	end

	test "runs basher with args" do
		pid = create_basher("echo blah")
		Cingi.Basher.run(pid)
		assert Cingi.Basher.get(pid) == %Cingi.Basher{cmd: "echo blah", output: [{"blah\n", 0}], running: true}
	end

	defp create_basher(cmd) do
		{:ok, pid} = Cingi.Basher.start_link(cmd)
		pid
	end
end
