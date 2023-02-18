package.path = package.path  .. "./?.lua;/etc/haproxy/scripts/?.lua;/etc/haproxy/libs/?.lua"

local pow_difficulty = tonumber(os.getenv("POW_DIFFICULTY") or 18)

-- setup initial server backends based on hosts.map
function setup_servers()
	if pow_difficulty < 8 then
		error("POW_DIFFICULTY must be > 8. Around 16-32 is better")
	end
	local backend_name = os.getenv("BACKEND_NAME")
	local server_prefix = os.getenv("SERVER_PREFIX")
	if backend_name == nil or server_prefix == nil then
		return;
	end
	local handle = io.open("/etc/haproxy/map/hosts.map", "r")
	local line = handle:read("*line")
	local counter = 1
	-- NOTE: using tcp socket to interact with runtime API because lua can't add servers
	local tcp = core.tcp();
	tcp:settimeout(1);
	tcp:connect("127.0.0.1", 2000); --TODO: configurable port
	while line do
		local domain, backend_host = line:match("([^%s]+)%s+([^%s]+)")
		-- local host_split = utils.split(backend_host, ":")
		-- local backend_hostname = host_split[1]
		-- local backend_port = host_split[2]
		core.set_map("/etc/haproxy/map/backends.map", domain, server_prefix..counter)
		-- local proxy = core.proxies[backend_name].servers[server_prefix..counter]
		-- proxy:set_addr(backend_hostname, backend_port)
		-- proxy:set_ready()
		local server_name = "servers/websrv"..counter
		tcp:send(string.format("add server %s %s check\n", server_name, backend_host))
		tcp:send(string.format("enable server %s\n", server_name))
		line = handle:read("*line")
		counter = counter + 1
	end
	handle:close()
	tcp:close()
end

core.register_task(setup_servers)
