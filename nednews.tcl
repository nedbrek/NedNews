### gui
wm withdraw .
toplevel .tMain

## a splitter for left and right windows
pack [ttk::panedwindow .tMain.splitLR -orient horizontal] -expand 1 -fill both
# a tree for news sources
ttk::treeview .tMain.splitLR.tSrcs
.tMain.splitLR add .tMain.splitLR.tSrcs

## a splitter for top and bottom (headers and bodies)
ttk::panedwindow .tMain.splitLR.splitRTB -orient vertical
.tMain.splitLR add .tMain.splitLR.splitRTB

# a tree for headers (threaded view)
ttk::treeview .tMain.splitLR.splitRTB.tHdr
.tMain.splitLR.splitRTB add .tMain.splitLR.splitRTB.tHdr

# textbox for bodies
text .tMain.splitLR.splitRTB.xBdy -state disabled
.tMain.splitLR.splitRTB add .tMain.splitLR.splitRTB.xBdy

