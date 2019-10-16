# Web Servers

## Compatibility

| Type      | Documentation                     | Version      | Support type |
| --------- | --------------------------------- | ------------ | ------------ |
| Puma      | http://puma.io/                   | 2.16+ / 3.6+ | Full         |
| Unicorn   | https://bogomips.org/unicorn/     | 4.8+ / 5.1+  | Full         |
| Passenger | https://www.phusionpassenger.com/ | 5.0+         | Full         |

## HTTP request queuing

Traces that originate from HTTP requests can be configured to include the time spent in a frontend web server or load balancer queue before the request reaches the Ruby application.

This functionality is **experimental** and deactivated by default.

To activate this feature, you must add an `X-Request-Start` or `X-Queue-Start` header from your web server (i.e., Nginx). The following is an Nginx configuration example:

```
# /etc/nginx/conf.d/ruby_service.conf
server {
    listen 8080;

    location / {
      proxy_set_header X-Request-Start "t=${msec}";
      proxy_pass http://web:3000;
    }
}
```

Then you must enable the request queuing feature in the integration handling the request.

For Rack-based applications, see the [documentation](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#rack) for details for enabling this feature.
