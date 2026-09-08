import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    anchors.fill: parent
    property real depth: 4.7
    property real waterTemp: 18.4
    property real signalQuality: 92
    property real phase: 0

    Rectangle { anchors.fill: parent; color: "#0b0f13" }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(58, root.height * 0.13)

            ColumnLayout {
                Layout.fillWidth: true
                Text {
                    text: "CARPCATCHER SONAR"
                    color: "#ff7a00"
                    font.bold: true
                    font.pixelSize: Math.max(22, root.height * 0.045)
                }
                Text {
                    text: "Carpcatcher Control • simulatie"
                    color: "#9aa5af"
                    font.pixelSize: Math.max(12, root.height * 0.02)
                }
            }

            Rectangle {
                Layout.preferredWidth: Math.max(110, root.width * 0.16)
                Layout.preferredHeight: Math.max(36, root.height * 0.06)
                radius: height / 2
                color: "#24140a"
                border.color: "#ff7a00"
                Text {
                    anchors.centerIn: parent
                    text: "SIMULATIE"
                    color: "#ff7a00"
                    font.bold: true
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(76, root.height * 0.18)
            spacing: 10

            Repeater {
                model: [
                    {label:"DIEPTE", value: root.depth.toFixed(1) + " m"},
                    {label:"WATERTEMP.", value: root.waterTemp.toFixed(1) + " °C"},
                    {label:"SIGNAAL", value: Math.round(root.signalQuality) + " %"}
                ]
                delegate: Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 8
                    color: "#141a20"
                    border.color: "#2a323a"
                    Column {
                        anchors.centerIn: parent
                        spacing: 3
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.label
                            color: "#8e99a4"
                            font.pixelSize: Math.max(11, root.height * 0.02)
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.value
                            color: "white"
                            font.bold: true
                            font.pixelSize: Math.max(24, root.height * 0.05)
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 8
            color: "#05080b"
            border.color: "#2a323a"
            clip: true

            Canvas {
                id: sonarCanvas
                anchors.fill: parent
                anchors.margins: 8

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)

                    ctx.strokeStyle = "#1f2b35"
                    ctx.lineWidth = 1
                    for (var i = 0; i <= 5; i++) {
                        var gy = i * height / 5
                        ctx.beginPath()
                        ctx.moveTo(0, gy)
                        ctx.lineTo(width, gy)
                        ctx.stroke()
                    }

                    for (var x = 0; x < width; x += 7) {
                        var y = height * (0.46 + 0.03 * Math.sin((x + root.phase * 20) / 35))
                        ctx.fillStyle = "#155181"
                        ctx.fillRect(x, y - 24, 2, 2)
                    }

                    var fx = [width*0.23, width*0.49, width*0.72]
                    var fy = [height*0.40, height*0.31, height*0.47]
                    for (var f = 0; f < fx.length; f++) {
                        ctx.strokeStyle = "#ffb000"
                        ctx.lineWidth = 3
                        ctx.beginPath()
                        ctx.arc(fx[f], fy[f], 10 + f*2, Math.PI, Math.PI*2)
                        ctx.stroke()
                    }

                    var pts = []
                    for (var bx = 0; bx <= width; bx += 5) {
                        var by = height * (0.70 + 0.06*Math.sin((bx + root.phase*10)/85) + 0.025*Math.sin(bx/29))
                        pts.push([bx, by])
                    }

                    var grad = ctx.createLinearGradient(0, height*0.55, 0, height)
                    grad.addColorStop(0, "#ff7a00")
                    grad.addColorStop(0.35, "#d93b00")
                    grad.addColorStop(1, "#471000")
                    ctx.fillStyle = grad
                    ctx.beginPath()
                    ctx.moveTo(0, height)
                    for (var p = 0; p < pts.length; p++) ctx.lineTo(pts[p][0], pts[p][1])
                    ctx.lineTo(width, height)
                    ctx.closePath()
                    ctx.fill()

                    ctx.strokeStyle = "#ffd23f"
                    ctx.lineWidth = 2
                    ctx.beginPath()
                    for (var q = 0; q < pts.length; q++) {
                        if (q === 0) ctx.moveTo(pts[q][0], pts[q][1])
                        else ctx.lineTo(pts[q][0], pts[q][1])
                    }
                    ctx.stroke()
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: "Echte Kogger-data wordt later hier gekoppeld."
            color: "#73808b"
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Math.max(11, root.height * 0.018)
        }
    }

    Timer {
        interval: 180
        repeat: true
        running: true
        onTriggered: {
            root.phase += 0.18
            root.depth = 4.7 + 0.12 * Math.sin(root.phase / 2.2)
            root.waterTemp = 18.4 + 0.05 * Math.sin(root.phase / 6)
            root.signalQuality = 92 + 3 * Math.sin(root.phase / 3.5)
            sonarCanvas.requestPaint()
        }
    }
}

