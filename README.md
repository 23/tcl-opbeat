### Installing

Installing is fair easy (with some sudo magic at least):

    git clone git@github.com:23/tcl-opbeat.git && sudo mv tcl-opbeat /usr/lib/tcltk/

### Starting up

To start using Tcl opbeat package, initialize it with your Opbeat credentials:

    package require opbeat
    opbeat::init <org_id> <app_id> <secret_token> [<environment>]

After this, you can tweak the configuration as needed:

    opbeat::config -option1 value1 -option2 value2 [...]

Valid options are:

* `-organization_id`: ID of your Opbeat organization.
* `-app_id`: ID of your Opbeat application.
* `-secret_token`: Token or the Opbeat app.
* `-env`: Environment, set to `test` or `dev` in order to skip actual logging to Opbeat.
* `-hostname`: Hostname of the logger, defaults to `info hostname`.
* `-logger`: A string identifying the logger.
* `-user_agent`: User agent to to report with (why would you need this?)
* `-sync`: Do not log to Opbeat immediately. If you set this option to `1`, you are reponsible for triggering logs later on by calling `opbeat::handle_async_queue`.

### Logging errors, the easy way

Wrapping any block of code with `opbeat::with_logging { ... }` will catch errors throw them to Opbeat:

    package require opbeat
    opbeat::init <org_id> <app_id> <secret_token> [<environment>]
    opbeat::with_logging {
        this_wont_work
    }

By default, that would also trigger an `error`, but you can choose not to have errors bubble:

    opbeat::with_logging {
        this_wont_work_but_we_dont_care
    } 0

### Logging errors, the hard way

Logging an error can be as simple as

    opbeat::log_error "error message"

You will want to send extra information along though:

    opbeat::log_error \
        "stuff" \
        -http_method GET \
        -http_url http://example.com \
        -http_data [dict create a 1 b 2] \
        -user_info [list id 1234 is_authenticated 1] \
        -query_info [list engine stuff query "SELECT ..."]


Valid options are:

* `-error_info`: Tcl error info.
* `-error_code`: Tcl error code.
* `-level`: Opbeat error level.
* `-http_url`: URL of HTTP request (required for any HTTP logging).
* `-http_method`: HTTP method (required for any HTTP logging).
* `-http_query_string`: Query string.
* `-http_env`: Key-value list of any environment variables you want to send.
* `-http_cookies`: Query-string encoded cookie string.
* `-http_headers`: Key-value list of HTTP headers.
* `-http_remote_host`: Remote host.
* `-http_host`: HTTP host.
* `-http_user_agent`: Client users agent.
* `-http_secure`: Secure request or not.
* `-http_data`: Key-value list of request POST data.
* `-user_info`: Key-value list of user data, keys `id` and `is_authenticated` are expected by Opbeat, but other data is arbitrary.
* `-query_info`: Key-value list of database query data, keys `engine` and `query` are expected by Opbeat.
