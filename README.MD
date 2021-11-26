## HaProxy DDoS protection system PoC

A fork and further development of a proof of concept from https://github.com/mora9715/haproxy_ddos_protector, a haproxy configuration and lua scripts allowing a holding page where users solve a captcha (think cloudflare CDN).
Intended to stop bots, spam, probably some forms of ddos, etc.

Some issues fixed and various improvements:

- Add a proof-of-work element to the bot-check page as an optional weaker but more user-friendly mode
- Add more options to CLI for nocaptcha
- Add examples and support for .onion/tor using the haproxy PROXY protocol to provide some kind of "ip" discrimination of tor users (circuit identifiers)
- Add serving javascript files directly from haproxy with http-request return, so no extra backend is needed
- Improved the appearance of the challenge page
- Fix a lot of bugs
- Fix resolving domain of hcaptcha, no longer uses a hack
- Fix multiple security issues that could result in bypassing the captcha
- Fix challenge cookies lasting forever, they are now limited by a bucket duration on server side

#### Screenshot

![captcha](img/captcha.png "captcha mode (pow done asynchronously in background)")
![nocaptcha](img/nocaptcha.png "no captcha mode")

#### How to test

Add some env vars to docker-compose file:

- HCAPTCHA_SITEKEY - your hcaptcha site key
- HCAPTCHA_SECRET - your hcaptcha secret key
- CAPTCHA_COOKIE_SECRET - random string, a salt for captcha cookies
- POW_COOKIE_SECRET - different random string, a salt for pow cookies
- RAY_ID - string to identify the haproxy node by

Run docker compose:
```bash
docker compose up
```

- visit *http://127.0.0.1*

DDoS-protection mode is enabled by default.

#### Installation

Before installing the tool, ensure that HaProxy is built with Lua support (in package and ubuntu recommended PPA, it is.)

- Copy haproxy config and make sure that `lua-load` directive contains absolute path to [register.lua](src/scripts/register.lua)
- Copy or link [scripts](src/scripts) to /etc/haproxy/scripts
- Copy or link [libs](src/libs) to /etc/haproxy/libs (or a path where Lua looks for modules).
- Create `/etc/haproxy/ddos.map` for domains with protection mode enabled
- Create `/etc/haproxy/no_captcha.map` for domains with no captcha, only pow

If you want to try with tor and haproxy PROXY mode:
- Uncomment the tor service in `docker-compose.yml`
- Change the haproxy mount in `docker-compose.yml` for haproxy.cfg to haproxy.tor.cfg
- Add your hidden service folder (with keys, etc) to `tor/hidden_service`
- Run `docker-compose build` to rebuild the tor container with it.

#### CLI
The system comes with CLI. It can be used to manage protection global/per-domain and control nocaptcha mode.
Ensure that stat socket is configured in HaProxy for CLI support.

```bash
Usage: ddos-cli <command> [options]

Command line interface to manage per-domain and global DDoS protection.

optional arguments:
  -h, --help                 Show this help message and exit.

Commands:
  Global management:
  src/cli/ddos-cli global status           Show status of global server ddos mode.
  src/cli/ddos-cli global enable           Enable global ddos mode.
  src/cli/ddos-cli global disable          Disable global ddos mode.

  Domain management:
  src/cli/ddos-cli domain list             List all domains with ddos mode on.
  src/cli/ddos-cli domain nocaptcha             List all domains with nocaptcha mode on.
  src/cli/ddos-cli domain status <domain>  Get ddos mode status for a domain.
  src/cli/ddos-cli domain enable <domain>  Enable ddos mode for a domain.
  src/cli/ddos-cli domain disable <domain> Disable ddos mode for a domain.
  src/cli/ddos-cli domain mode <domain> Toggle nocaptcha mode for a domain.

 ```
