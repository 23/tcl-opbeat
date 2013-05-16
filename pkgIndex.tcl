# pkgIndex.tcl --

if {![package vsatisfies [package provide Tcl] 8.5]} {return}

package ifneeded opbeat 0.1.0 [list source [file join ./ opbeat.tcl]]

