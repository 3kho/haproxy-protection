local _M = {}

function _M.get_hostname()
    local handler = io.popen ("/bin/hostname")
    local hostname = handler:read("*a") or ""
    handler:close()
    hostname =string.gsub(hostname, "\n$", "")
    return hostname
end

function _M.resolve_fqdn(fqdn)
    local handler = io.popen(string.format("dig +short %s | head -1", fqdn))
    local result = handler:read("*a")
    handler:close()
    return result:gsub("\n", "")
end

local secret_bucket_duration = 43200 -- 60 * 60 * 12 -- 12 hours
function _M.generate_secret(context, salt, is_applet)
	local start_sec = core.now()['sec']
	local bucket = start_sec - (start_sec % secret_bucket_duration)
    local ip = context.sf:src()
	local user_agent
	if is_applet == true then
		user_agent = context.headers['user-agent'] or {}
		user_agent = user_agent[0]
	else
		user_agent = context.sf:req_hdr('user-agent')
	end
    return context.sc:xxh64(salt .. bucket .. ip .. user_agent)
end

return _M

