# How to Run Varnish Cache on Fly

[Varnish Cache](https://varnish-cache.org/intro/index.html#intro) is a popular open-source web application accelerator. When placed in front of a web page, Varnish will request the page from once to cache the page - making a copy of its resources (including images, styles, and scripts) in memory. Varnish then handles all future requests for the same page by serving the cached copy.

Varnish acts like a reverse proxy that sits between your end-users and your web server. It can be configured to filter requests based on rules written in [Varnish Configuration Language](https://varnish-cache.org/docs/trunk/users-guide/vcl.html).

![Without Varnish](https://gist.github.com/gaurav-nelson/6b77f89f439e99014c798c65d03e68ac/raw/85283c9141006765040148b58a597041547c71e0/without-varnish.png "Without Varnish")

You can configure Varnish to store your pages' content and serve the cached pages whenever it receives new requests. Thus, Varnish speeds up your web application and reduces the load on the webserver. According to their site: “Varnish typically speeds up delivery with a factor of 300 - 1000x, depending on your architecture.”

![With Varnish](https://gist.githubusercontent.com/gaurav-nelson/6b77f89f439e99014c798c65d03e68ac/raw/85283c9141006765040148b58a597041547c71e0/with-varnish.png "With Varnish")

[Fly.io](https://fly.io/) runs your application in Docker containers across its edge network. This can make your application run 80% faster and increase reliability. By running Varnish on Fly, you can give your application an acceleration boost to make pages load even more quickly.

## How to Configure Varnish to Run on Fly
In this tutorial, you’ll see how to configure and run Varnish on Fly. You’ll create a new Fly application, customize your Varnish `.vcl` file, create a Dockerfile, and check that responses are successfully cached as you would expect.

### Prerequisites

- The [Flyctl command line tool](https://fly.io/docs/flyctl/installing/).

### Creating a New Fly Application

First, you'll need to use `flyctl` to create a new application. If you haven't already, install the appropriate version of `flyctl` for your operating system using the instructions at [Installing flyctl](https://fly.io/docs/hands-on/installing/).

After that, [sign up](https://fly.io/docs/hands-on/sign-up/) or [sign in](https://fly.io/docs/hands-on/sign-in/) to your Fly account from your console:

```bash
# Sign up 
flyctl auth signup

# Or sign in 
flyctl auth login
```

Running those commands opens a web page that allows you to log in by using your GitHub account or your email and password.

Create a new directory for the project and then use `flyctl init` to create a new application and generate the Fly configuration file.

```bash
mkdir varnish-on-fly && cd varnish-on-fly
flyctl init
```

- For `App Name` and `Select Organization` prompts, press **Enter** to use an auto-generated name and your default organization.
- For the `Select builder` prompt, press **Enter** to select the `(Do not set a builder)` option.
- For the `Select Internal Port` prompt, enter `80` as the port number and press **Enter**.

Every Fly application makes use of the `fly.toml` file to manage deployments. After completing the steps above, you'll see the message `Wrote config file fly.toml`.

### Deploying Varnish
To deploy Varnish to Fly, you can start from the official Docker image [available on Docker Hub](https://hub.docker.com/_/varnish).

Varnish uses a domain-specific language called [Varnish Configuration Language (VCL)](https://varnish-cache.org/docs/6.4/reference/vcl.html). You can configure Varnish by specifying the configuration in a `default.vcl` file. Varnish then uses the specified configuration for request handling and document caching policies for Varnish Cache.

Create a new file called `default.vcl` with the following content:

```
vcl 4.0;
backend default { 
    .host = "flygreeting.fly.dev";
    .port = "80";
}
```

The value of `.host` is a fully qualified hostname or IP address (typically a web server). This example uses the [Flygreeting](https://github.com/fly-examples/flygreeting) example app. The value of `.port` is the listening port of the Varnish backend, that is, the server providing the content that Varnish accelerates.

Next, create a new file called `Dockerfile` and add the following:

```Dockerfile
FROM varnish:6.4
COPY default.vcl /etc/varnish/
CMD ["/usr/sbin/varnishd", "-F", "-f", "/etc/varnish/default.vcl", "-T", "none"]
```

The Dockerfile uses the official Varnish Docker image with the configuration specified in the `default.vcl` file. By default, Varnish sets a management interface on your application, but because you shouldn't publicly expose this interface, you should update the `CMD` statement to specify the `-T none` flag. This disables the management interface. Read more about the [`varnishd` command-line parameters here](https://varnish-cache.org/docs/trunk/reference/varnishd.html) if you want to customize your run command further.

Now that your Dockerfile is set up, you're ready to deploy Varnish. Run `flyctl deploy` to deploy your application to Fly.io.

To check that Varnish is working, run the following command to get the response headers from your application:

```bash
curl -Is <your-app-address>/v1/countries/
HTTP/2 200
content-type: application/json; charset=utf-8
date: Sun, 30 Aug 2020 10:24:56 GMT
content-length: 1260
server: Fly/f8f635b (2020-08-24)
via: 1.1 fly.io, 2 fly.io
x-varnish: 32793 22
age: 53
accept-ranges: bytes
```

The presence of an `x-varnish` response header confirms that Varnish is intercepting web requests at this address.

### Verifying That Caching Works

To check that Varnish is properly caching the Flygreeting web application, you can configure Varnish to update the response headers if the request hits or misses the cache. To do this, replace the `default.vcl` file with the following:

```
vcl 4.0;

backend default {
  .host = "flygreeting.fly.dev";
  .port = "80";
}

sub vcl_recv {
    unset req.http.x-cache;
}

sub vcl_hit {
    set req.http.x-cache = "hit";
}

sub vcl_miss {
    set req.http.x-cache = "miss";
}

sub vcl_pass {
    set req.http.x-cache = "pass";
}

sub vcl_pipe {
    set req.http.x-cache = "pipe uncacheable";
}

sub vcl_synth {
    set req.http.x-cache = "synth synth";
    set resp.http.x-cache = req.http.x-cache;
}

sub vcl_deliver {
    if (obj.uncacheable) {
        set req.http.x-cache = req.http.x-cache + " uncacheable" ;
    } else {
        set req.http.x-cache = req.http.x-cache + " cached" ;
    }
    set resp.http.x-cache = req.http.x-cache;
}
```

This configuration adds an additional `x-cache` response header that returns `hit` when the response is delivered from the cache or `miss` when the response comes from the backend.

Deploy the updated version on Fly by running `flyctl deploy` again. Send a request to your web application using `curl` to inspect its headers:

```bash
curl -Is <your-app-address>/v1/countries/ | grep 'x-cache'
x-cache: miss cached
```

The `miss cached` value denotes that the response is being delivered from the Flygreeting backend. Now send the same request again:

```bash
curl -Is <your-app-address>/v1/countries/ | grep 'x-cache'
x-cache: hit cached
```

The `hit cached` value denotes that the response was delivered from Varnish's cache. Your Varnish installation is now successfully deployed to Fly's global edge hosting network and is ready to improve your website's speed from anywhere in the world.

## Conclusion
In this tutorial, you've seen how to deploy Varnish on Fly to take advantage of the application acceleration features that Varnish offers. You also learned how to configure Varnish to include caching status in a response header and how to verify that responses are being cached.

Varnish is a great way to improve the speed of your static web pages and assets, and deploying it to Fly is a great way to minimize the latency of your cache by distributing it globally. You can customize the way Varnish handles requests and caching using the [Varnish Configuration Language](https://varnish-cache.org/docs/trunk/users-guide/vcl.html), and for more information about setting up Varnish, see the [Reference Manual](https://varnish-cache.org/docs/6.4/reference/index.html).

If you have questions about using Varnish with [Fly.io](https://fly.io/), reach out to [support@fly.io](support@fly.io), and we'll help you get started.
