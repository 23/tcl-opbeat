# opbeat.tcl
# 
###Abstract
# Interface for Opbeat error logging and distribution tracking.
#
###Change history:
# 0.1.0 - First release

package require Tcl 8.5
package require http
package require tls
package require huddle
::http::register https 443 ::tls::socket

package provide opbeat 0.1.0

namespace eval opbeat { 
    variable queue ; # A queue for async logging
    set queue [list]

    variable config ; # A dict for current config info.
    variable config_orig ; # Holds "reset" version.

    set config_orig [dict create \
                         inited "0" \
                         organization_id "" \
                         app_id "" \
                         secret_token "" \
                         env "production" \
                         hostname [info hostname] \
                         logger "tcl opbeat" \
                         sync 1 \
                         user_agent "tcl-opbeat/0.1"
                        ]
    set config $config_orig
}

proc opbeat::debug {args} {
    puts $args
}
proc opbeat::config {args} {
    variable config
    variable config_orig
    switch -exact [llength $args] {
        0 {
            return $config
        }
        1 {
            set arg [regsub -inline {^-} [lindex $args 0] ""]
            if { [dict exists $config $arg] } {
                return [dict get $config $arg]
            } else {
                error "Bad option \"-${arg}\": must be [join [dict keys $config] ,\  ]" "" [list opbeat usage [lindex $args 0] "Bad option to config"]
            }
        }
        default {
            if {[llength $args] % 2 != 0} {
                error "Bad argument, config arguments by med '-name val ...'" "" [list opbeat usage [lindex $args end] "Odd number of config args"]
            }
            foreach {k v} $args {
                regsub {^-} $k "" k
                dict set config $k $v
            }
        }
    }
    return $config
}

proc opbeat::init {organization_id app_id secret_token {env "production"}} {
    opbeat::config \
        -inited 1 \
        -organization_id $organization_id \
        -app_id $app_id \
        -secret_token $secret_token \
        -env $env
}

proc opbeat::send {
    method
    payload
    {force_sync "0"}
} {
    variable config
    array set c $config
    if { !$c(inited) } {
        error "Opbeat package must be inited with opbeat::init" "" [list opbeat usage [lindex $args 0] "Opbeat not inited"]
    }

    if { !$c(sync) && !$force_sync } {
        variable queue
        lappend queue $method $payload
    } else {
        # Set URL, User-Agent and json body to post to
        switch -exact $method {
            error {
                set url "https://opbeat.com/api/v1/organizations/${c(organization_id)}/apps/${c(app_id)}/errors/"
            }
            default {
                error "Method '$method' is not supported by Opbeat implementation" "" [list opbeat usage [lindex $args 0] "Opbeat not inited"]
            }
        }
        http::config -useragent $c(user_agent)
        set json_body [huddle jsondump $payload]
        opbeat::debug $json_body
        if { [lsearch -exact {test testing dev development} $c(env)]>=0 } {
            opbeat::debug "Not sending, development more"
        } else {
            # Make the actual request
            set token [http::geturl \
                           $url \
                           -query $json_body \
                           -type "application/json" \
                           -headers [list "Authorization" "Bearer ${c(secret_token)}"] \
                          ]
            # Print out response, code + actual message
            set http_ncode [http::ncode $token]
            set http_data [http::data $token]
            http::cleanup $token
            if { $http_ncode ne "202" } {
                opbeat::debug "Error logging to Opbeat: $http_ncode / $http_data"
            }
        }
    }
}

proc opbeat::handle_async_queue {} {
    variable queue
    set local_queue $queue
    set queue ""
    foreach {method payload} $local_queue {
        opbeat::send $method $payload 1
    }
}

proc opbeat::log_error {args} {
    variable config
    array set c $config
    if { !$c(inited) } {
        error "Opbeat package must be inited with opbeat::init" "" [list opbeat usage [lindex $args 0] "Opbeat not inited"]
    }
    
    array set options  {
        error_info ""
        error_code ""
        level "error"
        http_url ""
        http_method ""
        http_query_string ""
        http_env ""
        http_cookies ""
        http_headers ""
        http_remote_host ""
        http_host ""
        http_user_agent ""
        http_secure "0"
        http_data ""
        user_info ""
        query_info ""
    }

    set message [lindex $args 0]
    if { [llength $args]==2 } {
        set args [lindex $args 1]
    } else {
        set args [lrange $args 1 end]
    }
    puts [llength $args]
    puts [expr [llength $args] % 2]
    if { [expr [llength $args] % 2]!=0 } {
        error "Bad argument, syntax is 'opbeat::log_error message -option value -option value ...'" "" [list opbeat usage [lindex $args end] "Invalid argument to log_error"]
    }
    foreach {o v} $args {
        set "options([string range $o 1 end])" $v
    }

    if { $options(error_info) eq "" } {set options(error_info) $message}
    set extra [huddle compile dict [list error_code $options(error_code)]]
    set client_supplied_id "tcl-${c(app_id)}-[clock seconds]-[expr int(rand()*99999.0)]"
    set payload [huddle create \
                     message [huddle compile string $message] \
                     timestamp [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S.000Z" -gmt 1] \
                     level $options(level) \
                     logger $c(logger) \
                     server_name $c(hostname) \
                     client_supplied_id $client_supplied_id \
                     stacktrace [huddle compile dict [list trace [string map [list "\{" "(" "\}" ")"] $options(error_info)]]] \
                    ]

    # HTTP info, url and method are required
    if { $options(http_url) ne "" && $options(http_method) ne "" } {
        set http [huddle create]
        foreach {type k v} {
            string url http_url
            string method http_method
            string query_string http_query_string
            string cookies http_cookies
            string remote_host http_remote_host
            string http_host http_host
            string user_agent http_user_agent
            string secure http_secure
            dict data http_data
            dict env http_env
            dict headers http_headers
        } {
            if { [set options($v)] ne "" } {
                huddle set http $k [huddle compile $type [set options($v)]]
            }
        }
        huddle append payload http $http
    }

    # User info, is_authenticated and id are required
    if { $options(user_info) ne ""  } {
        huddle append payload user [huddle compile dict $options(user_info)]
    }

    # Query info
    if { $options(query_info) ne ""  } {
        huddle append payload query [huddle compile dict $options(query_info)]
    }
    opbeat::send "error" $payload

    return $client_supplied_id
}        

proc opbeat::with_logging {code {bubble_error "1"}} {
    if { [catch {
        uplevel 1 $code
    } err] } {
        set i ${::errorInfo}
        set c ${::errorCode}
        opbeat::log_error $err -error_info $i -error_code $c
        if { $bubble_error } {
            error $err $i $c
        }
    }
}
