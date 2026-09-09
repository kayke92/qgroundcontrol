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
    property bool   _carpcatcherSonarFullScreen: false

    function _calcCenterViewPort() {
        var newToolInset = Qt.rect(0, 0, width, height)
        toolstrip.adjustToolInset(newToolInset)
    }

    function dropMainStatusIndicatorTool() {
        toolbar.dropMainStatusIndicatorTool();
    }

    QGCToolInsets {
        id:                     _toolInsets
        topEdgeLeftInset:       toolbar.height
        topEdgeCenterInset:     topEdgeLeftInset
        topEdgeRightInset:      topEdgeLeftInset
        leftEdgeBottomInset:    _pipView.leftEdgeBottomInset
        bottomEdgeLeftInset:    _pipView.bottomEdgeLeftInset
    }

    Item {
    readonly property bool _carpcatcherMapFullScreen: _pipView.splitMode && _pipView.splitFullItem === 1
    readonly property bool _carpcatcherCameraFullScreen: _pipView.splitMode && _pipView.splitFullItem === 2
        id:                 mapHolder
        anchors.left:       parent.left
        anchors.right:      parent.right
        anchors.top:        parent.top
        anchors.bottom: (_carpcatcherMapFullScreen || _carpcatcherCameraFullScreen) ? parent.bottom : sonarPanel.top
        visible:            !_carpcatcherSonarFullScreen

        FlyViewMap {
            id:                     mapControl

        TapHandler {
            id: carpcatcherMapDoubleTap
            acceptedButtons: Qt.LeftButton
            gesturePolicy: TapHandler.DragThreshold
            onDoubleTapped: {
                if (_carpcatcherSonarFullScreen) _carpcatcherSonarFullScreen = false
                _pipView.toggleSplitItem(mapControl)
            }
        }
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
            onCarpcatcherDoubleClicked: {
            if (_carpcatcherSonarFullScreen) _carpcatcherSonarFullScreen = false
            _pipView.toggleSplitItem(videoControl)
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
            show:                   QGroundControl.videoManager.hasVideo && !QGroundControl.videoManager.fullScreen &&
                                        (videoControl.pipState.state === videoControl.pipState.pipState || mapControl.pipState.state === mapControl.pipState.pipState)
            z:                      QGroundControl.zOrderWidgets

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
            anchors.topMargin:      toolbar.height + _widgetMargin
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

        // Development tool for visualizing the insets for a paticular layer, show if needed
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
            guidedValueSlider:     _guidedValueSlider
        }

        //-- Guided value slider (e.g. altitude)
        GuidedValueSlider {
            id:                 guidedValueSlider
            anchors.right:      parent.right
            anchors.top:        parent.top
            anchors.bottom:     parent.bottom
            anchors.topMargin:  toolbar.height
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


    Rectangle {
        id:                 sonarPanel
        anchors.left:       parent.left
        anchors.right:      parent.right
        anchors.bottom:     parent.bottom
        height:             _carpcatcherSonarFullScreen ? parent.height : parent.height * 0.38
        z:                  _carpcatcherSonarFullScreen ? QGroundControl.zOrderTopMost : (_fullItemZorder + 1)
        visible: _carpcatcherSonarFullScreen || (!_carpcatcherMapFullScreen && !_carpcatcherCameraFullScreen)
        color:              "#0b0f13"
        border.color:       "#2a323a"
        border.width:       1

        Loader {
            id:             carpcatcherSonarLoader
            anchors.fill:   parent
            source:         "qrc:/qml/QGroundControl/AnalyzeView/SonarLab/SonarLabPage.qml"
        }

        Rectangle {
            anchors.right:      parent.right
            anchors.top:        parent.top
            anchors.margins:    8
            width:              42
            height:             34
            radius:             6
            color:              "#cc11171d"
            border.color:       "#ff7a00"
            z:                  20

            Text {
                anchors.centerIn: parent
                text: _carpcatcherSonarFullScreen ? "↙" : "↗"
                color: "white"
                font.bold: true
                font.pixelSize: 20
            }

            MouseArea {
                anchors.fill: parent
                onClicked: _carpcatcherSonarFullScreen = !_carpcatcherSonarFullScreen
            }
        }
    }

    FlyViewToolBar {
        id:                 toolbar
        guidedValueSlider:  _guidedValueSlider
        visible: !QGroundControl.videoManager.fullScreen && !_carpcatcherSonarFullScreen
    }
}
