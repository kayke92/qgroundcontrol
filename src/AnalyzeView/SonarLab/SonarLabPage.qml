import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QGroundControl
import QGroundControl.Controls

Item {
    id: root
    property real depth: 4.7
    property real temperature: 18.4
    property real minDepth: 99
    property real maxDepth: 0
    property int sampleIndex: 0
    property var samples: []

    function addSample() {
        var base = 4.7 + Math.sin(sampleIndex * 0.10) * 0.75
        var detail = Math.sin(sampleIndex * 0.31) * 0.18
        depth = Math.max(1.0, base + detail)
        temperature = 18.4 + Math.sin(sampleIndex * 0.025) * 0.6
        minDepth = Math.min(minDepth, depth)
        maxDepth = Math.max(maxDepth, depth)
        var a = samples.slice(0)
        a.push(depth)
        if (a.length > 180) a.shift()
        samples = a
        sampleIndex++
        sonarCanvas.requestPaint()
    }

    Timer { interval: 180; running: true; repeat: true; onTriggered: root.addSample() }
    Component.onCompleted: { for (var i = 0; i < 100; i++) addSample() }

    Rectangle {
        anchors.fill: parent
        color: "#101010"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                ColumnLayout {
                    Layout.fillWidth: true
                    Label { text: qsTr("SONAR LAB"); color: "#ff7a00"; font.pixelSize: 26; font.bold: true }
                    Label { text: qsTr("Carpcatcher Control • gesimuleerde sonardata"); color: "#bdbdbd"; font.pixelSize: 13 }
                }
                Rectangle {
                    implicitWidth: 116; implicitHeight: 34; radius: 17
                    color: "#2a1a0c"; border.color: "#ff7a00"
                    Label { anchors.centerIn: parent; text: qsTr("SIMULATIE"); color: "#ff7a00"; font.bold: true }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 105; radius: 8
                    color: "#191919"; border.color: "#343434"
                    Column {
                        anchors.centerIn: parent
                        Label { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("DIEPTE"); color: "#aaaaaa" }
                        Label { anchors.horizontalCenter: parent.horizontalCenter; text: root.depth.toFixed(1) + " m"; color: "white"; font.pixelSize: 38; font.bold: true }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 105; radius: 8
                    color: "#191919"; border.color: "#343434"
                    Column {
                        anchors.centerIn: parent
                        Label { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("WATERTEMP."); color: "#aaaaaa" }
                        Label { anchors.horizontalCenter: parent.horizontalCenter; text: root.temperature.toFixed(1) + " °C"; color: "white"; font.pixelSize: 26; font.bold: true }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 105; radius: 8
                    color: "#191919"; border.color: "#343434"
                    Column {
                        anchors.centerIn: parent
                        Label { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("BEREIK"); color: "#aaaaaa" }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: (root.minDepth < 90 ? root.minDepth.toFixed(1) : "-") + " – " + root.maxDepth.toFixed(1) + " m"
                            color: "white"; font.pixelSize: 21; font.bold: true
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 240
                radius: 8; color: "#070707"; border.color: "#343434"; clip: true
                Canvas {
                    id: sonarCanvas
                    anchors.fill: parent
                    anchors.margins: 10
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        ctx.fillStyle = "#070707"
                        ctx.fillRect(0, 0, width, height)
                        ctx.strokeStyle = "#292929"
                        ctx.lineWidth = 1
                        ctx.font = "12px sans-serif"
                        ctx.fillStyle = "#888888"
                        for (var g = 0; g <= 5; g++) {
                            var gy = (height - 20) * g / 5
                            ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(width, gy); ctx.stroke()
                            ctx.fillText((g * 2).toFixed(0) + " m", 5, Math.max(12, gy - 3))
                        }
                        if (root.samples.length < 2) return
                        var usableH = height - 20
                        var dx = width / Math.max(1, root.samples.length - 1)
                        ctx.beginPath()
                        for (var i = 0; i < root.samples.length; i++) {
                            var x = i * dx
                            var y = Math.min(usableH, root.samples[i] / 10.0 * usableH)
                            if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                        }
                        ctx.lineTo(width, height); ctx.lineTo(0, height); ctx.closePath()
                        ctx.fillStyle = "#402006"; ctx.fill()
                        ctx.beginPath()
                        for (var j = 0; j < root.samples.length; j++) {
                            var xx = j * dx
                            var yy = Math.min(usableH, root.samples[j] / 10.0 * usableH)
                            if (j === 0) ctx.moveTo(xx, yy); else ctx.lineTo(xx, yy)
                        }
                        ctx.strokeStyle = "#ff7a00"; ctx.lineWidth = 3; ctx.stroke()
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Label { text: qsTr("Signaal: TEST"); color: "#bdbdbd" }
                Item { Layout.fillWidth: true }
                Label { text: qsTr("Echte sonarinterface wordt later gekoppeld"); color: "#777777" }
            }
        }
    }
}
