defmodule CingiExtendsFilePlanTest do
	use ExUnit.Case

	describe "extends file" do
		setup do
			Helper.run_mission_report("test/mission_plans/extends/file.yaml")
		end

		test "right amount of output", ctx do
			assert 3 = length(ctx.output)
		end

		test "can extend file created in outpost setup", ctx do
			assert "in_extends_file_2" = Enum.at(ctx.output, 0)
		end

		test "can extend template that extends file in template", ctx do
			assert "in_extends_file_1" = Enum.at(ctx.output, 1)
		end

		test "can still extend template along with extending file", ctx do
			assert "two" = Enum.at(ctx.output, 2)
		end
	end
end
