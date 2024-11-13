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

	# handle PURGE requests
	if (req.method == "PURGE" && req.http.X-BasedFlare-Varnish-Key == "changeme") {
		if (req.http.X-Forwarded-For) {
			set req.http.X-Real-IP = regsub(req.http.X-Forwarded-For, ",.*", "");
		} else {
			# fallback to client ip
			set req.http.X-Real-IP = client.ip;
		}
		if (std.ip(req.http.X-Real-IP, "0.0.0.0") ~ purge_allowed) {
			return (purge);
		} else {
			return (synth(405, "Not allowed"));
		}
	}

	# route all requests to haproxy
	set req.backend_hint = haproxy;

	# some conditions are not cached
	if (req.method != "GET" && req.method != "HEAD") {
		# Pass through for non-GET requests (e.g., POST, PUT)
		return (pass);
	}

	# honor cache control headers for "no-cache" or "no-store" (might remove later or disable under ACL)
	if (req.http.Cache-Control ~ "no-cache" || req.http.Cache-Control ~ "no-store") {
		return (pass);
	}
}

# caching behavior when fetching from backend
sub vcl_backend_response {
	# Only cache specific types of content and successful responses
	if ((beresp.status == 200 || beresp.status == 206) && beresp.http.Content-Type ~ "text|application|image|video|audio|font") {
		# try to handle backend cache headers better
		if (beresp.http.Cache-Control ~ "no-cache" || beresp.http.Cache-Control ~ "no-store" || beresp.http.Pragma == "no-cache") {
			# dont cache if the backend specifies not to cache
			set beresp.uncacheable = true;
			return (pass);
		} else if (beresp.http.Cache-Control ~ "max-age") {
			# if max-age is provided, use it directly
			set beresp.ttl = std.duration(regsub(beresp.http.Cache-Control, ".*max-age=([0-9]+).*", "\1"), 0s);
		} else if (beresp.http.Expires) {
			# if using expire, calculate remaining TTL
			set beresp.ttl = std.duration(beresp.http.Expires, 0s);
		} else {
			#default TTL if no caching header
			set beresp.ttl = 1m;
		}

		# grace period for serving stale content
		set beresp.grace = 10m;
		set beresp.uncacheable = false;
		set beresp.do_stream = true;
		set beresp.do_gunzip = true;
	} else {
		# Non-cacheable or non-success responses
		set beresp.uncacheable = true;
		return (pass);
	}

	# should be caught by haproxy acl alreayd, but just in case
	unset beresp.http.Set-Cookie;
}

# caching behavior when sending response
sub vcl_deliver {
	# custom header to tell whether req was served from cache
	if (obj.hits > 0) {
		set resp.http.X-Cache = "HIT";
	} else {
		set resp.http.X-Cache = "MISS";
	}
}
