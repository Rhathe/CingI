defmodule CingiTest do
  use ExUnit.Case
  doctest Cingi

  test "greets the world" do
    assert Cingi.hello() == :world
  end
end
