vcl 4.1;
import std;

# backend pointing to HAProxy
backend default {
	.path = "/shared-sockets/varnish-to-haproxy-internal.sock";
}
backend haproxy {
	.path = "/shared-sockets/varnish-to-haproxy-internal.sock";
}

acl purge_allowed {
	"127.0.0.1";
	"::1";
	"103.230.159.7";
	"2404:9400:2:0:216:3eff:fee3:5c06";
}

sub vcl_pipe {
	return (pipe);
}

# incoming requests
sub vcl_recv {

	# route all requests to haproxy
	set req.backend_hint = haproxy;

	# unfuck x-forwarded-for
	set req.http.X-Forwarded-For = regsub(req.http.X-Forwarded-For, "^([^,]+),?.*$", "\1");

	# handle PURGE and BAN
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
				ban("obj.http.x-url ~ " + req.url + " && obj.http.x-host == " + req.http.host);
				return (synth(200, "Ban added"));
			}
		} else {
			return (synth(405, "Not allowed"));
		}
	}

	if (req.http.Range) {
		return (pass);
	}

	# some conditions are not cached
	if (req.method != "GET" && req.method != "HEAD") {
		# pass through for non-GET requests
		return (pass);
	}

	# honor cache control headers for "no-cache" or "no-store"
	if (req.http.Cache-Control ~ "no-cache" || req.http.Cache-Control ~ "no-store") {
		return (pass);
	}

}

sub vcl_hash {
	hash_data(req.url);
	if (req.http.Host) {
		hash_data(req.http.Host);
	}
	if (req.http.Range) {
		hash_data(req.http.Range);
	}
}

## caching behavior when fetching from backend
sub vcl_backend_response {

	set beresp.do_stream = true;  # Stream directly
	set beresp.transit_buffer = 1M; # testing

	# dont cache > 100MB
	if (beresp.http.Content-Length && std.integer(beresp.http.Content-Length, 0) > 100 * 1024 * 1024) {
		set beresp.uncacheable = true;  # Don't cache
		return (deliver);
	}

	# dont cache set-cookie responses
	if (beresp.http.Set-Cookie) {
		set beresp.uncacheable = true;
		return (pass);
	}

	# dont cache ranges
	# if (bereq.http.Range) {
	# 	set beresp.ttl = 0s;
	# 	set beresp.uncacheable = true;
	# }

	# only cache specific types of content and successful responses
	if ((beresp.status == 200 || beresp.status == 206) && (!beresp.http.Content-Type || beresp.http.Content-Type ~ "text|application|image|video|audio|font")) {
		if (beresp.http.Cache-Control ~ "no-cache" || beresp.http.Cache-Control ~ "no-store" || beresp.http.Pragma == "no-cache") {
			#don't cache if the backend says no-cache
			set beresp.uncacheable = true;
			return (pass);
		} else if (beresp.http.Cache-Control ~ "max-age") {
			# use max-age if provided
			set beresp.ttl = std.duration(regsub(beresp.http.Cache-Control, ".*max-age=([0-9]+).*", "\1") + "s", 0s);
		} else if (beresp.http.Expires) {
			# calculate ttl using Expires if present
			set beresp.ttl = std.duration(beresp.http.Expires + "s", 0s);
		} else {
			# default ttl if no cache header
			set beresp.ttl = 1m;
		}
		# grace period for stale content
		set beresp.grace = 10m;
		set beresp.uncacheable = false;
	} else {
		# non-cacheable or non-success responses
		set beresp.uncacheable = true;
		return (pass);
	}

}

# when sending response
sub vcl_deliver {

	# add accept-ranges for backend reqs
	if (req.http.Range) {
		set resp.http.Accept-Ranges = "bytes";
	}

	# custom header to indicate cache hit or miss
	if (obj.hits > 0) {
		set resp.http.X-Cache = "HIT";
	} else {
		set resp.http.X-Cache = "MISS";
	}

}
