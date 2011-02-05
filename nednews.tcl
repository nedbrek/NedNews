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

