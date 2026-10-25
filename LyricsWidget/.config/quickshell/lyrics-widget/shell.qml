import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Io

ShellRoot {
    PanelWindow {
        id: widgetWindow
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        mask: Region {
            item: root.editMode ? root : emptyMask
        }

        Item {
            id: emptyMask
            width: 0
            height: 0
        }

        property bool positionInitialized: false
        onWidthChanged: {
            if (!positionInitialized && width > 0 && height > 0) {
                root.x = width - root.width - 60
                root.y = height - root.height - 60
                positionInitialized = true
            }
        }

        IpcHandler {
            target: "lyrics"
            function toggle(): void { root.editMode = !root.editMode }
            function enable(): void { root.editMode = true }
            function disable(): void { root.editMode = false }
            function toggleVisible(): void { widgetWindow.visible = !widgetWindow.visible }
            function quit(): void { Qt.quit() }
        }

        ClippingRectangle {
            id: root
            width: 325
            height: 260
            radius: 24
            color: Qt.rgba(0.05, 0.05, 0.05, root.backgroundDimOpacity)
            opacity: root.widgetOpacity

            border.width: editMode ? 2 : 0
            border.color: "#80ffffff"

            // --- TRANSPARENCY AND APPEARANCE SETTINGS ---
            property real widgetOpacity: 0.88
            property real coverArtOpacity: 0.65
            property real backgroundDimOpacity: 0.30
            property real innerBoxOpacity: 0.55

            property bool editMode: false
            property real innerBoxWidthRatio: 0.92
            property real innerBoxHeightRatio: 0.48
            property int innerBoxPadding: 12
            property real innerBoxRadius: 12
            property int lyricsFontSize: 20
            property string lyricsFontFamily: "Inter"
            property int lyricsFontWeight: Font.Bold
            property color lyricsTextColor: "#ffffff"

            property string currentLyricLine: "Waiting for lyrics..."
            property string hdArtUrl: ""
            property int requestCounter: 0
            property var albumArtCache: ({})

            // First, selects the browser that is actively playing.
            property var activePlayer: {
                var list = Mpris.players.values
                if (!list || list.length === 0) return null

                for (var i = 0; i < list.length; i++) {
                    var p = list[i]
                    var id = String(p.identity || "").toLowerCase()
                    var bus = String(p.dbusName || "").toLowerCase()
                    var isBrowser = (id.indexOf("vivaldi") !== -1 || bus.indexOf("vivaldi") !== -1 ||
                                     id.indexOf("chromium") !== -1 || bus.indexOf("chromium") !== -1 ||
                                     id.indexOf("brave") !== -1 || bus.indexOf("brave") !== -1 ||
                                     id.indexOf("firefox") !== -1 || bus.indexOf("firefox") !== -1 ||
                                     id.indexOf("spotify") !== -1 || bus.indexOf("spotify") !== -1 ||
                                     id.indexOf("floorp") !== -1 || bus.indexOf("floorp") !== -1)
                    if (isBrowser && p.playbackState === MprisPlaybackState.Playing) {
                        return p
                    }
                }

                for (var j = 0; j < list.length; j++) {
                    var p2 = list[j]
                    var id2 = String(p2.identity || "").toLowerCase()
                    var bus2 = String(p2.dbusName || "").toLowerCase()
                    if (id2.indexOf("vivaldi") !== -1 || bus2.indexOf("vivaldi") !== -1 ||
                        id2.indexOf("chromium") !== -1 || bus2.indexOf("chromium") !== -1 ||
                        id2.indexOf("floorp") !== -1 || bus2.indexOf("floorp") !== -1) {
                        return p2
                    }
                }
                return list[0]
            }

            property string mprisArtUrl: activePlayer ? String(activePlayer.trackArtUrl || "") : ""
            property string trackTitle: activePlayer ? String(activePlayer.trackTitle || "") : ""
            property string trackAlbum: activePlayer ? String(activePlayer.trackAlbum || "") : ""
            property string trackArtist: {
                if (!activePlayer) return ""
                if (typeof activePlayer.trackArtist === "string" && activePlayer.trackArtist.length > 0) {
                    return activePlayer.trackArtist
                }
                if (typeof activePlayer.trackAlbumArtist === "string" && activePlayer.trackAlbumArtist.length > 0) {
                    return activePlayer.trackAlbumArtist
                }
                if (typeof activePlayer.trackArtists === "string" && activePlayer.trackArtists.length > 0) {
                    return activePlayer.trackArtists
                }
                return ""
            }

            onTrackTitleChanged: artFetchTimer.restart()
            onTrackArtistChanged: artFetchTimer.restart()
            onTrackAlbumChanged: artFetchTimer.restart()
            Component.onCompleted: artFetchTimer.restart()

            Timer {
                id: artFetchTimer
                interval: 300
                repeat: false
                onTriggered: root.fetchHighResArt()
            }

            function isArtistMatch(resultArtist, targetArtist) {
                var a = String(resultArtist || "").toLowerCase().trim()
                var b = String(targetArtist || "").toLowerCase().trim()
                if (a.length === 0 || b.length === 0) return false
                return a === b || a.indexOf(b) !== -1 || b.indexOf(a) !== -1
            }

            function fetchHighResArt() {
                var cleanTitle = trackTitle
                    .replace(/\(.*?\)|\[.*?\]/g, "")
                    .replace(/[-–—]\s*(Remaster.*|Single.*|Explicit.*|Official.*|Audio.*|Video.*)$/gi, "")
                    .trim()
                var cleanArtist = trackArtist.replace(/- Topic$/gi, "").trim()
                var cleanAlbum = trackAlbum.replace(/\(.*?\)|\[.*?\]/g, "").trim()

                // Don't search for a random song if the artist name hasn't been fetched yet.
                if (cleanArtist.length === 0) {
                    hdArtUrl = ""
                    if (cleanTitle.length > 0) {
                        artFetchTimer.restart()
                    }
                    return
                }

                // Fetch instantly from cache if the same album is already cached.
                var cacheKey = (cleanArtist + "|" + cleanAlbum).toLowerCase()
                if (cleanAlbum.length > 0 && root.albumArtCache[cacheKey]) {
                    root.hdArtUrl = root.albumArtCache[cacheKey]
                    return
                }

                root.requestCounter += 1
                var currentReq = root.requestCounter

                console.log("Searching for Cover Art -> Artist:", cleanArtist, "| Album:", cleanAlbum, "| Song:", cleanTitle)

                // Step 1: Search directly for the original album if the album name is known.
                if (cleanAlbum.length > 0) {
                    var albumQuery = (cleanArtist + " " + cleanAlbum).trim()
                    var albumUrl = "https://itunes.apple.com/search?term=" + encodeURIComponent(albumQuery) + "&entity=album&limit=10"
                    var xhrAlbum = new XMLHttpRequest()
                    xhrAlbum.onreadystatechange = function() {
                        if (xhrAlbum.readyState === XMLHttpRequest.DONE) {
                            if (currentReq !== root.requestCounter) return
                            if (xhrAlbum.status === 200) {
                                try {
                                    var res = JSON.parse(xhrAlbum.responseText)
                                    var albumLower = cleanAlbum.toLowerCase()
                                    for (var i = 0; i < res.results.length; i++) {
                                        var r = res.results[i]
                                        var col = String(r.collectionName || "").toLowerCase()
                                        if (root.isArtistMatch(r.artistName, cleanArtist) &&
                                            (col.indexOf(albumLower) !== -1 || albumLower.indexOf(col) !== -1)) {
                                            var hd = r.artworkUrl100.replace("100x100bb", "1000x1000bb")
                                            root.albumArtCache[cacheKey] = hd
                                            root.hdArtUrl = hd
                                            return
                                        }
                                    }
                                } catch (e) {}
                            }
                            // If not found in the album search, proceed to Step 2 (song search)
                            root.fetchSongArt(cleanArtist, cleanAlbum, cleanTitle, currentReq, cacheKey)
                        }
                    }
                    xhrAlbum.open("GET", albumUrl)
                    xhrAlbum.send()
                } else {
                    root.fetchSongArt(cleanArtist, cleanAlbum, cleanTitle, currentReq, cacheKey)
                }
            }

            function fetchSongArt(cleanArtist, cleanAlbum, cleanTitle, currentReq, cacheKey) {
                if (cleanTitle.length === 0) {
                    root.hdArtUrl = ""
                    return
                }

                var songQuery = (cleanArtist + " " + cleanTitle).trim()
                var songUrl = "https://itunes.apple.com/search?term=" + encodeURIComponent(songQuery) + "&entity=song&limit=20"
                var xhrSong = new XMLHttpRequest()
                xhrSong.onreadystatechange = function() {
                    if (xhrSong.readyState === XMLHttpRequest.DONE) {
                        if (currentReq !== root.requestCounter) return
                        if (xhrSong.status === 200) {
                            try {
                                var res = JSON.parse(xhrSong.responseText)
                                var chosen = null
                                var albumLower = cleanAlbum.toLowerCase()

                                // Filter to keep only results with an exact artist name match.
                                var artistMatches = []
                                for (var i = 0; i < res.results.length; i++) {
                                    if (root.isArtistMatch(res.results[i].artistName, cleanArtist)) {
                                        artistMatches.push(res.results[i])
                                    }
                                }

                                // Priority 1: Album name match
                                if (albumLower.length > 0) {
                                    for (var j = 0; j < artistMatches.length; j++) {
                                        var col = String(artistMatches[j].collectionName || "").toLowerCase()
                                        if (col.indexOf(albumLower) !== -1 || albumLower.indexOf(col) !== -1) {
                                            chosen = artistMatches[j]
                                            break
                                        }
                                    }
                                }

                                // Priority 2: Studio album (non-compilation, non-single)
                                if (!chosen) {
                                    for (var k = 0; k < artistMatches.length; k++) {
                                        var colName = String(artistMatches[k].collectionName || "")
                                        if (!/greatest hits|best of|essential|live|single|compilation|anthology/i.test(colName)) {
                                            chosen = artistMatches[k]
                                            break
                                        }
                                    }
                                }

                                // Priority 3: First match for the artist
                                if (!chosen && artistMatches.length > 0) {
                                    chosen = artistMatches[0]
                                }

                                if (chosen && chosen.artworkUrl100) {
                                    var hd = chosen.artworkUrl100.replace("100x100bb", "1000x1000bb")
                                    if (cleanAlbum.length > 0) {
                                        root.albumArtCache[cacheKey] = hd
                                    }
                                    root.hdArtUrl = hd
                                    return
                                }
                            } catch (e) {}
                        }
                        root.hdArtUrl = ""
                    }
                }
                xhrSong.open("GET", songUrl)
                xhrSong.send()
            }

            Image {
                id: coverArt
                anchors.fill: parent
                source: root.hdArtUrl !== "" ? root.hdArtUrl : root.mprisArtUrl
                fillMode: Image.PreserveAspectCrop
                opacity: root.coverArtOpacity
                asynchronous: true
                cache: false
                smooth: true
                mipmap: true
            }

            Rectangle {
                anchors.fill: parent
                color: "#000000"
                opacity: root.backgroundDimOpacity
            }

            Rectangle {
                id: innerBox
                width: parent.width * root.innerBoxWidthRatio
                height: parent.height * root.innerBoxHeightRatio
                radius: root.innerBoxRadius
                color: Qt.rgba(0, 0, 0, root.innerBoxOpacity)
                anchors.centerIn: parent

                Text {
                    id: lyricsText
                    anchors.fill: parent
                    anchors.margins: root.innerBoxPadding
                    text: root.currentLyricLine
                    color: root.lyricsTextColor
                    font.family: root.lyricsFontFamily
                    font.pixelSize: root.lyricsFontSize
                    font.weight: root.lyricsFontWeight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.WordWrap
                    elide: Text.ElideRight
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.editMode
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                drag.target: root
                drag.minimumX: 0
                drag.maximumX: widgetWindow.width - root.width
                drag.minimumY: 0
                drag.maximumY: widgetWindow.height - root.height
                cursorShape: root.editMode ? Qt.SizeAllCursor : Qt.ArrowCursor

                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton) {
                        root.editMode = false
                    }
                }
            }

            Process {
                id: lyricsProcess
                command: ["sptlrx", "pipe"]
                running: true
                stdout: SplitParser {
                    onRead: data => {
                        var line = String(data).trim()
                        if (line.length > 0) {
                            root.currentLyricLine = line
                        }
                    }
                }
            }

            Timer {
                interval: 3000
                running: !lyricsProcess.running
                repeat: true
                onTriggered: lyricsProcess.running = true
            }
        }
    }
}
