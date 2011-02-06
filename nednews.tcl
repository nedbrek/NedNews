package require http
package require tdom

set url "http://semipublic.comp-arch.net/wiki/index.php?title=Special:RecentChanges&feed=atom"

set httpData ""
proc processXML {token} {
	set httpData [::http::data $token]
	set ::httpData $httpData
	set doc [dom parse $httpData]

	# try for atom
	$doc selectNodesNamespaces {atom http://www.w3.org/2005/Atom}
	set ns "atom:"
	set title  "atom:title"
	set author "atom:author/atom:name"
	set date   "atom:updated"
	set link   "atom:link/@href"
	set body   "atom:summary"

	set entries [$doc selectNodes /atom:feed/atom:entry]
	if {$entries eq ""} {
		# try old school RSS tags
		$doc selectNodesNamespaces {dc http://purl.org/dc/elements/1.1/}

		set entries [$doc selectNodes //item]

		set ns ""
		set title  "title"
		set author "dc:creator"
		set date   "pubDate"
		set link   "link/text()"
		set body   "content:encoded"
	}

	set tree .tMain.fHdr.tree
	$tree delete [$tree children {}]

	foreach e $entries {
		set ttl [$e selectNodes string($title/text())]
		set aut [$e selectNodes string($author/text())]
		set dte [$e selectNodes string($date/text())]
		set lnk [$e selectNodes string($link)]
		set bdy [$e selectNodes string($body/text())]

		$tree insert {} end -text $ttl

		update; # we may be here a while
	}

	$doc delete
}

proc httpDone {token} {

	set fail 0
	switch [::http::status $token] {
		ok {
			if {[::http::ncode $token] != 200} {
				puts "HTTP server returned non-OK code [::http::ncode $token]"
				puts "HTTP code is [::http::code]"
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
		processXML $token
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

