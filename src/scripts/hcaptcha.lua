_M = {}

local url = require("url")
local utils = require("utils")
local cookie = require("cookie")
local json = require("json")
local sha = require("sha")
local randbytes = require("randbytes")
-- require("print_r")

local captcha_secret = os.getenv("HCAPTCHA_SECRET") or os.getenv("RECAPTCHA_SECRET")
local captcha_sitekey = os.getenv("HCAPTCHA_SITEKEY") or os.getenv("RECAPTCHA_SITEKEY")
local captcha_cookie_secret = os.getenv("CAPTCHA_COOKIE_SECRET")
local pow_cookie_secret = os.getenv("POW_COOKIE_SECRET")
local hmac_cookie_secret = os.getenv("HMAC_COOKIE_SECRET")
local ray_id = os.getenv("RAY_ID")

local captcha_map = Map.new("/etc/haproxy/ddos.map", Map._str);
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

function _M.setup_servers()
	local backend_name = os.getenv("BACKEND_NAME")
	local server_prefix = os.getenv("SERVER_PREFIX")
	if backend_name == nil or server_prefix == nil then
		return;
	end
	local hosts_map = Map.new("/etc/haproxy/hosts.map", Map._str);
	local handle = io.open("/etc/haproxy/hosts.map", "r")
	local line = handle:read("*line")
	local counter = 1
	while line do
		local domain, backend_host = line:match("([^%s]+)%s+([^%s]+)")
		local port_index = backend_host:match'^.*():'
		local backend_hostname = backend_host:sub(0, port_index-1)
		local backend_port = backend_host:sub(port_index + 1)
		core.set_map("/etc/haproxy/backends.map", domain, server_prefix..counter)
		local proxy = core.proxies[backend_name].servers[server_prefix..counter]
		proxy:set_addr(backend_hostname, backend_port)
		proxy:set_ready()
		line = handle:read("*line")
		counter = counter + 1
	end
	handle:close()
end

-- main page template
local body_template = [[
<!DOCTYPE html>
<html>
	<head>
		<meta name='viewport' content='width=device-width initial-scale=1'>
		<title>Hold on...</title>
		<style>
			:root{--text-color:#c5c8c6;--bg-color:#1d1f21}
			@media (prefers-color-scheme:light){:root{--text-color:#333;--bg-color:#EEE}}
			.h-captcha,.g-recaptcha{min-height:85px;display:block}
			.red{color:red;font-weight:bold}
			a,a:visited{color:var(--text-color)}
			body,html{height:100%%}
			body{display:flex;flex-direction:column;background-color:var(--bg-color);color:var(--text-color);font-family:Helvetica,Arial,sans-serif;max-width:1200px;margin:0 auto;padding: 0 20px}
			details{transition: border-left-color 0.5s;max-width:1200px;text-align:left;border-left: 2px solid var(--text-color);padding:10px}
			code{background-color:#dfdfdf30;border-radius:3px;padding:0 3px;}
			img,h3,p{margin:0 0 5px 0}
			footer{font-size:x-small;margin-top:auto;margin-bottom:20px;text-align:center}
			img{display:inline}
			.pt{padding-top:15vh;display:flex;align-items: center}
			.pt img{margin-right:10px}
			details[open]{border-left-color: #1400ff}
			.lds-ring{display:inline-block;position:relative;width:80px;height:80px}.lds-ring div{box-sizing:border-box;display:block;position:absolute;width:32px;height:32px;margin:10px;border:5px solid var(--text-color);border-radius:50%%;animation:lds-ring 1.2s cubic-bezier(0.5, 0, 0.5, 1) infinite;border-color:var(--text-color) transparent transparent transparent}.lds-ring div:nth-child(1){animation-delay:-0.45s}.lds-ring div:nth-child(2){animation-delay:-0.3s}.lds-ring div:nth-child(3){animation-delay:-0.15s}@keyframes lds-ring{0%%{transform:rotate(0deg)}100%%{transform:rotate(360deg)}}
		</style>
		<noscript>
			<style>.jsonly{display:none}</style>
		</noscript>
		<script src="/js/challenge.js"></script>
	</head>
	<body data-pow="%s">
		%s
		%s
		%s
		<noscript>
			<br>
			<p class="red">JavaScript is required on this page.</p>
			%s
		</noscript>
		<footer>
			<img src="/img/footerlogo.png" />
			<p>Security and Performance by <a href="https://BasedFlare.com">BasedFlare</a></p>
			<p>Node: <code>%s</code></p>
		</footer>
	</body>
</html>
]]

local noscript_extra_template = [[
			<details>
				<summary>No JavaScript?</summary>
				<ol>
					<li>
						<p>Run this in a linux terminal:</p>
						<code style="word-break: break-all;">
							echo "Q0g9IiQyIjtCPSIwMDQxIjtJPTA7RElGRj0kKCgxNiMke0NIOjA6MX0gKiAyKSk7d2hpbGUgdHJ1ZTsgZG8gSD0kKGVjaG8gLW4gJENIJEkgfCBzaGEyNTZzdW0pO0U9JHtIOiRESUZGOjR9O1tbICRFID09ICRCIF1dICYmIGVjaG8gJDEjJDIjJDMjJEkgJiYgZXhpdCAwOygoSSsrKSk7ZG9uZTs=" | base64 -d | bash -s %s %s %s
						</code>
					<li>Set a cookie named <code>z_ddos_pow</code> with the value as the script output, and path <code>/</code>.
					<li>Remove <code>/bot-check?</code> from the url, and reload the page.
				</ol>
			</details>
]]

-- title with favicon and hostname
local site_name_section_template = [[
		<h3 class="pt">
			<img src="/favicon.ico" width="32" height="32">
			%s
		</h3>
]]

-- spinner animation for proof of work
local pow_section_template = [[
		<h3>
			Checking your browser for robots 🤖
		</h3>
		<div class="jsonly">
			<div class="lds-ring"><div></div><div></div><div></div><div></div></div>
		</div>
]]

-- message, captcha form and submit button
local captcha_section_template = [[
		<h3>
			Please solve the captcha to continue.
		</h3>
		<form class="jsonly" method="POST">
			<div class="%s" data-sitekey="%s" data-callback="onCaptchaSubmit"></div>
			<script src="%s" async defer></script>
		</form>
]]

function _M.view(applet)
	local response_body = ""
	local response_status_code
	if applet.method == "GET" then
		-- get the user_key#challenge#sig
		local user_key = sha.bin_to_hex(randbytes(16))
		local challenge_hash = utils.generate_secret(applet, pow_cookie_secret, user_key, true)
		local signature = sha.hmac(sha.sha256, hmac_cookie_secret, user_key .. challenge_hash)
		local combined_challenge = user_key .. "#" .. challenge_hash .. "#" .. signature
		-- print_r(user_key)
		-- print_r(challenge_hash)
		-- print_r(signature)
		-- print_r(combined_challenge)

		-- define body sections
		local site_name_body = ""
		local captcha_body = ""
		local pow_body = ""
		local noscript_extra_body = ""

		-- check if captcha is enabled, path+domain priority, then just domain, and 0 otherwise
		local captcha_enabled = false
		local host = applet.headers['host'][0]
		local path = applet.qs; --because on /bot-check?/whatever, .qs (query string) holds the "path"

		local captcha_map_lookup = captcha_map:lookup(host..path) or captcha_map:lookup(host) or 0
		captcha_map_lookup = tonumber(captcha_map_lookup)
		if captcha_map_lookup == 2 then
			captcha_enabled = true
		end

		-- pow at least is always enabled when reaching bot-check page
		site_name_body = string.format(site_name_section_template, host)
		if captcha_enabled then
			captcha_body = string.format(captcha_section_template, captcha_classname, captcha_sitekey, captcha_script_src)
		else
			pow_body = pow_section_template
			noscript_extra_body = string.format(noscript_extra_template, user_key, challenge_hash, signature)
		end

		-- sub in the body sections
		response_body = string.format(body_template, combined_challenge, site_name_body, pow_body, captcha_body, noscript_extra_body, ray_id)
		response_status_code = 403
	elseif applet.method == "POST" then
		local parsed_body = url.parseQuery(applet.receive(applet))
		local user_captcha_response = parsed_body["h-captcha-response"] or parsed_body["g-recaptcha-response"]
		if user_captcha_response then
			local captcha_url = string.format(
				"https://%s%s",
				core.backends[captcha_backend_name].servers[captcha_backend_name]:get_addr(),
				captcha_siteverify_path
			)
			local captcha_body = url.buildQuery({
				secret=captcha_secret,
				response=user_captcha_response
			})
			local httpclient = core.httpclient()
			local res = httpclient:post{
				url=captcha_url,
				body=captcha_body,
				headers={
					[ "host" ] = { captcha_provider_domain },
					[ "content-type" ] = { "application/x-www-form-urlencoded" }
				}
			}
			local status, api_response = pcall(json.decode, res.body)
			if not status then
				api_response = {}
			end
			if api_response.success == true then
				-- for captcha, they dont need to solve a POW but we check the user_hash and sig later
				local user_key = sha.bin_to_hex(randbytes(16))
				local user_hash = utils.generate_secret(applet, captcha_cookie_secret, user_key, true)
				local signature = sha.hmac(sha.sha256, hmac_cookie_secret, user_key .. user_hash)
				local combined_cookie = user_key .. "#" .. user_hash .. "#" .. signature
				local secure_cookie_flag = " Secure=true;"
				if applet.sf:ssl_fc() == "0" then
					secure_cookie_flag = ""
				end
				applet:add_header(
					"set-cookie",
					string.format(
						"z_ddos_captcha=%s; Expires=Thu, 31-Dec-37 23:55:55 GMT; Path=/; SameSite=Strict;",
						combined_cookie,
						secure_cookie_flag
					)
				)
			end
		end
		-- if failed captcha, will just get sent back here so 302 is fine
		response_status_code = 302
		applet:add_header("location", applet.qs)
	else
		-- other methods
		response_status_code = 403
	end
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
	local received_captcha_cookie = parsed_request_cookies["z_ddos_captcha"] or ""
	local split_cookie = utils.split(received_captcha_cookie, "#")
	if #split_cookie ~= 3 then
		return
	end
	local given_user_key = split_cookie[1]
	local given_user_hash = split_cookie[2]
	local given_signature = split_cookie[3]
	-- regenerate the user hash and compare it
	local generated_user_hash = utils.generate_secret(txn, captcha_cookie_secret, given_user_key, false)
	if generated_user_hash ~= given_user_hash then
		return
	end
	-- regenerate the signature and compare it
	local generated_signature = sha.hmac(sha.sha256, hmac_cookie_secret, given_user_key .. given_user_hash)
	if given_signature == generated_signature then
		return txn:set_var("txn.captcha_passed", true)
	end
end

-- check if pow cookie is valid
function _M.check_pow_status(txn)
	local parsed_request_cookies = cookie.get_cookie_table(txn.sf:hdr("Cookie"))
	local received_pow_cookie = parsed_request_cookies["z_ddos_pow"] or ""
	-- split the cookie up
	local split_cookie = utils.split(received_pow_cookie, "#")
	if #split_cookie ~= 4 then
		return
	end
	local given_user_key = split_cookie[1]
	local given_challenge_hash = split_cookie[2]
	local given_signature = split_cookie[3]
	local given_nonce = split_cookie[4]
	-- regenerate the challenge and compare it
	local generated_challenge_hash = utils.generate_secret(txn, pow_cookie_secret, given_user_key, false)
	if given_challenge_hash ~= generated_challenge_hash then
		return
	end
	-- regenerate the signature and compare it
	local generated_signature = sha.hmac(sha.sha256, hmac_cookie_secret, given_user_key .. given_challenge_hash)
	if given_signature ~= generated_signature then
		return
	end
	-- check the work
	local completed_work = sha.sha256(generated_challenge_hash .. given_nonce)
	local challenge_offset = tonumber(generated_challenge_hash:sub(1,1),16) * 2
	if completed_work:sub(challenge_offset+1, challenge_offset+4) == '0041' then -- i dont know lua properly :^)
		return txn:set_var("txn.pow_passed", true)
	end
end

return _M
