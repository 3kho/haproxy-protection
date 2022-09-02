_M = {}

local url = require("url")
local utils = require("utils")
local cookie = require("cookie")
local json = require("json")
local sha = require("sha")

local captcha_secret = os.getenv("HCAPTCHA_SECRET")
local captcha_sitekey = os.getenv("HCAPTCHA_SITEKEY")
local hcaptcha_cookie_secret = os.getenv("CAPTCHA_COOKIE_SECRET")
local pow_cookie_secret = os.getenv("POW_COOKIE_SECRET")
local ray_id = os.getenv("RAY_ID")

local captcha_provider_domain = "hcaptcha.com"
local captcha_map = Map.new("/etc/haproxy/ddos.map", Map._str);

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
			.h-captcha{min-height:85px;display:block}
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
	</head>
	<body data-pow="%s">
		%s
		%s
		<noscript>
			<br>
			<p class="red">JavaScript is required on this page.</p>
			%s
		</noscript>
		<footer>
			<img src="/img/footerlogo.png" />
			<p>Security and Performance by <a href="https://kikeflare.com">Kikeflare</a></p>
			<p>Node: <code>%s</code></p>
		</footer>
		<script src="/js/sha1.js"></script>
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
							echo "Q0g9IiQxIjtCPSJiMDBiIjtJPTA7RElGRj0kKCgxNiMke0NIOjA6MX0gKiAyKSk7d2hpbGUgdHJ1ZTsgZG8gSD0kKGVjaG8gLW4gJENIJEkgfCBzaGExc3VtKTtFPSR7SDokRElGRjo0fTtbWyAkRSA9PSAkQiBdXSAmJiBlY2hvICRJICYmIGV4aXQgMDsoKEkrKykpO2RvbmU7Cg==" | base64 -d | bash -s %s
						</code>
					<li>Set a cookie named <code>z_ddos_pow</code> with the value as the number the script outputs, and path <code>/</code>.
					<li>Remove <code>/bot-check?</code> from the url, and load the page again.
				</ol>
			</details>
]]

-- 3 dots animation for proof of work
local pow_section_template = [[
		<h3 class="pt">
			<img src="/favicon.ico" width="32" height="32">
			%s
		</h3>
		<h3>
			Checking your browser for robots 🤖
		</h3>
		<div class="jsonly">
			<div class="lds-ring"><div></div><div></div><div></div><div></div></div>
		</div>
]]

-- message, hcaptcha form and submit button
local captcha_section_template = [[
		<p class="pt">Please solve the captcha to continue.</p>
		<form class="jsonly" method="POST">
			<div class="h-captcha" data-sitekey="%s"></div>
			<script src="https://hcaptcha.com/1/api.js" async defer></script>
			<input type="submit" value="Calculating proof of work..." disabled>
		</form>
]]

function _M.view(applet)
	local response_body = ""
	local response_status_code
	if applet.method == "GET" then

		-- get challenge string for proof of work
		generated_work = utils.generate_secret(applet, pow_cookie_secret, true, "")

		-- define body sections
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
		--

		-- pow at least is always enabled when reaching bot-check page
		if captcha_enabled then
			captcha_body = string.format(captcha_section_template, captcha_sitekey)
		else
			pow_body = string.format(pow_section_template, host)
			noscript_extra_body = string.format(noscript_extra_template, generated_work)
		end

		-- sub in the body sections
		response_body = string.format(body_template, generated_work, pow_body, captcha_body, noscript_extra_body, ray_id)
		response_status_code = 403
	elseif applet.method == "POST" then
		local parsed_body = url.parseQuery(applet.receive(applet))
		if parsed_body["h-captcha-response"] then
			local hcaptcha_url = string.format(
				"https://%s/siteverify",
				core.backends["hcaptcha"].servers["hcaptcha"]:get_addr()
			)
			local hcaptcha_body = url.buildQuery({
				secret=captcha_secret,
				response=parsed_body["h-captcha-response"]
			})
			local httpclient = core.httpclient()
			local res = httpclient:post{
				url=hcaptcha_url,
				body=hcaptcha_body,
				headers={
					[ "host" ] = { captcha_provider_domain },
					[ "content-type" ] = { "application/x-www-form-urlencoded" }
				}
			}
			local status, api_response = pcall(json.decode, res.body)
			--require("print_r")
			--print_r(hcaptcha_body)
			--print_r(res)
			--print_r(api_response)
			if not status then
				api_response = {}
			end
			if api_response.success == true then
				local floating_hash = utils.generate_secret(applet, hcaptcha_cookie_secret, true, nil)
				applet:add_header(
					"set-cookie",
					string.format("z_ddos_captcha=%s; expires=Thu, 31-Dec-37 23:55:55 GMT; Path=/; SameSite=Strict; Secure=true;", floating_hash)
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

-- check if captcha token is valid, separate secret from POW
function _M.check_captcha_status(txn)
	local parsed_request_cookies = cookie.get_cookie_table(txn.sf:hdr("Cookie"))
	local expected_cookie = utils.generate_secret(txn, hcaptcha_cookie_secret, false, nil)
	if parsed_request_cookies["z_ddos_captcha"] == expected_cookie then
		return txn:set_var("txn.captcha_passed", true)
	end
end

-- check if pow token is valid
function _M.check_pow_status(txn)
	local parsed_request_cookies = cookie.get_cookie_table(txn.sf:hdr("Cookie"))
	if parsed_request_cookies["z_ddos_pow"] then
		local generated_work = utils.generate_secret(txn, pow_cookie_secret, false, "")
		local iterations = parsed_request_cookies["z_ddos_pow"]
		local completed_work = sha.sha1(generated_work .. iterations)
		local challenge_offset = tonumber(generated_work:sub(1,1),16) * 2
		if completed_work:sub(challenge_offset+1, challenge_offset+4) == 'b00b' then -- i dont know lua properly :^)
			return txn:set_var("txn.pow_passed", true)
		end
	end
end

return _M
