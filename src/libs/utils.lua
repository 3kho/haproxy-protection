local _M = {}

local sha = require("sha")
local secret_bucket_duration = tonumber(os.getenv("BUCKET_DURATION"))

function _M.generate_secret(context, salt, is_applet, iterations)
	local start_sec = core.now()['sec']
	local bucket = start_sec - (start_sec % secret_bucket_duration)
	local ip = context.sf:src()
	local user_agent = ""
	if is_applet == true then
		user_agent = context.headers['user-agent'] or {}
		user_agent = user_agent[0] or ""
	else
		--note req_fhdr not req_hdr otherwise commas in useragent become a delimiter
		user_agent = context.sf:req_fhdr('user-agent') or ""
	end
	if iterations == nil then
		--hcaptcha secret is just this
		return context.sc:xxh32(salt .. bucket .. ip .. user_agent)
	else
		--POW secret adds the iteration number by the user
		return sha.sha1(salt .. bucket .. ip .. user_agent .. iterations)
	end
end

return _M

