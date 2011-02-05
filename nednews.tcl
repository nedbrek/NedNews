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
		set httpData [::http::data $token]
		set ::httpData $httpData
		set doc [dom parse $httpData]
		$doc selectNodesNamespaces {atom http://www.w3.org/2005/Atom}

		set entries [$doc selectNodes /atom:feed/atom:entry]

		set tree .tMain.fHdr.tree
		foreach e $entries {
			set title  [$e selectNodes string(atom:title/text())]
			set author [$e selectNodes string(atom:author/atom:name/text())]
			set time   [$e selectNodes string(atom:updated/text())]
			set link   [$e selectNodes string(atom:link/@href)]
			set body   [$e selectNodes string(atom:summary/text())]

			$tree insert {} end -text $title
		}

		$doc delete
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
.tMain.splitLR add [ttk::treeview .tMain.tSrcs]

## a splitter for top and bottom (headers and bodies)
.tMain.splitLR add [ttk::panedwindow .tMain.splitRTB -orient vertical]

# a tree for headers (threaded view)
frame .tMain.fHdr
pack [scrollbar .tMain.fHdr.scroll -orient vertical \
   -command [list .tMain.fHdr.tree yview]] \
      -fill y -side right
pack [ttk::treeview .tMain.fHdr.tree \
   -yscrollcommand [list .tMain.fHdr.scroll set]] \
      -fill both -expand 1 -side right

.tMain.splitRTB add .tMain.fHdr

# textbox for bodies
.tMain.splitRTB add [text .tMain.xBdy -state disabled]

