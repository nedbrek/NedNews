package require Tk
package require http
package require tdom
package require nntp
package require sqlite3

### database
proc createDb {} {
	if {[info exists ::db]} {
		::db close
	}
	sqlite3 ::db "test.db"

	::db eval {
		CREATE TABLE msgs(
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			author TEXT not NULL,
			subject TEXT not NULL,
			date TEXT not NULL,
			status not NULL,
			origHdrs TEXT not NULL,
			body TEXT not NULL
		)
	}

	::db eval {
		CREATE TABLE nntp(
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			name TEXT not NULL,
			host TEXT not NULL,
			port TEXT not NULL,
			user TEXT not NULL,
			pass TEXT not NULL,
			groups TEXT not NULL,
			lastFetchId TEXT not NULL
		)
	}
}

### http
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

#set httpToken [::http::geturl $url -timeout 5000 -command httpDone]

### nntp
# pull the group status
proc fetchNntpMsgList {nc settings groupIdx} {

	set groupName [lindex [dict get $settings GROUPS] $groupIdx]
	set msgList [$nc group $groupName]

	return $msgList
	# lindex
	# 0 number of articles
	# 1 first id
	# 2 last id
	# 3 group name
}

# msg is a list with headers (one per element), a blank element, then the
# body (one line per element)
proc parseNntpMsg {msg} {
	set headers ""
	set body ""

	set inHeaders 1
	foreach l $msg {
		if {$inHeaders} {
			if {$l eq ""} {
				set inHeaders 0
			} else {
				lappend headers $l
			}
		} else {
			append body "$l\n"
		}
	}

	return [dict create HEADERS $headers BODY $body]
}

# extract the relevant info from headers
# (not currently used)
proc parseNntpHdrList {hdrList} {
	set ret [dict create FROM "" SUBJECT "" DATE ""]

	foreach hdr $hdrList {
		if {![regexp {(.*?): (.*)$} $hdr -> type value]} {
			continue
		}

		switch $type {
			From    { dict set ret FROM    $value }
			Subject { dict set ret SUBJECT $value }
			Date    { dict set ret DATE    $value }
		}
	}

	return $ret
}

# update the database with new messages for the given group
proc updateNntpGroup {accountId groupIndex} {
	set settings [::db eval {
		SELECT 'HOST', host, 'PORT', port, 'USER', user, 'PASS', pass, 'GROUPS', groups, 'LAST_MSG_ID', lastFetchId
		FROM nntp
		WHERE id = $accountId
	}]

	set nc [::nntp::nntp [dict get $settings HOST] [dict get $settings PORT]]
	$nc authinfo [dict get $settings USER] [dict get $settings PASS]

	set msgList [fetchNntpMsgList $nc $settings $groupIndex]
	set lastMsg [lindex $msgList 2]
	set lastFetched [dict get $settings LAST_MSG_ID]
	if {$lastFetched == $lastMsg} {
		# up to date
		$nc quit
		return
	}

	# set the current pointer to the next message
	if {$lastFetched eq ""} {
		# no prior history, fetch first message
		set lastFetch [lindex $msgList 1]
		$nc stat $lastFetched
	} else {
		# else, set cursor to last fetched, and advance
		$nc stat $lastFetched
		if {[catch {$nc next}]} {
			return ;# nothing new
		}
	}

	# don't fetch forever
	set ct 0

	::db eval {BEGIN TRANSACTION}

	set done 0
	while {$ct < 500 && !$done} {
		incr ct

		set overview [lindex [$nc xover] 0]
		# a single string with all this info, tab separated
		# 0 msgId
		# 1 subject
		# 2 author
		# 3 date
		# 4 idstring
		# 5 path
		# 6 body size
		# 7 header size
		# 8 xref
		set hdrList [split $overview "\t"]
		foreach {msgId subject author date idstring path bodySz hdrSz xref} $hdrList {
		}

		set lastFetched $msgId

		if {$bodySz > 300000} {
			# skip huge messages

			# but insert headers, so we can fetch it later
			::db eval {
				INSERT INTO msgs
				(author, subject, date, status, origHdrs, body)
				VALUES(
				$author, $subject, $date, "new", "NedNews_MsgId: $msgId, ""
				)
			}

			set done [catch {$nc next}]
			continue
		}

		set origMsg [$nc article]
		set dm [parseNntpMsg $origMsg]

		set origHdrs [dict get $dm HEADERS]
		set body     [dict get $dm BODY]

		::db eval {
			INSERT INTO msgs
			(author, subject, date, status, origHdrs, body)
			VALUES(
			$author, $subject, $date, "new", $origHdrs, $body
			)
		}

		set done [catch {$nc next}]
	}

	$nc quit
	::db eval {END TRANSACTION}

	::db eval {
		UPDATE nntp
		SET lastFetchId = $lastFetched
		WHERE id = $accountId
	}
}

if {0} {
	set f [open [file join ~ .nednewsrc]]
	set settings [read $f]
	close $f

	set nc [::nntp::nntp [dict get $settings HOST] [dict get $settings PORT]]
	$nc authinfo [dict get $settings USER] [dict get $settings PASS]

	set msgList [fetchNntpMsgList $nc $settings 0]
	set lastMsg [lindex $msgList 2]
	set hdrList [$nc xover [expr $lastMsg - 100] $lastMsg]; set tmp 0
	# msgId
	# subject
	# from
	# date
	# path
	# body size
	# header size
	# xref

	$nc quit

	# NOTE: newnews disabled at eternal-september.org
	set msgs [$nc newnews $groupName $lastDate]; set tmp 0

	# message handler
	foreach msg $txt {
		set dm [parseNntpMsg $msg]

		set origHdrs [dict get $dm HEADERS]
		set body     [dict get $dm BODY]

		set hdrDict [parseNntpHdrList $origHdrs]
		set author  [dict get $hdrDict FROM]
		set subject [dict get $hdrDict SUBJECT]
		set date    [dict get $hdrDict DATE]

		::db eval {BEGIN TRANSACTION}
		::db eval {
			INSERT INTO msgs
			(author, subject, date, status, origHdrs, body)
			VALUES(
			$author, $subject, $date, "new", $origHdrs, $body
			)
		}
		::db eval {END TRANSACTION}
	}

	set maxBody 0
	set oversz 154243
	foreach msg $txt {
		set dm [parseNntpMsg $msg]
		set bodySz [string bytelength [dict get $dm BODY]]
		if {$bodySz == $oversz} {
			puts [dict get $dm HEADERS]
		}
		set maxBody [expr {max($maxBody, $bodySz)}]
	}
}

proc clockScan {dateStr} {
	# try simple scan
	if {![catch {clock scan $dateStr} ret]} {
		return $ret
	}

	set badIndex [string first { +0000} $dateStr]
	set dateStr2 [string range $dateStr 0 $badIndex]
	if {![catch {clock scan "$dateStr2 GMT"} ret]} {
		return $ret
	}

	puts "ClockScan error on '$dateStr'"
	return 0
}

proc deleteMsg {w} {
	set sel [$w selection]
	foreach i $sel {
		set id [lindex [$w item $i -values] 0]
		::db eval {
			UPDATE msgs
			SET status = "deleted"
			WHERE id = $id
		}

		$w item $i -tags deleted
	}

	set nextId [$w next $i]
	if {$nextId ne "" && $nextId ne "{}"} {
		$w selection set $nextId
		$w focus $nextId
		$w see $nextId
	}
}

proc showBody {w} {
	set t .tMain.xBdy

	$t configure -state normal
	$t delete 1.0 end

	set sel [$w selection]
	if {[llength $sel] != 1} {
		$t configure -state disabled
		return
	}

	set id [lindex [$w item $sel -values] 0]

	set body [lindex [::db eval {SELECT body FROM msgs WHERE id=$id}] 0]
	$t insert 1.0 $body

	$t configure -state disabled
}

proc refresh {} {
	.tMain.fHdr.tree delete [.tMain.fHdr.tree children {}]

	set dbRes [::db eval {
		SELECT id, author, subject, date, status FROM msgs
		WHERE status != "deleted"
		ORDER BY id DESC LIMIT 100
	}]

	foreach {id author subject date status} $dbRes {
		.tMain.fHdr.tree insert {} 0 -text $subject -values [list $id $author $date $status]
	}
}

proc buildAccounts {w} {
	set nntp [::db eval {
		SELECT id, name, groups
		FROM nntp
	}]

	foreach {id name groups} $nntp {
		set par [$w insert {} end -text $name -values [list $id]]

		set ct 0
		foreach g $groups {
			$w insert $par end -text $g -values [list $id $ct]
			incr ct
		}
	}
}

### gui
set deletedFont [font create -overstrike 1]

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

.tMain.fHdr.tree configure -columns {1 2 3 4}
.tMain.fHdr.tree tag configure deleted -font $deletedFont

.tMain.splitRTB add .tMain.fHdr

# textbox for bodies
.tMain.splitRTB add [text .tMain.xBdy -state disabled]

### bindings
bind .tMain.fHdr.tree <<TreeviewSelect>> {showBody %W}
bind .tMain.fHdr.tree <Delete> {deleteMsg %W}

bind .tMain <space> { .tMain.xBdy yview scroll 1 page }

### runtime
sqlite3 ::db "test.db"
#::db function clockScan {clockScan}
buildAccounts .tMain.tSrcs

