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

    ListModel {
        id: bathymetrySamples
    }
    ListModel { id: bathymetryHeatCells }
    property real _heatCellMeters: 3.0
    property real _heatRadiusMeters: 12.0

    function _heatLonScale(lat) {
        return 111320.0 * Math.max(0.15, Math.cos(lat * Math.PI / 180.0))
    }
    function _heatDistance(lat1, lon1, lat2, lon2) {
        var dy=(lat2-lat1)*111320.0
        var dx=(lon2-lon1)*_heatLonScale((lat1+lat2)*0.5)
        return Math.sqrt(dx*dx+dy*dy)
    }
    function _rebuildHeatmap() {
        bathymetryHeatCells.clear()
        if (bathymetrySamples.count < 2) return
        var minLat=90, maxLat=-90, minLon=180, maxLon=-180, meanLat=0
        for (var i=0;i<bathymetrySamples.count;i++) {
            var q=bathymetrySamples.get(i)
            minLat=Math.min(minLat,q.latitude); maxLat=Math.max(maxLat,q.latitude)
            minLon=Math.min(minLon,q.longitude); maxLon=Math.max(maxLon,q.longitude)
            meanLat+=q.latitude
        }
        meanLat/=bathymetrySamples.count
        var dLat=_heatCellMeters/111320.0
        var dLon=_heatCellMeters/_heatLonScale(meanLat)
        var rows=Math.max(1,Math.ceil((maxLat-minLat)/dLat)+1)
        var cols=Math.max(1,Math.ceil((maxLon-minLon)/dLon)+1)
        var scale=Math.max(1.0,Math.sqrt((rows*cols)/900.0))
        dLat*=scale; dLon*=scale
        rows=Math.max(1,Math.ceil((maxLat-minLat)/dLat)+1)
        cols=Math.max(1,Math.ceil((maxLon-minLon)/dLon)+1)
        for (var r=0;r<rows;r++) for (var c=0;c<cols;c++) {
            var lat=minLat+r*dLat, lon=minLon+c*dLon
            var sum=0, weights=0, nearby=0, nearest=999999
            for (var j=0;j<bathymetrySamples.count;j++) {
                var x=bathymetrySamples.get(j)
                var d=_heatDistance(lat,lon,x.latitude,x.longitude)
                nearest=Math.min(nearest,d)
                if (d<=_heatRadiusMeters) {
                    var w=1.0/Math.max(1.0,d*d)
                    sum+=x.depth*w; weights+=w; nearby++
                }
            }
            if (nearby>=1 && nearest<=_heatRadiusMeters && weights>0)
                bathymetryHeatCells.append({"latitude":lat,"longitude":lon,"depth":sum/weights,"latStep":dLat,"lonStep":dLon})
        }
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
        if (bathymetrySamples.count >= 2 && (bathymetrySamples.count % 3) === 0) {
            _rebuildHeatmap()
        }
    }

    function _clearBathymetry() {
        _demoTrackInitialized = false
        _demoLatitude = 0.0
        _demoLongitude = 0.0
        _demoHeadingDeg = 70.0
        _demoTrackStep = 0
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

            Row {
                anchors.centerIn: parent
                spacing: 3
                Repeater {
                    model: [
                        {t:"<1", c:"#e53935"},
                        {t:"1-2", c:"#fb8c00"},
                        {t:"2-3", c:"#fdd835"},
                        {t:"3-4", c:"#43a047"},
                        {t:"4-5", c:"#29b6f6"},
                        {t:"5+", c:"#1565c0"}
                    ]

                    delegate: Row {
                        spacing: 1
                        Rectangle {
                            width: 8
                            height: 8
                            radius: 4
                            anchors.verticalCenter: parent.verticalCenter
                            color: modelData.c
                        }
                        Text {
                            text: modelData.t
                            color: "white"
                            font.pixelSize: 7
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

            // LIVECHART meetpunten: echte kaartobjecten met GPS-coördinaten.
            // Daardoor blijven ze op dezelfde geografische plek bij pan/zoom.
            MapItemView {
                id: bathymetryHeatmapItems
                model: bathymetryHeatCells
                delegate: MapPolygon {
                    border.width: 0
                    opacity: 0.58
                    color: _depthColor(model.depth)
                    path: [
                        QtPositioning.coordinate(model.latitude-model.latStep*0.55, model.longitude-model.lonStep*0.55),
                        QtPositioning.coordinate(model.latitude-model.latStep*0.55, model.longitude+model.lonStep*0.55),
                        QtPositioning.coordinate(model.latitude+model.latStep*0.55, model.longitude+model.lonStep*0.55),
                        QtPositioning.coordinate(model.latitude+model.latStep*0.55, model.longitude-model.lonStep*0.55)
                    ]
                }
            }

            MapItemView {
                id: bathymetryMapItems
                model: bathymetrySamples

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
                        text: "HEAT " + bathymetryHeatCells.count
                        color: bathymetryHeatCells.count > 0 ? "#54d17a" : "#ff5252"
                        font.bold: true
                        font.pixelSize: 11
                    }

                    Text {
                        text: _bathymetryRecording ? "OPNAME AAN" : "OPNAME UIT"
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
    // CARPCATCHER SONAR — self-contained simulator until Kogger is connected
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
