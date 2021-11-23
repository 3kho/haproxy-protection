local _M = {}

local sha = require("sha")
local secret_bucket_duration = 43200 -- 60 * 60 * 12 -- 12 hours

function _M.generate_secret(context, salt, is_applet, iterations)
	local start_sec = core.now()['sec']
	local bucket = start_sec - (start_sec % secret_bucket_duration)
	local ip = context.sf:src()
	local user_agent = ""
--TODO: fix bug here making this not be same value
--	if is_applet == true then
--		user_agent = context.headers['user-agent'] or {}
--		user_agent = user_agent[0]
--	else
--		user_agent = context.sf:req_hdr('user-agent')
--	end
	if iterations == nil then
		--hcaptcha secret is just this
		return context.sc:xxh32(salt .. bucket .. ip .. user_agent)
	else
		--POW secret adds the iteration number by the user
		return sha.sha1(salt .. bucket .. ip .. user_agent .. iterations)
	end
end

return _M

