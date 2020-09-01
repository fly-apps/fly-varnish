FROM varnish:6.4
COPY default.vcl /etc/varnish/
CMD ["/usr/sbin/varnishd", "-F", "-f", "/etc/varnish/default.vcl", "-T", "none"]
