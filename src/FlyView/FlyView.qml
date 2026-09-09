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
    readonly property real _carpcatcherSonarHeight: _carpcatcherViewMode === 2
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
        width: parent.width
        height: _carpcatcherShowMapArea
                  ? Math.max(0, _carpcatcherContentHeight - _carpcatcherSonarHeight)
                  : 0
        visible: _carpcatcherShowMapArea && height > 0
        clip: true

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
    // CARPCATCHER SONAR — self-contained simulator until Kogger is connected
    // ---------------------------------------------------------------------
    Rectangle {
        id: sonarPanel
        x: 0
        y: _carpcatcherViewMode === 2
             ? _carpcatcherContentTop
             : (_carpcatcherContentTop + (_carpcatcherContentHeight - _carpcatcherSonarHeight))
        width: parent.width
        height: _carpcatcherSonarHeight
        visible: _carpcatcherShowSonar && height > 0
        z: QGroundControl.zOrderWidgets + 3
        color: "#070b0f"
        border.color: "#2a323a"
        border.width: 1
        clip: true

        property real simulatedDepth: 4.82
        property real simulatedTemperature: 16.8
        property int simulatedSignal: 92
        property int rangeMeters: 6
        property int gainValue: 70
        property bool filterEnabled: true
        property real phase: 0

        Timer {
            interval: 160
            repeat: true
            running: sonarPanel.visible
            onTriggered: {
                sonarPanel.phase += 0.06
                sonarPanel.simulatedDepth = 4.75 + Math.sin(sonarPanel.phase * 0.55) * 0.07
                sonarCanvas.requestPaint()
            }
        }

        // Top information overlay
        Rectangle {
            id: sonarInfoBar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Math.max(30, parent.height * 0.12)
            color: "#d910151b"
            z: 3

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: Math.max(12, parent.width * 0.04)

                Text {
                    text: sonarPanel.simulatedDepth.toFixed(2) + " m"
                    color: "white"
                    font.bold: true
                    font.pixelSize: Math.max(14, sonarInfoBar.height * 0.48)
                }
                Text {
                    text: sonarPanel.simulatedTemperature.toFixed(1) + "°C"
                    color: "#d7e2eb"
                    font.pixelSize: Math.max(11, sonarInfoBar.height * 0.38)
                }
                Text {
                    text: "SIG " + sonarPanel.simulatedSignal + "%"
                    color: "#d7e2eb"
                    font.pixelSize: Math.max(11, sonarInfoBar.height * 0.38)
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: simText.width + 12
                height: Math.max(20, sonarInfoBar.height * 0.62)
                radius: 4
                color: "#222b35"
                border.color: "#ff7a00"

                Text {
                    id: simText
                    anchors.centerIn: parent
                    text: "SIM"
                    color: "#ff9b42"
                    font.bold: true
                    font.pixelSize: Math.max(9, sonarInfoBar.height * 0.30)
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

            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()

                var w = width
                var h = height
                if (w <= 1 || h <= 1) return

                // Dark echogram background
                var grd = ctx.createLinearGradient(0, 0, 0, h)
                grd.addColorStop(0.0, "#081018")
                grd.addColorStop(0.55, "#0a1520")
                grd.addColorStop(1.0, "#0c1117")
                ctx.fillStyle = grd
                ctx.fillRect(0, 0, w, h)

                // Horizontal depth grid
                ctx.lineWidth = 1
                ctx.strokeStyle = "#26323d"
                ctx.fillStyle = "#8fa0ad"
                ctx.font = Math.max(9, h * 0.07) + "px sans-serif"

                var r = Math.max(1, sonarPanel.rangeMeters)
                for (var m = 1; m <= r; m++) {
                    var gy = (m / r) * h
                    ctx.beginPath()
                    ctx.moveTo(0, gy)
                    ctx.lineTo(w, gy)
                    ctx.stroke()
                    if (m < r) {
                        ctx.fillText(m + "m", w - 30, Math.max(10, gy - 3))
                    }
                }

                // A changing bottom profile with a clearly visible trench.
                function depthAt(nx) {
                    var base = 0.69
                    var wave = Math.sin(nx * 10.0 + sonarPanel.phase * 0.35) * 0.018
                    var trench = 0
                    var center = 0.60
                    var d = Math.abs(nx - center)
                    if (d < 0.16) {
                        trench = (1.0 - d / 0.16) * 0.12
                    }
                    var rise = nx > 0.80 ? -(nx - 0.80) * 0.20 : 0
                    return Math.min(0.91, Math.max(0.45, base + wave + trench + rise))
                }

                // Soft return / bottom body
                ctx.beginPath()
                ctx.moveTo(0, h)
                for (var x = 0; x <= w; x += 3) {
                    var nx = x / w
                    var by = depthAt(nx) * h
                    ctx.lineTo(x, by)
                }
                ctx.lineTo(w, h)
                ctx.closePath()

                var bottomGradient = ctx.createLinearGradient(0, h * 0.52, 0, h)
                bottomGradient.addColorStop(0.0, "#7a3515")
                bottomGradient.addColorStop(0.45, "#4b2a1c")
                bottomGradient.addColorStop(1.0, "#1d1715")
                ctx.fillStyle = bottomGradient
                ctx.fill()

                // Strong blue detected bottom line
                ctx.beginPath()
                for (var bx = 0; bx <= w; bx += 2) {
                    var bnx = bx / w
                    var bly = depthAt(bnx) * h
                    if (bx === 0) ctx.moveTo(bx, bly)
                    else ctx.lineTo(bx, bly)
                }
                ctx.strokeStyle = "#21a9ff"
                ctx.lineWidth = Math.max(2, h * 0.012)
                ctx.stroke()

                // Fish/target arches
                function drawArch(cx, cy, rx, ry, alpha) {
                    ctx.beginPath()
                    ctx.arc(cx, cy, rx, Math.PI * 1.08, Math.PI * 1.92, false)
                    ctx.strokeStyle = "rgba(255,122,0," + alpha + ")"
                    ctx.lineWidth = Math.max(1.5, h * 0.009)
                    ctx.stroke()
                }

                drawArch(w * 0.18, h * 0.36, w * 0.025, h * 0.07, 0.86)
                drawArch(w * 0.39, h * 0.47, w * 0.018, h * 0.05, 0.72)
                drawArch(w * 0.76, h * 0.31, w * 0.028, h * 0.075, 0.90)

                // Some faint suspended returns
                ctx.fillStyle = "rgba(255,180,70,0.18)"
                for (var p = 0; p < 18; p++) {
                    var px = ((p * 71 + Math.floor(sonarPanel.phase * 9)) % 997) / 997 * w
                    var py = (0.15 + ((p * 37) % 43) / 100) * h
                    ctx.fillRect(px, py, 2, 2)
                }
            }
        }

        Rectangle {
            id: sonarControlBar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Math.max(30, parent.height * 0.13)
            color: "#10151b"
            border.color: "#2a323a"
            border.width: 1
            z: 4

            RowLayout {
                anchors.fill: parent
                anchors.margins: 4
                spacing: 4

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 4
                    color: "#1b232c"
                    border.color: "#3b4651"
                    Text {
                        anchors.centerIn: parent
                        text: "RANGE " + sonarPanel.rangeMeters + "m"
                        color: "white"
                        font.bold: true
                        font.pixelSize: Math.max(9, parent.height * 0.32)
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            sonarPanel.rangeMeters = sonarPanel.rangeMeters === 6 ? 10 :
                                                     (sonarPanel.rangeMeters === 10 ? 20 : 6)
                            sonarCanvas.requestPaint()
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 4
                    color: "#1b232c"
                    border.color: "#3b4651"
                    Text {
                        anchors.centerIn: parent
                        text: "GAIN " + sonarPanel.gainValue
                        color: "white"
                        font.bold: true
                        font.pixelSize: Math.max(9, parent.height * 0.32)
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            sonarPanel.gainValue = sonarPanel.gainValue === 70 ? 90 :
                                                   (sonarPanel.gainValue === 90 ? 50 : 70)
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 4
                    color: sonarPanel.filterEnabled ? "#173224" : "#1b232c"
                    border.color: sonarPanel.filterEnabled ? "#49b86e" : "#3b4651"
                    Text {
                        anchors.centerIn: parent
                        text: sonarPanel.filterEnabled ? "FILTER AAN" : "FILTER UIT"
                        color: "white"
                        font.bold: true
                        font.pixelSize: Math.max(9, parent.height * 0.32)
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: sonarPanel.filterEnabled = !sonarPanel.filterEnabled
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

