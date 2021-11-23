_M = {}

local url = require("url")
local http = require("http")
local utils = require("utils")
local cookie = require("cookie")
local json = require("json")

local captcha_secret = os.getenv("HCAPTCHA_SECRET")
local captcha_sitekey = os.getenv("HCAPTCHA_SITEKEY")
local cookie_secret = os.getenv("COOKIE_SECRET")

local captcha_provider_domain = "hcaptcha.com"

local body_template = [[
<!DOCTYPE html>
<html>
	<head>
		<meta name='viewport' content='width=device-width initial-scale=1'>
		<title>Solve this captcha...</title>
		<style>
			:root{--text-color:#c5c8c6;--bg-color:#1d1f21}
		    @media (prefers-color-scheme:light){:root{--text-color:#333;--bg-color:#EEE}}
			a,a:visited{color:var(--text-color)}
			body,html{height:100vh}
			body{display:flex;flex-direction:column;background-color:var(--bg-color);color:var(--text-color);font-family:Helvetica,Arial,sans-serif;text-align:center;margin:0}
			h3,p{margin:0}
			footer{font-size:small;margin-top:auto;margin-bottom:50px}h3{padding-top:30vh}
		</style>
	</head>
	<body>
		<h3>Captcha completion required</h3>
		<p>We have detected unusual activity on the requested resource.</p>
		<p>Please solve this captcha to prove you are not a robot.</p>
		<div>
			<br>
		</div>
		<noscript>
			<p class="red">JavaScript is required to complete the captcha.</p>
		</noscript>
		<form method="POST">
			<div class="h-captcha" data-sitekey="%s"></div>
			<script src="https://hcaptcha.com/1/api.js" async defer></script>
			<input type="submit" value="Submit">
		</form>
		<footer>Supported by <a href="https://kikeflare.com">KikeFlare</a></footer>
	</body>
</html>
]]

function _M.view(applet)
    local response_body
    local response_status_code
    if applet.method == "GET" then
        response_body = string.format(body_template, captcha_sitekey)
        response_status_code = 403
	    applet:set_status(response_status_code)
	    applet:add_header("content-type", "text/html")
	    applet:add_header("content-length", string.len(response_body))
	    applet:start_response()
	    applet:send(response_body)
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
                local floating_hash = utils.generate_secret(applet, cookie_secret, true)
                applet:add_header(
                    "set-cookie",
                    string.format("z_ddos_captcha=%s; Max-Age=14400; Path=/", floating_hash)
                )
--            else
--                core.Debug("HCAPTCHA FAILED: " .. json.encode(api_response))
            end
        end
        response_body = ""
        response_status_code = 302
        applet:add_header("location", applet.qs)
	    applet:set_status(response_status_code)
	    applet:add_header("content-type", "text/html")
	    applet:add_header("content-length", string.len(response_body))
	    applet:start_response()
	    applet:send(response_body)
    end
end

function _M.check_captcha_status(txn)
    local parsed_request_cookies = cookie.get_cookie_table(txn.sf:hdr("Cookie"))
    local expected_cookie = utils.generate_secret(txn, cookie_secret)
    --core.Debug("RECEIVED SECRET COOKIE: " .. parsed_request_cookies["z_ddos_captcha"])
    --core.Debug("EXPECTED SECRET COOKIE: " .. expected_cookie)
    if parsed_request_cookies["z_ddos_captcha"] == expected_cookie then
        core.Debug("CAPTCHA STATUS CHECK SUCCESS")
        return txn:set_var("txn.captcha_passed", true)
    end
end

return _M
