_M = {}

-- Testing only
-- require("socket")
-- require("print_r")

-- main libs
local url = require("url")
local utils = require("utils")
local cookie = require("cookie")
local json = require("json")
local sha = require("sha")
local randbytes = require("randbytes")
local templates = require("templates")

-- POW
local pow_difficulty = tonumber(os.getenv("POW_DIFFICULTY") or 18)

-- argon2
local argon2 = require("argon2")
local argon_kb = tonumber(os.getenv("ARGON_KB") or 6000)
local argon_time = tonumber(os.getenv("ARGON_TIME") or 1)
argon2.t_cost(argon_time)
argon2.m_cost(argon_kb)
argon2.parallelism(1)
argon2.hash_len(32)
argon2.variant(argon2.variants.argon2_id)

-- sha2
-- TODO

-- environment variables
local captcha_secret = os.getenv("HCAPTCHA_SECRET") or os.getenv("RECAPTCHA_SECRET")
local captcha_sitekey = os.getenv("HCAPTCHA_SITEKEY") or os.getenv("RECAPTCHA_SITEKEY")
local captcha_cookie_secret = os.getenv("CAPTCHA_COOKIE_SECRET")
local pow_cookie_secret = os.getenv("POW_COOKIE_SECRET")
local hmac_cookie_secret = os.getenv("HMAC_COOKIE_SECRET")
local ray_id = os.getenv("RAY_ID")

-- load captcha map and set hcaptcha/recaptch based off env vars
local captcha_map = Map.new("/etc/haproxy/map/ddos.map", Map._str);
local captcha_provider_domain = ""
local captcha_classname = ""
local captcha_script_src = ""
local captcha_siteverify_path = ""
local captcha_backend_name = ""
if os.getenv("HCAPTCHA_SITEKEY") then
	captcha_provider_domain = "hcaptcha.com"
	captcha_classname = "h-captcha"
	captcha_script_src = "https://hcaptcha.com/1/api.js"
	captcha_siteverify_path = "/siteverify"
	captcha_backend_name = "hcaptcha"
else
	captcha_provider_domain = "www.google.com"
	captcha_classname = "g-recaptcha"
	captcha_script_src = "https://www.google.com/recaptcha/api.js"
	captcha_siteverify_path = "/recaptcha/api/siteverify"
	captcha_backend_name = "recaptcha"
end

-- setup initial server backends based on hosts.map into backends.map
function _M.setup_servers()
	if pow_difficulty < 8 then
		error("POW_DIFFICULTY must be > 8. Around 16-32 is better")
	end
	local backend_name = os.getenv("BACKEND_NAME")
	local server_prefix = os.getenv("SERVER_PREFIX")
	if backend_name == nil or server_prefix == nil then
		return;
	end
	local hosts_map = Map.new("/etc/haproxy/map/hosts.map", Map._str);
	local handle = io.open("/etc/haproxy/map/hosts.map", "r")
	local line = handle:read("*line")
	local counter = 1
	while line do
		local domain, backend_host = line:match("([^%s]+)%s+([^%s]+)")
		local port_index = backend_host:match'^.*():'
		local backend_hostname = backend_host:sub(0, port_index-1)
		local backend_port = backend_host:sub(port_index + 1)
		core.set_map("/etc/haproxy/map/backends.map", domain, server_prefix..counter)
		local proxy = core.proxies[backend_name].servers[server_prefix..counter]
		proxy:set_addr(backend_hostname, backend_port)
		proxy:set_ready()
		line = handle:read("*line")
		counter = counter + 1
	end
	handle:close()
end

-- kill a tor circuit
function _M.kill_tor_circuit(txn)
	local ip = txn.sf:src()
	if ip:sub(1,19) ~= "fc00:dead:beef:4dad" then
		return -- not a tor circuit id/ip. we shouldn't get here, but just in case.
	end
	-- split the IP, take the last 2 sections
	local split_ip = utils.split(ip, ":")
	local aa_bb = split_ip[5] or "0000"
	local cc_dd = split_ip[6] or "0000"
	aa_bb = string.rep("0", 4 - #aa_bb) .. aa_bb
	cc_dd = string.rep("0", 4 - #cc_dd) .. cc_dd
	-- convert the last 2 sections to a number from hex, which makes the circuit ID
	local circuit_identifier = tonumber(aa_bb..cc_dd, 16)
	print('Closing Tor circuit ID: '..circuit_identifier..', "IP": '..ip)
	utils.send_tor_control_port(circuit_identifier)
end

function _M.view(applet)

	-- set response body and declare status code
	local response_body = ""
	local response_status_code

	-- if request is GET, serve the challenge page
	if applet.method == "GET" then

		-- get the user_key#challenge#sig
		local user_key = sha.bin_to_hex(randbytes(16))
		local challenge_hash, expiry = utils.generate_challenge(applet, pow_cookie_secret, user_key, true)
		local signature = sha.hmac(sha.sha3_256, hmac_cookie_secret, user_key .. challenge_hash .. expiry)
		local combined_challenge = user_key .. "#" .. challenge_hash .. "#" .. expiry .. "#" .. signature

		-- define body sections
		local site_name_body = ""
		local captcha_body = ""
		local pow_body = ""
		local noscript_extra_body = ""

		-- check if captcha is enabled, path+domain priority, then just domain, and 0 otherwise
		local captcha_enabled = false
		local host = applet.headers['host'][0]
		local path = applet.qs; --because on /.basedflare/bot-check?/whatever, .qs (query string) holds the "path"

		local captcha_map_lookup = captcha_map:lookup(host..path) or captcha_map:lookup(host) or 0
		captcha_map_lookup = tonumber(captcha_map_lookup)
		if captcha_map_lookup == 2 then
			captcha_enabled = true
		end

		-- pow at least is always enabled when reaching bot-check page
		site_name_body = string.format(templates.site_name_section, host)
		if captcha_enabled then
			captcha_body = string.format(templates.captcha_section, captcha_classname,
				captcha_sitekey, captcha_script_src)
		else
			pow_body = templates.pow_section
			noscript_extra_body = string.format(templates.noscript_extra, user_key,
				challenge_hash, expiry, signature, math.ceil(pow_difficulty/8), 
				argon_time, argon_kb)
		end

		-- sub in the body sections
		response_body = string.format(templates.body, combined_challenge,
			pow_difficulty, argon_time, argon_kb,
			site_name_body, pow_body, captcha_body, noscript_extra_body, ray_id)
		response_status_code = 403

	-- if request is POST, check the answer to the pow/cookie
	elseif applet.method == "POST" then

		-- if they fail, set a var for use in ACLs later
		local valid_submission = false

		-- parsed POST body
		local parsed_body = url.parseQuery(applet.receive(applet))

		-- whether to set cookies sent as secure or not
		local secure_cookie_flag = " Secure=true;"
		if applet.sf:ssl_fc() == "0" then
			secure_cookie_flag = ""
		end

		-- handle setting the POW cookie
		local user_pow_response = parsed_body["pow_response"]
		local matched_expiry = 0 -- ensure captcha cookie expiry matches POW cookie
		if user_pow_response then

			-- split the response up (makes the nojs submission easier because it can be a single field)
			local split_response = utils.split(user_pow_response, "#")

			if #split_response == 5 then
				local given_user_key = split_response[1]
				local given_challenge_hash = split_response[2]
				local given_expiry = split_response[3]
				local given_signature = split_response[4]
				local given_answer = split_response[5]

				-- expiry check
				local number_expiry = tonumber(given_expiry, 10)
				if number_expiry ~= nil and number_expiry > core.now()['sec'] then

					-- regenerate the challenge and compare it
					local generated_challenge_hash = utils.generate_challenge(applet, pow_cookie_secret, given_user_key, true)

					if given_challenge_hash == generated_challenge_hash then

						-- regenerate the signature and compare it
						local generated_signature = sha.hmac(sha.sha3_256, hmac_cookie_secret, given_user_key .. given_challenge_hash .. given_expiry)

						if given_signature == generated_signature then

							-- do the work with their given answer
							local full_hash = argon2.hash_encoded(given_challenge_hash .. given_answer, given_user_key)

							-- check the output is correct
							local hash_output = utils.split(full_hash, '$')[6]:sub(0, 43) -- https://github.com/thibaultcha/lua-argon2/issues/37
							local hex_hash_output = sha.bin_to_hex(sha.base64_to_bin(hash_output));

							if utils.checkdiff(hex_hash_output, pow_difficulty) then

								-- the answer was good, give them a cookie
								local signature = sha.hmac(sha.sha3_256, hmac_cookie_secret, given_user_key .. given_challenge_hash .. given_expiry .. given_answer)
								local combined_cookie = given_user_key .. "#" .. given_challenge_hash .. "#" .. given_expiry .. "#" .. given_answer .. "#" .. signature
								applet:add_header(
									"set-cookie",
									string.format(
										"_basedflare_pow=%s; Expires=Thu, 31-Dec-37 23:55:55 GMT; Path=/; Domain=.%s; SameSite=Strict; HttpOnly;%s",
										combined_cookie,
										applet.headers['host'][0],
										secure_cookie_flag
									)
								)
								valid_submission = true

							end
						end
					end
				end
			end
		end

		-- handle setting the captcha cookie
		local user_captcha_response = parsed_body["h-captcha-response"] or parsed_body["g-recaptcha-response"]
		if valid_submission and user_captcha_response then -- only check captcha if POW is already correct
			-- format the url for verifying the captcha response
			local captcha_url = string.format(
				"https://%s%s",
				core.backends[captcha_backend_name].servers[captcha_backend_name]:get_addr(),
				captcha_siteverify_path
			)
			-- construct the captcha body to send to the captcha url
			local captcha_body = url.buildQuery({
				secret=captcha_secret,
				response=user_captcha_response
			})
			-- instantiate an http client and make the request
			local httpclient = core.httpclient()
			local res = httpclient:post{
				url=captcha_url,
				body=captcha_body,
				headers={
					[ "host" ] = { captcha_provider_domain },
					[ "content-type" ] = { "application/x-www-form-urlencoded" }
				}
			}
			-- try parsing the response as json
			local status, api_response = pcall(json.decode, res.body)
			if not status then
				api_response = {}
			end
			-- the response was good i.e the captcha provider says they passed, give them a cookie
			if api_response.success == true then

				local user_key = sha.bin_to_hex(randbytes(16))
				local user_hash = utils.generate_challenge(applet, captcha_cookie_secret, user_key, true)
				local signature = sha.hmac(sha.sha3_256, hmac_cookie_secret, user_key .. user_hash .. matched_expiry)
				local combined_cookie = user_key .. "#" .. user_hash .. "#" .. matched_expiry .. "#" .. signature
				applet:add_header(
					"set-cookie",
					string.format(
						"_basedflare_captcha=%s; Expires=Thu, 31-Dec-37 23:55:55 GMT; Path=/; Domain=.%s; SameSite=Strict; HttpOnly;%s",
						combined_cookie,
						applet.headers['host'][0],
						secure_cookie_flag
					)
				)
				valid_submission = valid_submission and true

			end
		end

		if not valid_submission then
			_M.kill_tor_circuit(applet)
		end

		-- redirect them to their desired page in applet.qs (query string)
		-- if they didn't get the appropriate cookies they will be sent back to the challenge page
		response_status_code = 302
		applet:add_header("location", applet.qs)

	-- else if its another http method, just 403 them
	else
		response_status_code = 403
	end

	-- finish sending the response
	applet:set_status(response_status_code)
	applet:add_header("content-type", "text/html; charset=utf-8")
	applet:add_header("content-length", string.len(response_body))
	applet:start_response()
	applet:send(response_body)

end

-- check if captcha is enabled, path+domain priority, then just domain, and 0 otherwise
function _M.decide_checks_necessary(txn)
	local host = txn.sf:hdr("Host")
	local path = txn.sf:path();
	local captcha_map_lookup = captcha_map:lookup(host..path) or captcha_map:lookup(host) or 0
	captcha_map_lookup = tonumber(captcha_map_lookup)
	if captcha_map_lookup == 1 then
		txn:set_var("txn.validate_pow", true)
	elseif captcha_map_lookup == 2 then
		txn:set_var("txn.validate_captcha", true)
		txn:set_var("txn.validate_pow", true)
	end
	-- otherwise, domain+path was set to 0 (whitelist) or there is no entry in the map
end

-- check if captcha cookie is valid, separate secret from POW
function _M.check_captcha_status(txn)
	local parsed_request_cookies = cookie.get_cookie_table(txn.sf:hdr("Cookie"))
	local received_captcha_cookie = parsed_request_cookies["_basedflare_captcha"] or ""
	-- split the cookie up
	local split_cookie = utils.split(received_captcha_cookie, "#")
	if #split_cookie ~= 4 then
		return
	end
	local given_user_key = split_cookie[1]
	local given_user_hash = split_cookie[2]
	local given_expiry = split_cookie[3]
	local given_signature = split_cookie[4]

	-- expiry check
	local number_expiry = tonumber(given_expiry, 10)
	if number_expiry == nil or number_expiry <= core.now()['sec'] then
		return
	end
	-- regenerate the user hash and compare it
	local generated_user_hash = utils.generate_challenge(txn, captcha_cookie_secret, given_user_key, false)
	if generated_user_hash ~= given_user_hash then
		return
	end
	-- regenerate the signature and compare it
	local generated_signature = sha.hmac(sha.sha3_256, hmac_cookie_secret, given_user_key .. given_user_hash .. given_expiry)
	if given_signature == generated_signature then
		return txn:set_var("txn.captcha_passed", true)
	end
end

-- check if pow cookie is valid
function _M.check_pow_status(txn)
	local parsed_request_cookies = cookie.get_cookie_table(txn.sf:hdr("Cookie"))
	local received_pow_cookie = parsed_request_cookies["_basedflare_pow"] or ""
	-- split the cookie up
	local split_cookie = utils.split(received_pow_cookie, "#")
	if #split_cookie ~= 5 then
		return
	end
	local given_user_key = split_cookie[1]
	local given_challenge_hash = split_cookie[2]
	local given_expiry = split_cookie[3]
	local given_answer = split_cookie[4]
	local given_signature = split_cookie[5]

	-- expiry check
	local number_expiry = tonumber(given_expiry, 10)
	if number_expiry == nil or number_expiry <= core.now()['sec'] then
		return
	end
	-- regenerate the challenge and compare it
	local generated_challenge_hash = utils.generate_challenge(txn, pow_cookie_secret, given_user_key, false)
	if given_challenge_hash ~= generated_challenge_hash then
		return
	end
	-- regenerate the signature and compare it
	local generated_signature = sha.hmac(sha.sha3_256, hmac_cookie_secret, given_user_key .. given_challenge_hash .. given_expiry .. given_answer)
	if given_signature == generated_signature then
		return txn:set_var("txn.pow_passed", true)
	end
end

return _M
