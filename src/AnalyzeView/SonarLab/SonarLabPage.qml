import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    property real depth: 4.7
    property real temp: 18.4
    property real signal: 92
    property real phase: 0

    Rectangle {
        anchors.fill: parent
        color: "#080b0e"
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 5
        spacing: 4

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(38, Math.min(52, root.height * 0.14))
            radius: 3
            color: "#10161b"
            border.color: "#38434c"

            RowLayout {
                anchors.fill: parent
                anchors.margins: 4
                spacing: 4

                Repeater {
                    model: [
                        { t: "DIEPTE", value: root.depth.toFixed(1) + " m" },
                        { t: "TEMP", value: root.temp.toFixed(1) + " °C" },
                        { t: "SIGNAAL", value: Math.round(root.signal) + " %" }
                    ]

                    delegate: Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 2
                        color: "#171e24"
                        border.color: "#35404a"

                        Row {
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                text: modelData.t
                                color: "#9ca8b2"
                                font.bold: true
                                font.pixelSize: Math.max(8, Math.min(11, root.height * 0.023))
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: modelData.value
                                color: "white"
                                font.bold: true
                                font.pixelSize: Math.max(14, Math.min(20, root.height * 0.041))
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.preferredWidth: Math.max(76, root.width * 0.105)
                    Layout.fillHeight: true
                    radius: 2
                    color: "#251408"
                    border.color: "#ff7a00"

                    Text {
                        anchors.centerIn: parent
                        text: "SIMULATIE"
                        color: "#ff7a00"
                        font.bold: true
                        font.pixelSize: Math.max(8, Math.min(11, root.height * 0.022))
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 3
            color: "#030609"
            border.color: "#303942"
            clip: true

            Canvas {
                id: canvas
                anchors.fill: parent
                anchors.rightMargin: 42
                anchors.margins: 4

                onPaint: {
                    var c = getContext("2d")
                    c.clearRect(0, 0, width, height)

                    c.strokeStyle = "#17232d"
                    c.lineWidth = 1
                    for (var i = 0; i <= 5; i++) {
                        var y = i * height / 5
                        c.beginPath()
                        c.moveTo(0, y)
                        c.lineTo(width, y)
                        c.stroke()
                    }

                    var fx = [0.18, 0.35, 0.58, 0.77]
                    var fy = [0.31, 0.43, 0.27, 0.48]
                    for (var f = 0; f < 4; f++) {
                        c.strokeStyle = f === 2 ? "#ffd23f" : "#ff8a00"
                        c.lineWidth = 3
                        c.beginPath()
                        c.arc(width * fx[f], height * fy[f], 8 + f * 2, Math.PI, Math.PI * 2)
                        c.stroke()
                    }

                    var pts = []
                    for (var x = 0; x <= width; x += 4) {
                        var by = height * (
                            0.73 +
                            0.055 * Math.sin((x + root.phase * 8) / 92) +
                            0.022 * Math.sin(x / 29)
                        )
                        pts.push([x, by])
                    }

                    var g = c.createLinearGradient(0, height * 0.60, 0, height)
                    g.addColorStop(0, "#ffd23f")
                    g.addColorStop(0.08, "#ff8a00")
                    g.addColorStop(0.25, "#d84a00")
                    g.addColorStop(1, "#351008")

                    c.fillStyle = g
                    c.beginPath()
                    c.moveTo(0, height)
                    for (var p = 0; p < pts.length; p++)
                        c.lineTo(pts[p][0], pts[p][1])
                    c.lineTo(width, height)
                    c.closePath()
                    c.fill()

                    c.strokeStyle = "#ffe15a"
                    c.lineWidth = 2
                    c.beginPath()
                    for (var q = 0; q < pts.length; q++) {
                        if (q === 0)
                            c.moveTo(pts[q][0], pts[q][1])
                        else
                            c.lineTo(pts[q][0], pts[q][1])
                    }
                    c.stroke()
                }
            }

            Column {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: 5
                width: 34

                Repeater {
                    model: ["0", "2", "4", "6", "8", "10m"]

                    delegate: Text {
                        width: 34
                        height: parent.height / 6
                        text: modelData
                        color: "#aeb7c0"
                        horizontalAlignment: Text.AlignRight
                        font.pixelSize: Math.max(8, Math.min(11, root.height * 0.021))
                    }
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: 7
                width: sonarTitle.implicitWidth + 12
                height: sonarTitle.implicitHeight + 7
                radius: 2
                color: "#bb11171d"

                Text {
                    id: sonarTitle
                    anchors.centerIn: parent
                    text: "CARPCATCHER SONAR"
                    color: "#ff7a00"
                    font.bold: true
                    font.pixelSize: Math.max(9, Math.min(13, root.height * 0.025))
                }
            }
        }
    }

    Timer {
        interval: 160
        repeat: true
        running: true

        onTriggered: {
            root.phase += 0.16
            root.depth = 4.7 + 0.12 * Math.sin(root.phase / 2.2)
            root.temp = 18.4 + 0.05 * Math.sin(root.phase / 6)
            root.signal = 92 + 3 * Math.sin(root.phase / 3.5)
            canvas.requestPaint()
        }
    }
}
