Handlers.add("info", "Info", function(msg)
	msg.reply({
		Target = msg.From,
		["Memory-KiB-Used"] = tostring(collectgarbage("count")),
	})
end)

Handlers.add("loadBalances", "Load-Balances", function(msg)
	local balances = msg.Data
	local memoryBefore = collectgarbage("count")
	for address, balance in ipairs(balances) do
		Balances[address] = balance
	end
	-- collect garbage to free up memory
	collectgarbage()
	local memoryAfter = collectgarbage("count")
	msg.reply({
		Target = msg.From,
		["Memory-KiB-Before"] = tostring(memoryBefore),
		["Memory-KiB-After"] = tostring(memoryAfter),
		["Memory-KiB-Used"] = tostring(memoryAfter - memoryBefore),
	})
end)

Handlers.add("loadBalance", "Load-Balance", function(msg)
	local address = msg.Data.address
	local balance = msg.Data.balance
	Balances[address] = balance
	msg.reply({
		Target = msg.From,
		["Balance-Address"] = address,
		["Balance-Amount"] = balance,
	})
end)
