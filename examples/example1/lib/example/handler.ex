defmodule Example.Handler do
	use Sockjs.Handler

	init do
		IO.puts "!!!!!!!INIT HANDLER!!!!!!!"
		reply([404, "Unauthorized access"])
		close(404, "Unauthorized access")
	end

	handle do
		IO.puts "!!!!!!HANDLING REQUEST" 
	end

	terminate do
		IO.puts "!!!!!!!!!REQUEST TERMINATED!!!!!" 
	end

end