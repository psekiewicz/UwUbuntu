/* Slideshow shown while UwUbuntu installs. */
import QtQuick 2.0
import calamares.slideshow 1.0

Presentation {
    id: presentation

    Timer {
        interval: 7000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    component PawSlide: Slide {
        property string heading
        property string body

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#2b1610" }
                GradientStop { position: 1.0; color: "#5a2a12" }
            }
        }
        Image {
            id: paw
            source: "paw.png"
            width: 72; height: 72
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: parent.height * 0.18
        }
        Text {
            id: title
            text: heading
            color: "#ffffff"
            font.pixelSize: 30
            font.bold: true
            anchors.top: paw.bottom
            anchors.topMargin: 24
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Text {
            text: body
            color: "#f1d9cc"
            font.pixelSize: 17
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            width: parent.width * 0.7
            anchors.top: title.bottom
            anchors.topMargin: 16
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    PawSlide {
        heading: "Welcome home, pawtner! (=^·ω·^=)"
        body: "UwUbuntu is Ubuntu 26.04 LTS with extra fluff: same rock-solid base, five years of updates, way more pawprints."
    }
    PawSlide {
        heading: "Apps for every critter"
        body: "GNOME Software comes with Flathub built in, so Krita, Inkscape, Blender, Discord, Telegram and thousands more are a click away."
    }
    PawSlide {
        heading: "Terminal toys"
        body: "Open a terminal and try uwufetch, or pipe anything through uwuify:  echo hello world | uwuify"
    }
    PawSlide {
        heading: "Make it yours"
        body: "Pick an accent colour in Settings → Appearance, swap wallpapers, and tweak everything else with GNOME Tweaks and Extension Manager."
    }

    function onActivate() { presentation.currentSlide = 0; }
    function onLeave() { }
}
