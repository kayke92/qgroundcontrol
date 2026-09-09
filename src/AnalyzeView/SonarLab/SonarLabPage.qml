import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.Palette

Item {
    id: root
    anchors.fill: parent

    // Voorlopige simulatie totdat de echte Kogger-data binnenkomt.
    property real depthM: 4.82
    property real temperatureC: 16.8
    property int signalPercent: 92
    property real maxDepthM: 6.0
    property real phase: 0

    Rectangle {
        anchors.fill: parent
        color: "#05080c"
    }

    // Groot echogram: vrijwel alle beschikbare ruimte.
    Canvas {
        id: sonarCanvas
        anchors.fill: parent
        anchors.bottomMargin: bottomBar.height

        onPaint: {
            var ctx = getContext("2d")
            var w = width
            var h = height
            ctx.reset()

            // Donkere achtergrond
            ctx.fillStyle = "#05080c"
            ctx.fillRect(0, 0, w, h)

            // Subtiele horizontale dieptelijnen
            ctx.lineWidth = 1
            for (var d = 1; d < Math.ceil(root.maxDepthM); d++) {
                var y = (d / root.maxDepthM) * h
                ctx.strokeStyle = "rgba(255,255,255,0.08)"
                ctx.beginPath()
                ctx.moveTo(0, y)
                ctx.lineTo(w, y)
                ctx.stroke()
            }

            // Ruwe sonar-textuur / waterkolom
            for (var x = 0; x < w; x += 7) {
                var n1 = Math.sin((x + root.phase * 55) * 0.045)
                var n2 = Math.sin((x + root.phase * 23) * 0.11)
                var bottomDepth = 4.15 + 0.38 * n1 + 0.16 * n2

                // Klein kuiltje / geul in bodem
                var cx = w * 0.63
                var sigma = w * 0.10
                var dip = 0.62 * Math.exp(-Math.pow(x - cx, 2) / (2 * sigma * sigma))
                bottomDepth += dip

                var by = Math.min(h - 4, (bottomDepth / root.maxDepthM) * h)

                // Waterkolom stipjes
                for (var y2 = 16; y2 < by - 10; y2 += 14) {
                    var v = Math.sin((x * 0.07) + (y2 * 0.12) + root.phase * 1.8)
                    if (v > 0.75) {
                        ctx.fillStyle = "rgba(85,140,180,0.16)"
                        ctx.fillRect(x, y2, 2, 2)
                    }
                }

                // Bodemvulling
                var grad = ctx.createLinearGradient(0, by, 0, h)
                grad.addColorStop(0, "rgba(85,55,20,0.85)")
                grad.addColorStop(1, "rgba(15,10,5,0.95)")
                ctx.fillStyle = grad
                ctx.fillRect(x, by, 7, h - by)
            }

            // Visbogen / targets, klein en niet overdreven
            function fishArc(cx, cy, rx, ry, alpha) {
                ctx.strokeStyle = "rgba(255,170,55," + alpha + ")"
                ctx.lineWidth = 2
                ctx.beginPath()
                ctx.arc(cx, cy, rx, Math.PI, Math.PI * 2, false)
                ctx.stroke()
            }
            fishArc(w * 0.28, h * 0.34, 12, 6, 0.75)
            fishArc(w * 0.49, h * 0.45, 17, 8, 0.58)
            fishArc(w * 0.78, h * 0.29, 10, 5, 0.65)

            // Blauwe gedetecteerde bodemlijn
            ctx.strokeStyle = "#27a9ff"
            ctx.lineWidth = 3
            ctx.beginPath()
            for (var xx = 0; xx <= w; xx += 4) {
                var a = Math.sin((xx + root.phase * 55) * 0.045)
                var b = Math.sin((xx + root.phase * 23) * 0.11)
                var dep = 4.15 + 0.38 * a + 0.16 * b
                var cc = w * 0.63
                var ss = w * 0.10
                dep += 0.62 * Math.exp(-Math.pow(xx - cc, 2) / (2 * ss * ss))
                var yy = Math.min(h - 4, (dep / root.maxDepthM) * h)
                if (xx === 0) ctx.moveTo(xx, yy)
                else ctx.lineTo(xx, yy)
            }
            ctx.stroke()
        }
    }

    // Informatie compact als overlay, niet meer in grote kaarten.
    Rectangle {
        id: infoStrip
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 42
        color: "#B8000000"
        z: 10

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 12

            Label {
                text: root.depthM.toFixed(2) + " m"
                color: "white"
                font.pixelSize: 22
                font.bold: true
                Layout.alignment: Qt.AlignVCenter
            }

            Label {
                text: root.temperatureC.toFixed(1) + "°C"
                color: "#e7e7e7"
                font.pixelSize: 14
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            Label {
                text: "SIG " + root.signalPercent + "%"
                color: root.signalPercent >= 70 ? "#d7f8d7" : "#ffd27a"
                font.pixelSize: 13
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }

    // Diepteschaal rechts in beeld.
    Item {
        id: depthScale
        anchors.top: infoStrip.bottom
        anchors.bottom: bottomBar.top
        anchors.right: parent.right
        width: 44
        z: 11

        Repeater {
            model: Math.floor(root.maxDepthM) + 1
            delegate: Label {
                required property int index
                x: 2
                y: (index / root.maxDepthM) * (depthScale.height - 18)
                text: index + "m"
                color: "#d8dde3"
                font.pixelSize: 11
            }
        }
    }

    Rectangle {
        id: bottomBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 42
        color: "#D20B0F14"
        border.color: "#282f37"
        border.width: 1
        z: 20

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 5

            Button {
                text: "RANGE " + root.maxDepthM.toFixed(0) + "m"
                font.pixelSize: 11
                onClicked: {
                    if (root.maxDepthM < 10) root.maxDepthM += 2
                    else root.maxDepthM = 4
                    sonarCanvas.requestPaint()
                }
            }

            Button {
                text: "GAIN"
                font.pixelSize: 11
            }

            Button {
                text: "FILTER"
                font.pixelSize: 11
            }

            Item { Layout.fillWidth: true }

            Label {
                text: "KOGGER"
                color: "#ff8c24"
                font.pixelSize: 11
                font.bold: true
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }

    Timer {
        interval: 90
        running: true
        repeat: true
        onTriggered: {
            root.phase += 0.025
            sonarCanvas.requestPaint()
        }
    }
}
