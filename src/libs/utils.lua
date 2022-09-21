local _M = {}

local sha = require("sha")
local secret_bucket_duration = tonumber(os.getenv("BUCKET_DURATION"))
local challenge_includes_ip = os.getenv("CHALLENGE_INCLUDES_IP")

function _M.generate_secret(context, salt, user_key, is_applet)

	-- time bucket for expiry
	local start_sec = core.now()['sec']
	local bucket = start_sec - (start_sec % secret_bucket_duration)

	-- optional IP to lock challenges/user_keys to IP (for clearnet or single-onion aka 99% of cases)
	local ip = ""
	if challenge_includes_ip then
		ip = context.sf:src()
	end

	-- user agent to counter very dumb spammers
	local user_agent = ""
	if is_applet == true then
		user_agent = context.headers['user-agent'] or {}
		user_agent = user_agent[0] or ""
	else
		--note req_fhdr not req_hdr otherwise commas in useragent become a delimiter
		user_agent = context.sf:req_fhdr('user-agent') or ""
	end

	return sha.sha256(salt .. bucket .. ip .. user_key .. user_agent)

end

function _M.split(inputstr, sep)
	local t = {}
	for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
		table.insert(t, str)
	end
	return t
end

return _M

