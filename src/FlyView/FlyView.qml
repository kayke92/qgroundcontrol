import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

import QtLocation
import QtPositioning
import QtQuick.Window
import QtQml.Models

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlyView
import QGroundControl.FlightMap
import QGroundControl.Toolbar
import QGroundControl.Viewer3D

Item {
    id: _root

    readonly property bool _is3DMode:       QGCViewer3DManager.displayMode === QGCViewer3DManager.View3D
    readonly property bool _keepSceneAlive: QGroundControl.settingsManager.viewer3DSettings.keepSceneAlive.rawValue

    // Carpcatcher view modes:
    // 0 = map, 1 = camera, 2 = sonar
    // 3 = map+camera, 4 = map+sonar, 5 = camera+sonar
    property int _carpcatcherViewMode: 3
    property int _carpcatcherLastComboMode: 3

    readonly property bool _carpcatcherShowSonar: _carpcatcherViewMode === 2 ||
                                                   _carpcatcherViewMode === 4 ||
                                                   _carpcatcherViewMode === 5
    readonly property bool _carpcatcherShowMapArea: _carpcatcherViewMode !== 2
    readonly property real _carpcatcherContentTop: modeBar.y + modeBar.height
    readonly property real _carpcatcherContentHeight: Math.max(0, height - _carpcatcherContentTop)
    readonly property real _carpcatcherSonarHeight: (_carpcatcherViewMode === 2 ||
                                                       _carpcatcherViewMode === 4 ||
                                                       _carpcatcherViewMode === 5)
                                                      ? _carpcatcherContentHeight
                                                      : (_carpcatcherShowSonar ? _carpcatcherContentHeight * 0.44 : 0)

    // These should only be used by MainRootWindow
    property var planController:    _planController
    property var guidedController:  _guidedController

    PlanMasterController {
        id:                     _planController
        flyView:                true
        Component.onCompleted:  start()
    }

    property bool   _mainWindowIsMap:       mapControl.pipState.state === mapControl.pipState.fullState ||
                                              mapControl.pipState.state === mapControl.pipState.splitLeftState
    property bool   _isFullWindowItemDark:  _mainWindowIsMap ? mapControl.isSatelliteMap : true
    property var    _activeVehicle:         QGroundControl.multiVehicleManager.activeVehicle
    property var    _missionController:     _planController.missionController
    property var    _geoFenceController:    _planController.geoFenceController
    property var    _rallyPointController:  _planController.rallyPointController
    property real   _margins:               ScreenTools.defaultFontPixelWidth / 2
    property var    _guidedController:      guidedActionsController
    property var    _guidedValueSlider:     guidedValueSlider
    property var    _widgetLayer:           widgetLayer
    property real   _toolsMargin:           ScreenTools.defaultFontPixelWidth * 0.75
    property rect   _centerViewport:        Qt.rect(0, 0, width, height)
    property real   _rightPanelWidth:       ScreenTools.defaultFontPixelWidth * 30
    property var    _mapControl:            mapControl
    property real   _widgetMargin:          ScreenTools.defaultFontPixelWidth * 0.75

    property real   _fullItemZorder:    0
    property real   _pipItemZorder:     QGroundControl.zOrderWidgets

    // ---------------------------------------------------------------------
    // CARPCATCHER LIVECHART BASIS
    // ---------------------------------------------------------------------
    property bool   _bathymetryRecording:       false
    property bool   _bathymetryDemoMode:        true
    property real   _liveDepthMeters:           4.80
    property real   _liveWaterTemperature:      16.8
    property int    _bathymetrySampleInterval:  900
    property int    _bathymetryMaxSamples:      2500

    property bool _demoTrackInitialized: false
    property real _demoLatitude: 0.0
    property real _demoLongitude: 0.0
    property real _demoHeadingDeg: 70.0
    property int _demoTrackStep: 0
    property real _demoStepMeters: 0.75

    // Laat uitsluitend de meest recente GPS/dieptemeting op de kaart zien.
    property bool _bathymetryHasCurrentPosition: false
    property real _bathymetryCurrentLatitude: 0.0
    property real _bathymetryCurrentLongitude: 0.0

    ListModel {
        id: bathymetrySamples
    }
    property real _bathymetryMinDepth: 0.0
    property real _bathymetryMaxDepth: 6.0
    property real _bathymetryContourStep: 0.5

    ListModel { id: bathymetryHeatCells }
    // Kwartmeter-raster verkleint zichtbare kleurblokken; Android-limiet blijft actief.
    property real _heatCellMeters: 0.25
    // Kleur uitsluitend binnen 2 meter van een echte GPS/dieptemeting.
    property real _heatRadiusMeters: 2.0

    // Fixed depth scale shared by renderer and legend; no per-track recolouring.
    function _bathymetryColor(depth) {
        var stops = [[229,57,53], [251,140,0], [253,216,53],
                     [67,160,71], [41,182,246], [21,101,192]]
        var t = Math.max(0, Math.min(5, depth))
        var i = Math.min(4, Math.floor(t))
        var u = t - i
        return Qt.rgba((stops[i][0] + (stops[i+1][0]-stops[i][0])*u)/255,
                       (stops[i][1] + (stops[i+1][1]-stops[i][1])*u)/255,
                       (stops[i][2] + (stops[i+1][2]-stops[i][2])*u)/255, 1)
    }

    function _isContourDepth(depth) {

        var step = Math.max(0.1, _bathymetryContourStep)

        var nearest = Math.round(depth / step) * step

        return Math.abs(depth - nearest) <= 0.055

    }


    function _heatLonScale(lat) {
        return 111320.0 * Math.max(0.15, Math.cos(lat * Math.PI / 180.0))
    }
    function _heatDistance(lat1, lon1, lat2, lon2) {
        var dy=(lat2-lat1)*111320.0
        var dx=(lon2-lon1)*_heatLonScale((lat1+lat2)*0.5)
        return Math.sqrt(dx*dx+dy*dy)
    }
    // The Canvas uses raw samples directly. Do not build an unused second grid.
    function _rebuildHeatmap() {
        var lo = Infinity, hi = -Infinity
        for (var i = 0; i < bathymetrySamples.count; i++) {
            var d = bathymetrySamples.get(i).depth
            if (!isFinite(d) || d <= 0) continue
            lo = Math.min(lo, d)
            hi = Math.max(hi, d)
        }
        _bathymetryMinDepth = isFinite(lo) ? lo : 0
        _bathymetryMaxDepth = isFinite(hi) ? hi : 0
    }

    function _depthColor(depth) {
        if (depth < 1.0) return "#e53935"   // rood
        if (depth < 2.0) return "#fb8c00"   // oranje
        if (depth < 3.0) return "#fdd835"   // geel
        if (depth < 4.0) return "#43a047"   // groen
        if (depth < 5.0) return "#29b6f6"   // lichtblauw
        return "#1565c0"                    // donkerblauw
    }

    function _recordBathymetrySample() {
        if (!_bathymetryRecording || !mapControl) {
            return
        }

        var coordinate = mapControl.center
        var usingVehicleGps = false

        if (_activeVehicle && _activeVehicle.coordinate && _activeVehicle.coordinate.isValid) {
            coordinate = _activeVehicle.coordinate
            usingVehicleGps = true
        }

        // Zonder Pixhawk/Kogger bouwen we alvast een zichtbare demo rondom
        // het kaartcentrum. Zodra de echte GPS beschikbaar is gebruiken we
        // automatisch de voertuigpositie.
        var latitude = coordinate.latitude
        var longitude = coordinate.longitude
        var index = bathymetrySamples.count

        if (!usingVehicleGps) {
            if (!_demoTrackInitialized) {
                _demoLatitude = coordinate.latitude
                _demoLongitude = coordinate.longitude
                _demoHeadingDeg = 70.0
                _demoTrackStep = 0
                _demoTrackInitialized = true
            }

            if (_demoTrackStep > 0 && (_demoTrackStep % 18) === 0) {
                _demoHeadingDeg += 8.0
            }

            var headingRad = _demoHeadingDeg * Math.PI / 180.0
            var northMeters = Math.cos(headingRad) * _demoStepMeters
            var eastMeters = Math.sin(headingRad) * _demoStepMeters

            _demoLatitude += northMeters / 111320.0
            _demoLongitude += eastMeters / _heatLonScale(_demoLatitude)

            latitude = _demoLatitude
            longitude = _demoLongitude
            _demoTrackStep++
        }

        _bathymetryCurrentLatitude = latitude
        _bathymetryCurrentLongitude = longitude
        _bathymetryHasCurrentPosition = true

        if (bathymetrySamples.count >= _bathymetryMaxSamples) {
            bathymetrySamples.remove(0, 1)
        }

        bathymetrySamples.append({
            "latitude": latitude,
            "longitude": longitude,
            "depth": _liveDepthMeters,
            "temperature": _liveWaterTemperature,
            "timestampMs": Date.now()
        })
        if (bathymetrySamples.count > 0) {
            _rebuildHeatmap()
        }
    }

    function _clearBathymetry() {
        _demoTrackInitialized = false
        _demoLatitude = 0.0
        _demoLongitude = 0.0
        _demoHeadingDeg = 70.0
        _demoTrackStep = 0
        _bathymetryHasCurrentPosition = false
        _bathymetryCurrentLatitude = 0.0
        _bathymetryCurrentLongitude = 0.0
        bathymetrySamples.clear()
        bathymetryHeatCells.clear()
    }

    Timer {
        id: bathymetryRecordTimer
        interval: _bathymetrySampleInterval
        repeat: true
        running: _bathymetryRecording
        onTriggered: {
            // Voor de V5.0 basis komt de diepte nog uit de simulator.
            // Later vervangt de Kogger/Pi bridge alleen deze live waarde.
            if (_bathymetryDemoMode) {
                var n = bathymetrySamples.count
                _liveDepthMeters = 3.7
                                  + Math.sin(n * 0.28) * 0.55
                                  + Math.sin(n * 0.075) * 0.35
            }
            _recordBathymetrySample()
        }
    }

    function _setViewMode(mode) {
        _carpcatcherViewMode = mode

        if (mode >= 3) {
            _carpcatcherLastComboMode = mode
        }

        // Keep QGC's own video fullscreen flag out of the layout logic.
        QGroundControl.videoManager.fullScreen = false

        // We still use the proven QGC PipView internally to arrange map/video,
        // but Carpcatcher now owns the visible mode.
        if (mode === 0 || mode === 4) {
            _pipView.splitFullItem = 1
        } else if (mode === 1 || mode === 5) {
            _pipView.splitFullItem = 2
        } else if (mode === 3) {
            _pipView.splitFullItem = 0
        }
    }

    function _cycleCombo() {
        if (_carpcatcherViewMode < 3) {
            _setViewMode(_carpcatcherLastComboMode)
        } else if (_carpcatcherViewMode === 3) {
            _setViewMode(4)
        } else if (_carpcatcherViewMode === 4) {
            _setViewMode(5)
        } else {
            _setViewMode(3)
        }
    }

    function _comboLabel() {
        if (_carpcatcherViewMode === 4 || (_carpcatcherViewMode < 3 && _carpcatcherLastComboMode === 4)) {
            return "COMBI K+S"
        }
        if (_carpcatcherViewMode === 5 || (_carpcatcherViewMode < 3 && _carpcatcherLastComboMode === 5)) {
            return "COMBI C+S"
        }
        return "COMBI K+C"
    }

    function _calcCenterViewPort() {
        var newToolInset = Qt.rect(0, 0, width, height)
        toolstrip.adjustToolInset(newToolInset)
    }

    function dropMainStatusIndicatorTool() {
        toolbar.dropMainStatusIndicatorTool();
    }

    QGCToolInsets {
        id:                     _toolInsets
        topEdgeLeftInset:       toolbar.height + modeBar.height
        topEdgeCenterInset:     topEdgeLeftInset
        topEdgeRightInset:      topEdgeLeftInset
        leftEdgeBottomInset:    _pipView.leftEdgeBottomInset
        bottomEdgeLeftInset:    _pipView.bottomEdgeLeftInset
    }

    // ---------------------------------------------------------------------
    // CARPCATCHER MODE BAR
    // ---------------------------------------------------------------------
    Rectangle {
        id: modeBar
        x: 0
        y: toolbar.visible ? toolbar.height : 0
        width: parent.width
        height: Math.max(38, ScreenTools.defaultFontPixelHeight * 2.2)
        z: QGroundControl.zOrderTopMost + 10
        color: "#10151b"
        border.color: "#2a323a"
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 5
            anchors.rightMargin: 5
            anchors.topMargin: 4
            anchors.bottomMargin: 4
            spacing: 5

            Repeater {
                model: [
                    { label: "KAART", mode: 0 },
                    { label: "CAMERA", mode: 1 },
                    { label: "SONAR", mode: 2 }
                ]

                delegate: Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 5
                    color: _carpcatcherViewMode === modelData.mode ? "#ff7a00" : "#1b232c"
                    border.color: _carpcatcherViewMode === modelData.mode ? "#ff9b42" : "#3b4651"
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: modelData.label
                        color: "white"
                        font.bold: true
                        font.pixelSize: Math.max(11, ScreenTools.defaultFontPixelHeight * 0.72)
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: _setViewMode(modelData.mode)
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 5
                color: _carpcatcherViewMode >= 3 ? "#ff7a00" : "#1b232c"
                border.color: _carpcatcherViewMode >= 3 ? "#ff9b42" : "#3b4651"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: _comboLabel()
                    color: "white"
                    font.bold: true
                    font.pixelSize: Math.max(9, ScreenTools.defaultFontPixelHeight * 0.60)
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: _cycleCombo()
                }
            }
        }
    }

    // ---------------------------------------------------------------------
    // MAP + CAMERA AREA
    // ---------------------------------------------------------------------
    Item {
        id: mapHolder
        x: 0
        y: _carpcatcherContentTop
        width: (_carpcatcherViewMode === 4 || _carpcatcherViewMode === 5) ? parent.width * 0.45 : parent.width
        height: _carpcatcherShowMapArea
                  ? ((_carpcatcherViewMode === 4 || _carpcatcherViewMode === 5)
                       ? _carpcatcherContentHeight
                       : Math.max(0, _carpcatcherContentHeight - _carpcatcherSonarHeight))
                  : 0
        visible: _carpcatcherShowMapArea && height > 0
        clip: true

        Rectangle {
            id: depthLegend
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.leftMargin: 8
            anchors.bottomMargin: 8
            width: 176
            height: 30
            radius: 5
            color: "#d610151b"
            border.color: "#3b4651"
            border.width: 1
            z: 1200
            visible: bathymetrySamples.count > 0

            Column {
                anchors.centerIn: parent
                spacing: 2
                Rectangle {
                    width: 156
                    height: 8
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: _bathymetryColor(0) }
                        GradientStop { position: 0.2; color: _bathymetryColor(1) }
                        GradientStop { position: 0.4; color: _bathymetryColor(2) }
                        GradientStop { position: 0.6; color: _bathymetryColor(3) }
                        GradientStop { position: 0.8; color: _bathymetryColor(4) }
                        GradientStop { position: 1.0; color: _bathymetryColor(5) }
                    }
                }
                Item {
                    width: 156; height: 9
                    Repeater {
                        model: 6
                        delegate: Text {
                            x: Math.max(0, Math.min(156-width, index*31.2-width/2))
                            text: index === 5 ? "5+ m" : index + " m"
                            color: "white"
                            font.pixelSize: 8
                        }
                    }
                }
            }
        }

        FlyViewMap {
            id:                     mapControl
            planMasterController:   _planController
            rightPanelWidth:        ScreenTools.defaultFontPixelHeight * 9
            pipView:                _pipView
            pipMode:                mapControl.pipState.state === mapControl.pipState.pipState
            toolInsets:             customOverlay.totalToolInsets
            mapName:                "FlightDisplayView"
            enabled:                !_is3DMode
            visible:                !_is3DMode

            // Doorlopende bathymetrische laag: kleine textuur, expliciete schaal.
            Canvas {
                id: bathymetrySmoothCanvas
                width: Math.max(1, Math.ceil(parent.width / 2))
                height: Math.max(1, Math.ceil(parent.height / 2))
                transform: Scale {
                    xScale: mapControl.width / bathymetrySmoothCanvas.width
                    yScale: mapControl.height / bathymetrySmoothCanvas.height
                }
                z: 45
                enabled: false
                visible: bathymetrySamples.count >= 2
                smooth: true
                renderTarget: Canvas.Image
                renderStrategy: Canvas.Immediate
                property string renderStatus: "WACHT OP DATA"
                onAvailableChanged: if (available) requestPaint()
                onVisibleChanged: if (visible) requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                onPaint: {
                    var ctx = getContext("2d")
                    if (!ctx) { renderStatus = "WACHT OP CANVAS"; return }
                    ctx.clearRect(0, 0, width, height)
                    renderStatus = "WACHT OP DATA"
                    if (bathymetrySamples.count < 2) return
                    try {
                        if (!mapControl.mapReady) { renderStatus = "WACHT OP KAART"; return }
                        var centre = mapControl.center
                        var origin = mapControl.fromCoordinate(centre, false)
                        var north = mapControl.fromCoordinate(centre.atDistanceAndAzimuth(1, 0), false)
                        var mx = north.x - origin.x
                        var my = north.y - origin.y
                        var ppm = Math.sqrt(mx * mx + my * my)
                        if (!isFinite(ppm) || ppm <= 0) { renderStatus = "GEEN PROJECTIE"; return }
                        var cw = Math.ceil(width), ch = Math.ceil(height)
                        var sx = mapControl.width / cw, sy = mapControl.height / ch
                        var radius = _heatRadiusMeters
                        var rx = radius * ppm / sx, ry = radius * ppm / sy
                        // Sample-first accumulation: only visit pixels near measurements.
                        var sums = new Float32Array(cw * ch)
                        var weights = new Float32Array(cw * ch)
                        var nearest = new Float32Array(cw * ch)
                        var hits = 0
                        // Merge exactly coincident positions for painting only.
                        // Keep their weight/count; never discard raw measurements.
                        var grouped = {}, positions = []
                        for (var gi = 0; gi < bathymetrySamples.count; gi++) {
                            var raw = bathymetrySamples.get(gi)
                            if (!isFinite(raw.depth) || raw.depth <= 0) continue
                            var key = raw.latitude + ":" + raw.longitude
                            if (grouped[key] === undefined) {
                                grouped[key] = positions.length
                                positions.push({latitude:raw.latitude, longitude:raw.longitude, total:raw.depth, count:1})
                            } else {
                                var existing = positions[grouped[key]]
                                existing.total += raw.depth
                                existing.count++
                            }
                        }
                        for (var i = 0; i < positions.length; i++) {
                            var s = positions[i]
                            s.depth = s.total / s.count
                            if (!isFinite(s.depth) || s.depth <= 0) continue
                            var p = mapControl.fromCoordinate(QtPositioning.coordinate(s.latitude, s.longitude), false)
                            if (!isFinite(p.x) || !isFinite(p.y)) continue
                            var x = p.x / sx, y = p.y / sy
                            var x0 = Math.max(0, Math.floor(x - rx))
                            var x1 = Math.min(cw - 1, Math.ceil(x + rx))
                            var y0 = Math.max(0, Math.floor(y - ry))
                            var y1 = Math.min(ch - 1, Math.ceil(y + ry))
                            for (var py = y0; py <= y1; py++) {
                                for (var px = x0; px <= x1; px++) {
                                    var dx = (px + 0.5 - x) * sx / ppm
                                    var dy = (py + 0.5 - y) * sy / ppm
                                    var d = Math.sqrt(dx * dx + dy * dy)
                                    if (d >= radius) continue
                                    var k = py * cw + px
                                    // Weight reaches zero smoothly at the 2 m boundary.
                                    var taper = 1 - (d * d) / (radius * radius)
                                    var w = s.count * taper * taper / Math.max(0.20, d * d)
                                    if (weights[k] === 0) { nearest[k] = d; hits++ }
                                    else nearest[k] = Math.min(nearest[k], d)
                                    sums[k] += s.depth * w
                                    weights[k] += w
                                }
                            }
                        }
                        // Reuse colours instead of rebuilding a palette per pixel.
                        var palette = []
                        for (var ci = 0; ci <= 500; ci++) {
                            var col = _bathymetryColor(ci / 100)
                            palette.push(col)
                        }
                        for (var k2 = 0; k2 < weights.length; k2++) {
                            if (weights[k2] === 0) continue
                            var fade = Math.max(0, Math.min(1, (radius-nearest[k2])/(radius*0.35)))
                            fade = fade * fade * (3 - 2 * fade)
                            var depth = sums[k2] / weights[k2]
                            ctx.fillStyle = palette[Math.max(0, Math.min(500, Math.round(depth * 100)))]
                            ctx.globalAlpha = 0.80 * fade
                            ctx.fillRect(k2 % cw, Math.floor(k2 / cw), 1, 1)
                        }
                        ctx.globalAlpha = 1
                        renderStatus = hits > 0 ? "GETEKEND" : "BUITEN BEELD / ZOOM IN"
                    } catch (error) {
                        ctx.globalAlpha = 1
                        renderStatus = "TEKENFOUT"
                        console.warn("Carpcatcher bathymetry:", error)
                    }
                }
            }

            // Coalesce requests without postponing forever during movement.
            Timer {
                id: bathymetrySmoothRefresh
                interval: 32
                repeat: false
                function schedule() { if (!running) start() }
                onTriggered: bathymetrySmoothCanvas.requestPaint()
            }
            Connections {
                target: bathymetrySamples
                function onCountChanged() { bathymetrySmoothRefresh.schedule() }
            }
            Connections {
                target: bathymetryHeatCells
                function onCountChanged() { bathymetrySmoothRefresh.schedule() }
            }
            Connections {
                target: mapControl
                function onMapReadyChanged() { bathymetrySmoothRefresh.schedule() }
                function onCenterChanged() { bathymetrySmoothRefresh.schedule() }
                function onZoomLevelChanged() { bathymetrySmoothRefresh.schedule() }
                function onBearingChanged() { bathymetrySmoothRefresh.schedule() }
                function onTiltChanged() { bathymetrySmoothRefresh.schedule() }
            }

            // Eén actueel GPS-punt; de volledige historische meetroute blijft verborgen.
            MapQuickItem {
                id: bathymetryCurrentPositionItem
                visible: _bathymetryHasCurrentPosition
                coordinate: QtPositioning.coordinate(_bathymetryCurrentLatitude, _bathymetryCurrentLongitude)
                anchorPoint.x: 12
                anchorPoint.y: 12
                z: 60

                sourceItem: Item {
                    width: 24
                    height: 24

                    Rectangle {
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                        radius: 9
                        color: "#ff7a00"
                        border.color: "#ffffff"
                        border.width: 2
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 4
                        height: 4
                        radius: 2
                        color: "#17212b"
                    }
                }
            }

            MapItemView {
                id: bathymetryMapItems
                model: bathymetrySamples
                visible: false

                delegate: MapQuickItem {
                    coordinate: QtPositioning.coordinate(model.latitude, model.longitude)
                    anchorPoint.x: 5
                    anchorPoint.y: 5
                    z: 50

                    sourceItem: Rectangle {
                        width: 10
                        height: 10
                        radius: 5
                        color: _depthColor(model.depth)
                        border.color: "#d9ffffff"
                        border.width: 1

                        ToolTip.visible: sampleMouse.containsMouse
                        ToolTip.text: model.depth.toFixed(2) + " m"

                        MouseArea {
                            id: sampleMouse
                            anchors.fill: parent
                            hoverEnabled: true
                        }
                    }
                }
            }

            Rectangle {
                id: liveChartHud
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 8
                width: Math.min(parent.width * 0.40, 220)
                height: 88
                radius: 7
                color: "#dc10151b"
                border.color: _bathymetryRecording ? "#ff7a00" : "#3b4651"
                border.width: 1
                z: 1000

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        text: "LIVECHART  " + (_bathymetryDemoMode ? "DEMO" : "LIVE")
                        color: _bathymetryRecording ? "#ff9b42" : "#d7e2eb"
                        font.bold: true
                        font.pixelSize: 11
                    }

                    Text {
                        text: _liveDepthMeters.toFixed(2) + " m   •   " + bathymetrySamples.count + " punten"
                        color: "white"
                        font.bold: true
                        font.pixelSize: 14
                    }

                    Text {
                        text: "DIEPTE " + _bathymetryMinDepth.toFixed(1) + "–" + _bathymetryMaxDepth.toFixed(1) + " m"
                        color: bathymetrySamples.count > 0 ? "#54d17a" : "#ff5252"
                        font.bold: true
                        font.pixelSize: 11
                    }

                    Text {
                        text: (_bathymetryRecording ? "REC • " : "STOP • ") + bathymetrySmoothCanvas.renderStatus
                        color: _bathymetryRecording ? "#54d17a" : "#aab6c0"
                        font.pixelSize: 10
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        _bathymetryRecording = !_bathymetryRecording
                        if (_bathymetryRecording && bathymetrySamples.count === 0) {
                            _recordBathymetrySample()
                        }
                    }
                }
            }

            Rectangle {
                anchors.top: liveChartHud.bottom
                anchors.right: parent.right
                anchors.topMargin: 5
                anchors.rightMargin: 8
                width: liveChartHud.width
                height: 30
                radius: 6
                color: "#dc10151b"
                border.color: "#3b4651"
                border.width: 1
                z: 1000

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 3
                    spacing: 3

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 4
                        color: _bathymetryRecording ? "#5b2b12" : "#1b232c"
                        Text {
                            anchors.centerIn: parent
                            text: _bathymetryRecording ? "STOP" : "START"
                            color: "white"
                            font.bold: true
                            font.pixelSize: 10
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: _bathymetryRecording = !_bathymetryRecording
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 4
                        color: "#1b232c"
                        Text {
                            anchors.centerIn: parent
                            text: "WIS KAART"
                            color: "white"
                            font.bold: true
                            font.pixelSize: 9
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: _clearBathymetry()
                        }
                    }
                }
            }
        }

        FlyViewVideo {
            id:                         videoControl
            pipView:                    _pipView
            carpcatcherSplitMode:       _pipView.splitMode

            // In a Carpcatcher combination, double tap makes the selected panel
            // the single active tab. Double tap again can be exited with tabs.
            onCarpcatcherDoubleClicked: {
                if (_carpcatcherViewMode === 3 || _carpcatcherViewMode === 5) {
                    _setViewMode(1)
                } else if (_carpcatcherViewMode === 1) {
                    _setViewMode(_carpcatcherLastComboMode)
                }
            }
        }

        PipView {
            id:                     _pipView
            anchors.left:           parent.left
            anchors.bottom:         parent.bottom
            anchors.margins:        _toolsMargin
            splitMode:              QGroundControl.videoManager.hasVideo
            splitFullItem:          0
            item1IsFullSettingsKey: "MainFlyWindowIsMap"
            item1:                  mapControl
            item2:                  QGroundControl.videoManager.hasVideo ? videoControl : null

            // In split mode the items are managed by PipView itself.
            // When a single map/camera mode is selected splitFullItem decides
            // which content owns this entire holder.
            show: QGroundControl.videoManager.hasVideo &&
                  (videoControl.pipState.state === videoControl.pipState.pipState ||
                   mapControl.pipState.state === mapControl.pipState.pipState)

            z: QGroundControl.zOrderWidgets

            property real leftEdgeBottomInset: visible ? width + anchors.margins : 0
            property real bottomEdgeLeftInset: visible ? height + anchors.margins : 0
        }

        FlyViewWidgetLayer {
            id:                     widgetLayer
            anchors.top:            parent.top
            anchors.bottom:         parent.bottom
            anchors.left:           parent.left
            anchors.right:          guidedValueSlider.visible ? guidedValueSlider.left : parent.right
            anchors.margins:        _widgetMargin
            z:                      _fullItemZorder + 2
            parentToolInsets:       _toolInsets
            mapControl:             _mapControl
            viewer3DCameraController: viewer3DLoader.item ? viewer3DLoader.item.cameraController : null
            visible: false
        }

        FlyViewCustomLayer {
            id:                 customOverlay
            anchors.fill:       widgetLayer
            z:                  _fullItemZorder + 2
            parentToolInsets:   widgetLayer.totalToolInsets
            mapControl:         _mapControl
            visible: false
        }

        FlyViewInsetViewer {
            id:                     widgetLayerInsetViewer
            anchors.top:            parent.top
            anchors.bottom:         parent.bottom
            anchors.left:           parent.left
            anchors.right:          guidedValueSlider.visible ? guidedValueSlider.left : parent.right
            z:                      widgetLayer.z + 1
            insetsToView:           widgetLayer.totalToolInsets
            visible:                false
        }

        GuidedActionsController {
            id:                 guidedActionsController
            missionController:  _missionController
            guidedValueSlider:  _guidedValueSlider
        }

        GuidedValueSlider {
            id:                 guidedValueSlider
            anchors.right:      parent.right
            anchors.top:        parent.top
            anchors.bottom:     parent.bottom
            anchors.topMargin:  0
            z:                  QGroundControl.zOrderTopMost
            visible:            false
        }

        Loader {
            id:           viewer3DLoader
            z:            1
            anchors.fill: parent
            visible:      _is3DMode
        }

        Connections {
            target: QGCViewer3DManager
            function onDisplayModeChanged() {
                if (QGCViewer3DManager.displayMode === QGCViewer3DManager.View3D) {
                    if (!viewer3DLoader.item) {
                        viewer3DLoader.setSource("qrc:/qml/QGroundControl/Viewer3D/Models3D/Viewer3DModel.qml")
                    }
                } else if (!_keepSceneAlive) {
                    viewer3DLoader.source = ""
                }
            }
        }
    }

    // ---------------------------------------------------------------------
    // CARPCATCHER SONAR — rolling echogram, ready for a Kogger data bridge
    // ---------------------------------------------------------------------
    Rectangle {
        id: sonarPanel
        x: (_carpcatcherViewMode === 4 || _carpcatcherViewMode === 5) ? parent.width * 0.45 : 0
        y: (_carpcatcherViewMode === 2 || _carpcatcherViewMode === 4 || _carpcatcherViewMode === 5)
             ? _carpcatcherContentTop
             : (_carpcatcherContentTop + (_carpcatcherContentHeight - _carpcatcherSonarHeight))
        width: (_carpcatcherViewMode === 4 || _carpcatcherViewMode === 5) ? parent.width * 0.55 : parent.width
        height: _carpcatcherSonarHeight
        visible: _carpcatcherShowSonar && height > 0
        z: QGroundControl.zOrderWidgets + 3
        color: "#03101d"
        border.color: "#27465d"
        border.width: 1
        clip: true

        property bool demoMode: true
        property bool paused: false
        property real currentDepth: 4.82
        property real waterTemperature: 16.8
        property int signalStrength: 92
        property int rangeMeters: 6
        property int gainValue: 70
        property bool filterEnabled: true
        property real phase: 0
        property int sequence: 0
        property var history: []
        property int historyLimit: 520

        // This is the single input for both demo and future Kogger samples.
        // targets is an array containing target depths in metres.
        function ingestSample(depth, temperature, signal, targets) {
            if (!isFinite(depth) || depth <= 0) return
            currentDepth = depth
            waterTemperature = isFinite(temperature) ? temperature : waterTemperature
            signalStrength = Math.max(0, Math.min(100, isFinite(signal) ? signal : signalStrength))
            _liveDepthMeters = currentDepth
            _liveWaterTemperature = waterTemperature

            var next = history.slice(0)
            next.push({
                depth: currentDepth,
                strength: signalStrength,
                targets: targets || [],
                sequence: sequence++
            })
            if (next.length > historyLimit)
                next.splice(0, next.length - historyLimit)
            history = next
            sonarCanvas.requestPaint()
        }

        function addDemoSample() {
            phase += 0.115
            var bottom = 4.15
                       + Math.sin(phase * 0.45) * 0.24
                       + Math.sin(phase * 0.13) * 0.16
            var trenchDistance = Math.abs((sequence % 260) - 150)
            if (trenchDistance < 34)
                bottom += (1.0 - trenchDistance / 34.0) * 0.55

            var targets = []
            var cycle = sequence % 210
            if (cycle >= 28 && cycle <= 42)
                targets.push(1.65 + Math.abs(cycle - 35) * 0.035)
            if (cycle >= 92 && cycle <= 104)
                targets.push(2.55 + Math.abs(cycle - 98) * 0.045)
            if (cycle >= 154 && cycle <= 172)
                targets.push(1.05 + Math.abs(cycle - 163) * 0.028)

            ingestSample(bottom, 16.8 + Math.sin(phase * 0.08) * 0.1,
                         90 + Math.round(Math.sin(phase * 0.31) * 4), targets)
        }

        function resetDemo() {
            history = []
            phase = 0
            sequence = 0
            for (var i = 0; i < 260; i++) addDemoSample()
        }

        Component.onCompleted: resetDemo()

        Timer {
            interval: 120
            repeat: true
            running: sonarPanel.visible && sonarPanel.demoMode && !sonarPanel.paused
            onTriggered: sonarPanel.addDemoSample()
        }

        Rectangle {
            id: sonarInfoBar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Math.max(32, parent.height * 0.13)
            color: "#e6071724"
            border.color: "#27465d"
            border.width: 1
            z: 3

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: Math.max(10, parent.width * 0.035)

                Text {
                    text: sonarPanel.currentDepth.toFixed(2) + " m"
                    color: "white"
                    font.bold: true
                    font.pixelSize: Math.max(14, sonarInfoBar.height * 0.46)
                }
                Text {
                    text: sonarPanel.waterTemperature.toFixed(1) + "°C"
                    color: "#bfe5ff"
                    font.pixelSize: Math.max(10, sonarInfoBar.height * 0.34)
                }
                Text {
                    text: "SIG " + sonarPanel.signalStrength + "%"
                    color: sonarPanel.signalStrength >= 65 ? "#7ee7a3" : "#ffb25c"
                    font.pixelSize: Math.max(10, sonarInfoBar.height * 0.34)
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: modeText.width + 16
                height: Math.max(21, sonarInfoBar.height * 0.62)
                radius: 4
                color: sonarPanel.demoMode ? "#253341" : "#183d2b"
                border.color: sonarPanel.demoMode ? "#ff8b28" : "#58d78a"
                Text {
                    id: modeText
                    anchors.centerIn: parent
                    text: sonarPanel.demoMode ? "SONAR DEMO" : "KOGGER LIVE"
                    color: sonarPanel.demoMode ? "#ffad66" : "#78efa5"
                    font.bold: true
                    font.pixelSize: Math.max(9, sonarInfoBar.height * 0.28)
                }
            }
        }

        Canvas {
            id: sonarCanvas
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: sonarInfoBar.bottom
            anchors.bottom: sonarControlBar.top
            antialiasing: true
            renderTarget: Canvas.Image
            renderStrategy: Canvas.Immediate

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var w = width, h = height
                if (w <= 1 || h <= 1) return

                var water = ctx.createLinearGradient(0, 0, 0, h)
                water.addColorStop(0.0, "#020915")
                water.addColorStop(0.42, "#062641")
                water.addColorStop(1.0, "#084f78")
                ctx.fillStyle = water
                ctx.fillRect(0, 0, w, h)

                var range = Math.max(1, sonarPanel.rangeMeters)
                ctx.lineWidth = 1
                ctx.font = Math.max(9, h * 0.058) + "px sans-serif"
                for (var metre = 1; metre <= range; metre++) {
                    var gy = metre / range * h
                    ctx.strokeStyle = metre % 2 === 0 ? "rgba(120,193,232,0.25)" : "rgba(120,193,232,0.13)"
                    ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(w, gy); ctx.stroke()
                    if (metre < range) {
                        ctx.fillStyle = "rgba(198,228,244,0.72)"
                        ctx.fillText(metre + "m", 6, Math.max(11, gy - 3))
                    }
                }

                var data = sonarPanel.history
                if (!data || data.length < 2) return
                var visibleCount = Math.min(data.length, Math.max(90, Math.floor(w / 2)))
                var first = data.length - visibleCount
                var stepX = w / Math.max(1, visibleCount - 1)
                function yForDepth(depth) { return Math.max(0, Math.min(h, depth / range * h)) }

                // Bottom fill: the newest echo is always at the right edge.
                ctx.beginPath()
                ctx.moveTo(0, h)
                for (var i = 0; i < visibleCount; i++) {
                    var sample = data[first + i]
                    var bx = i * stepX
                    var by = yForDepth(sample.depth)
                    if (i === 0) ctx.lineTo(bx, by); else ctx.lineTo(bx, by)
                }
                ctx.lineTo(w, h); ctx.closePath()
                var ground = ctx.createLinearGradient(0, h * 0.45, 0, h)
                ground.addColorStop(0.0, "#ffb13b")
                ground.addColorStop(0.10, "#d9661e")
                ground.addColorStop(0.38, "#71351d")
                ground.addColorStop(1.0, "#211713")
                ctx.fillStyle = ground; ctx.fill()

                // Layered return makes soft/hard bottom immediately readable.
                for (var pass = 0; pass < 3; pass++) {
                    ctx.beginPath()
                    for (var j = 0; j < visibleCount; j++) {
                        var lineSample = data[first + j]
                        var lx = j * stepX
                        var ly = yForDepth(lineSample.depth) + pass * 1.5
                        if (j === 0) ctx.moveTo(lx, ly); else ctx.lineTo(lx, ly)
                    }
                    ctx.strokeStyle = pass === 0 ? "#fff06a" : (pass === 1 ? "#ff9b24" : "rgba(255,74,24,0.70)")
                    ctx.lineWidth = pass === 0 ? Math.max(1.5, h * 0.009) : Math.max(1, h * 0.007)
                    ctx.stroke()
                }

                // Real fish targets arrive as depths. Consecutive returns form arches.
                var fishAlpha = 0.38 + sonarPanel.gainValue / 150.0
                for (var k = 0; k < visibleCount; k++) {
                    var echo = data[first + k]
                    if (!echo.targets) continue
                    for (var t = 0; t < echo.targets.length; t++) {
                        var fx = k * stepX
                        var fy = yForDepth(echo.targets[t])
                        var glow = Math.max(2, stepX * 1.7)
                        ctx.fillStyle = "rgba(255,220,55," + Math.min(0.95, fishAlpha) + ")"
                        ctx.fillRect(fx - glow * 0.5, fy - 1.5, glow, 3)
                        ctx.fillStyle = "rgba(255,91,24,0.80)"
                        ctx.fillRect(fx - Math.max(1, stepX * 0.3), fy - 1, Math.max(2, stepX * 0.6), 2)
                    }
                }

                if (!sonarPanel.filterEnabled) {
                    ctx.fillStyle = "rgba(110,208,255,0.20)"
                    for (var n = 0; n < 55; n++) {
                        var nx = (n * 67 + sonarPanel.sequence * 3) % Math.max(1, Math.floor(w))
                        var ny = (n * 43 + sonarPanel.sequence) % Math.max(1, Math.floor(h * 0.66))
                        ctx.fillRect(nx, ny, 2, 2)
                    }
                }

                // Right-hand live cursor.
                ctx.strokeStyle = "rgba(109,221,255,0.75)"
                ctx.lineWidth = 1
                ctx.beginPath(); ctx.moveTo(w - 1, 0); ctx.lineTo(w - 1, h); ctx.stroke()
            }
        }

        Rectangle {
            id: sonarControlBar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Math.max(32, parent.height * 0.14)
            color: "#08131d"
            border.color: "#27465d"
            border.width: 1
            z: 4

            RowLayout {
                anchors.fill: parent
                anchors.margins: 4
                spacing: 4

                Repeater {
                    model: [
                        { label: "RANGE", value: sonarPanel.rangeMeters + "m" },
                        { label: "GAIN", value: sonarPanel.gainValue },
                        { label: "FILTER", value: sonarPanel.filterEnabled ? "AAN" : "UIT" },
                        { label: sonarPanel.paused ? "START" : "PAUZE", value: "" }
                    ]
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 4
                        color: (index === 2 && sonarPanel.filterEnabled) ? "#123426" : "#142331"
                        border.color: (index === 2 && sonarPanel.filterEnabled) ? "#49c779" : "#38536a"
                        Text {
                            anchors.centerIn: parent
                            text: modelData.value === "" ? modelData.label : modelData.label + " " + modelData.value
                            color: "white"
                            font.bold: true
                            font.pixelSize: Math.max(8, parent.height * 0.27)
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (index === 0)
                                    sonarPanel.rangeMeters = sonarPanel.rangeMeters === 6 ? 10 : (sonarPanel.rangeMeters === 10 ? 20 : 6)
                                else if (index === 1)
                                    sonarPanel.gainValue = sonarPanel.gainValue === 70 ? 90 : (sonarPanel.gainValue === 90 ? 50 : 70)
                                else if (index === 2)
                                    sonarPanel.filterEnabled = !sonarPanel.filterEnabled
                                else
                                    sonarPanel.paused = !sonarPanel.paused
                                sonarCanvas.requestPaint()
                            }
                        }
                    }
                }
            }
        }
    }

    FlyViewToolBar {
        id:                 toolbar
        guidedValueSlider:  _guidedValueSlider
        visible:            true
    }

    Component.onCompleted: {
        _setViewMode(3)
    }
}
