## HaProxy DDoS protection system PoC

A fork of https://github.com/mora9715/haproxy_ddos_protector, a haproxy lua script allowing a holding page where users solve a captcha and proof-of-work (cpu intensive) task.
Intended to stop bots, spam, probably some forms of ddos, etc.

Some issues fixed and various improvements:

- Fix some bugs
- Fix a security issue where unsalted hash could let users bypass captcha
- Made the cookies not work permanently. They now expire based on a server-side bucket as part of the cookie hash, instead of client side expiry
- Added additional proof-of-work element to the challenge page, both pow+captcha must be completed
- Avoid using a hack to resolve domain names, usea backend in haproxy instead
- Improved the appearance of the challenge page
- More options to CLI for nocaptcha

#### How to test

Add some env vars to docker-compose file:

- HCAPTCHA_SITEKEY - your hcaptcha site key
- HCAPTCHA_SECRET - your hcaptcha secret key
- CAPTCHA_COOKIE_SECRET - random string, a salt for cookies
- POW_COOKIE_SECRET - random string a salt for cookies
- RAY_ID - string to identify the haproxy node by


Run docker compose:
```bash
docker compose up
```

- visit *http://127.0.0.1*

DDoS-protection mode is enabled by default.

#### Installation
Before installing the tool, ensure that HaProxy is built with Lua support.

- Copy [scripts](src/scripts) to a folder accessible for HaProxy
- Copy haproxy config and make sure that `lua-load` directive contains absolute path to [register.lua](src/scripts/register.lua)
- Copy [libs](src/libs) to a path where Lua looks for modules.
- Copy [ddos-cli](src/cli/ddos-cli) to any convenient path.
- Create `/etc/haproxy/domains_under_ddos.txt` with write permissions for HaProxy (feel free to change the map file path, update the HaProxy config correspondingly)
- If you want to try with tor, change the haproxy mount in docker-compose to the haproxy/haproxy.tor.cfg and include your hidden_service folder (with keys, etc) in the tor folder

#### CLI
The system comes with CLI. It can be used to manage global and per-domain protection.
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
