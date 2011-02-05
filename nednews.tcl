package require http
package require tdom

set url "http://semipublic.comp-arch.net/wiki/index.php?title=Special:RecentChanges&feed=atom"

set httpData ""
proc httpDone {token} {

	set fail 0
	switch [::http::status $token] {
		ok {
			if {[::http::ncode $token] != 200} {
				puts "HTTP server returned non-OK code [::http::ncode $token]"
				set fail 1
			}
		}

		eof {
			puts "HTTP server returned nothing"
			set fail 1
		}

		error {
			puts "HTTP error [::http::error $token]"
			set fail 1
		}
	}

	if {!$fail} {
		set ::httpData [::http::data $token]
	}

	::http::cleanup $token
	puts "HTTP Done"
}

set httpToken [::http::geturl $url -timeout 5000 -command httpDone]

### gui
wm withdraw .
toplevel .tMain

## a splitter for left and right windows
pack [ttk::panedwindow .tMain.splitLR -orient horizontal] -expand 1 -fill both
# a tree for news sources
.tMain.splitLR add [ttk::treeview .tMain.splitLR.tSrcs]

## a splitter for top and bottom (headers and bodies)
.tMain.splitLR add [ttk::panedwindow .tMain.splitLR.splitRTB -orient vertical]

# a tree for headers (threaded view)
.tMain.splitLR.splitRTB add [ttk::treeview .tMain.splitLR.splitRTB.tHdr]

# textbox for bodies
.tMain.splitLR.splitRTB add [text .tMain.splitLR.splitRTB.xBdy -state disabled]

