_M = {}

local url = require("url")
local http = require("http")
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

local captcha_map = Map.new("/etc/haproxy/no_captcha.map", Map._dom);

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
		    .b{display:inline-block;background:#6b93f7;border-radius:50%%;margin:10px;height:16px;width:16px;box-shadow:0 0 0 0 #6b93f720;transform:scale(1)}
		    .b:nth-of-type(1){animation:p 3s infinite}
		    .b:nth-of-type(2){animation:p 3s .5s infinite}
		    .b:nth-of-type(3){animation:p 3s 1s infinite}
		    @keyframes p{0%%{transform:scale(.95);box-shadow:0 0 0 0 #6b93f790}70%%{transform:scale(1);box-shadow:0 0 0 10px #6b93f700}100%%{transform:scale(.95);box-shadow:0 0 0 0 #6b93f700}}
		    .h-captcha{min-height:85px;display:block}
		    .red{color:red;font-weight:bold}
			a,a:visited{color:var(--text-color)}
			body,html{height:100%%}
			body{display:flex;flex-direction:column;background-color:var(--bg-color);color:var(--text-color);font-family:Helvetica,Arial,sans-serif;text-align:center;margin:0}
			h3,p{margin:3px}
			footer{font-size:small;margin-top:auto;margin-bottom:50px}h3{padding-top:30vh}
		</style>
		<noscript>
			<style>.jsonly{display:none}</style>
		</noscript>
	</head>
	<body data-pow="%s">
		<h3>Checking your browser for robots...</h3>
		%s
		%s
		<noscript>
			<p class="red">JavaScript is required on this page.</p>
		</noscript>
		<footer>
			<p>Protection by <a href="https://kikeflare.com">KikeFlare</a></p>
			<p>Vey ID: <code>%s</code></p>
		</footer>
		<script src="/js/sha1.js"></script>
	</body>
</html>
]]

-- 3 dots animation for proof of work
local pow_section_template = [[
		<div>
			<div class="b"></div>
			<div class="b"></div>
			<div class="b"></div>
		</div>
]]

-- message, hcaptcha form and submit button
local captcha_section_template = [[
		<p>Please solve the captcha to continue.</p>
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
    	generated_work = utils.generate_secret(applet, pow_cookie_secret, true, "")
    	local captcha_body = ""
    	local pow_body = ""
    	local captcha_enabled = false
	    local host = applet.headers['host'][0]
		loc = captcha_map:lookup(host);
		if loc == nil then
			captcha_enabled = true
		end
    	if captcha_enabled then
			captcha_body = string.format(captcha_section_template, captcha_sitekey)
    	else
    		pow_body = pow_section_template
    	end
        response_body = string.format(body_template, generated_work, pow_body, captcha_body, ray_id)
        response_status_code = 403
    elseif applet.method == "POST" then
        local parsed_body = url.parseQuery(applet.receive(applet))
        if parsed_body["h-captcha-response"] then
            local url = string.format(
                "https://%s/siteverify?secret=%s&response=%s",
                core.backends["hcaptcha"].servers["hcaptcha"]:get_addr(),
                captcha_secret,
                parsed_body["h-captcha-response"]
            )
            local res, err = http.get{url=url, headers={host=captcha_provider_domain} }
            local status, api_response = pcall(res.json, res)
            if not status then
                local original_error = api_response
                api_response = {}
            end
            if api_response.success == true then
                local floating_hash = utils.generate_secret(applet, hcaptcha_cookie_secret, true, nil)
                applet:add_header(
                    "set-cookie",
                    string.format("z_ddos_captcha=%s; expires=Thu, 31-Dec-37 23:55:55 GMT; Path=/; SameSite=Strict; Secure=true;", floating_hash)
                )
--            else
--                core.Debug("HCAPTCHA FAILED: " .. json.encode(api_response))
            end
        end
        response_status_code = 302
        applet:add_header("location", applet.qs)
    else
		--other methods
        response_status_code = 403
    end
    applet:set_status(response_status_code)
    applet:add_header("content-type", "text/html; charset=utf-8")
    applet:add_header("content-length", string.len(response_body))
    applet:start_response()
    applet:send(response_body)
end

function _M.check_captcha_status(txn)
    local parsed_request_cookies = cookie.get_cookie_table(txn.sf:hdr("Cookie"))
    local expected_cookie = utils.generate_secret(txn, hcaptcha_cookie_secret, false, nil)
    if parsed_request_cookies["z_ddos_captcha"] == expected_cookie then
        --core.Debug("CAPTCHA STATUS CHECK SUCCESS")
        return txn:set_var("txn.captcha_passed", true)
    end
end

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
