vcl 4.1;
import std;

# backend pointing to HAProxy
backend haproxy {
	.path = "/shared-sockets/varnish-to-haproxy-internal.sock";
}

acl purge_allowed {
	"127.0.0.1";
	"::1";
	"172.19.0.1";
}

# incoming requests
sub vcl_recv {

	# handle PURGE and BAN requests
	if ((req.method == "PURGE" || req.method == "BAN") && req.http.X-BasedFlare-Varnish-Key == "changeme") {
		if (req.http.X-Forwarded-For) {
			set req.http.X-Real-IP = regsub(req.http.X-Forwarded-For, ",.*", "");
		} else {
			# set fallback to client IP
			set req.http.X-Real-IP = client.ip;
		}
		if (std.ip(req.http.X-Real-IP, "0.0.0.0") ~ purge_allowed) {
			#perform action based on the requestm ethod
			if (req.method == "PURGE") {
				return (purge);
			} else if (req.method == "BAN") {
				return (ban);
			}
		} else {
			return (synth(405, "Not allowed"));
		}
	}

	# route all requests to haproxy
	set req.backend_hint = haproxy;

	# some conditions are not cached
	if (req.method != "GET" && req.method != "HEAD") {
		# pass through for non-GET requests
		return (pass);
	}

	# honor cache control headers for "no-cache" or "no-store"
	if (req.http.Cache-Control ~ "no-cache" || req.http.Cache-Control ~ "no-store") {
		return (pass);
	}

	# save the Cookie header temporarily if needed by the backend
	if (req.http.Cookie) {
		set req.http.X-Cookie-Temp = req.http.Cookie;
		unset req.http.Cookie;  # remove Cookie header for caching purposes
	}
}

# caching behavior when fetching from backend
sub vcl_backend_response {
	if (beresp.http.Set-Cookie) {
		set beresp.uncacheable = true;
		return (pass);
	}
	# only cache specific types of content and successful responses
	if ((beresp.status == 200 || beresp.status == 206) && beresp.http.Content-Type ~ "text|application|image|video|audio|font") {
		if (beresp.http.Cache-Control ~ "no-cache" || beresp.http.Cache-Control ~ "no-store" || beresp.http.Pragma == "no-cache") {
			#don't cache if the backend says no-cache
			set beresp.uncacheable = true;
			return (pass);
		} else if (beresp.http.Cache-Control ~ "max-age") {
			# use max-age if provided
			set beresp.ttl = std.duration(regsub(beresp.http.Cache-Control, ".*max-age=([0-9]+).*", "\1") + "s", 0s);
		} else if (beresp.http.Expires) {
			# calculate ttl using Expires if present
			set beresp.ttl = std.duration(beresp.http.Expires, 0s);
		} else {
			# default ttl if no cache header
			set beresp.ttl = 1m;
		}

		# grace period for stale content
		set beresp.grace = 10m;
		set beresp.uncacheable = false;
		set beresp.do_stream = true;
		set beresp.do_gunzip = true;
	} else {
		# non-cacheable or non-success responses
		set beresp.uncacheable = true;
		return (pass);
	}

	# remove Set-Cookie for cacheable responses
	if (!beresp.uncacheable) {
		unset beresp.http.Set-Cookie;
	}
}

# when sending response
sub vcl_deliver {
	unset resp.http.X-Varnish;
	unset resp.http.Via;
	unset req.http.X-Cookie-Temp; # ensure X-Cookie-Temp is gone

	# custom header to indicate cache hit or miss
	if (obj.hits > 0) {
		set resp.http.X-Cache = "HIT";
	} else {
		set resp.http.X-Cache = "MISS";
	}
}

# restore Cookie header to backend if saved
sub vcl_backend_fetch {
	if (bereq.http.X-Cookie-Temp) {
		set bereq.http.Cookie = bereq.http.X-Cookie-Temp;
		unset bereq.http.X-Cookie-Temp; # remove X-Cookie-Temp after use
	}
}
