pragma ComponentBehavior: Bound

// caelestia-overlay: Nexus's Display page (its own is still to come), AgrOS's: the screens to drag into place as on
// Windows (drawn where Hyprland has them; one let go snaps to a side of another, and every screen's position is saved,
// moved so the top left one is at 0,0) and the main screen, then dots-settings's other screen settings (night light,
// each screen's mode, scale, rotation) and each screen's own wallpaper, as AgrOS sections (AgrosSections.qml)

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property var layout: AgrosSettings.byKey["screens.layout"] ?? null

    // Where screen i, let go at x, y (Hyprland's layout pixels), goes: against the side of another screen nearest to
    // there, sharing at least a quarter of the shorter edge, lined up with its top, bottom or middle (or left, right,
    // centre) when within 48 px of that; never over a screen. Back where it was if no side fits
    function snap(list: var, i: int, x: real, y: real): var {
        const d = list[i], others = list.filter((_, j) => j !== i);
        if (!others.length)
            return { x: 0, y: 0 };
        const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
        const align = (v, o, size, osize) => [o, o + osize - size, o + (osize - size) / 2].find(c => Math.abs(v - c) <= 48) ?? v;
        const over = (cx, cy) => others.some(o => cx < o.x + o.w && cx + d.w > o.x && cy < o.y + o.h && cy + d.h > o.y);
        let best = null, dist = Infinity;
        for (const o of others) {
            const sy = Math.min(d.h, o.h) / 4, sx = Math.min(d.w, o.w) / 4;
            const ay = align(clamp(y, o.y - d.h + sy, o.y + o.h - sy), o.y, d.h, o.h);
            const ax = align(clamp(x, o.x - d.w + sx, o.x + o.w - sx), o.x, d.w, o.w);
            for (const [cx, cy] of [[o.x + o.w, ay], [o.x - d.w, ay], [ax, o.y + o.h], [ax, o.y - d.h]]) {
                const away = Math.hypot(cx - x, cy - y);
                if (away < dist && !over(cx, cy)) {
                    best = { x: Math.round(cx), y: Math.round(cy) };
                    dist = away;
                }
            }
        }
        return best ?? { x: d.x, y: d.y };
    }

    // The layout moved so its top left is 0,0: none left of or above it (Proton games aim the mouse elsewhere there)
    function normal(list: var): var {
        const mx = Math.min(...list.map(s => s.x)), my = Math.min(...list.map(s => s.y));
        return list.map(s => Object.assign({}, s, { x: s.x - mx, y: s.y - my }));
    }

    title: "Display"
    Component.onCompleted: AgrosSettings.reload()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: "Arrangement"
        }

        StyledRect {
            id: arr

            property var screens: []
            readonly property real minX: Math.min(...screens.map(s => s.x))
            readonly property real minY: Math.min(...screens.map(s => s.y))
            readonly property real spanW: Math.max(...screens.map(s => s.x + s.w)) - minX
            readonly property real spanH: Math.max(...screens.map(s => s.y + s.h)) - minY
            // (room around them to drag one to any side)
            readonly property real k: screens.length ? Math.min(width / (spanW * 1.8), height / (spanH * 1.8)) : 1
            readonly property real ox: (width - spanW * k) / 2
            readonly property real oy: (height - spanH * k) / 2

            Layout.fillWidth: true
            implicitHeight: 280
            topLeftRadius: Tokens.rounding.large
            topRightRadius: Tokens.rounding.large
            bottomLeftRadius: Tokens.rounding.extraSmall
            bottomRightRadius: Tokens.rounding.extraSmall
            color: Colours.layer(Colours.palette.m3surfaceContainer, 2)

            Connections {
                function onLayoutChanged(): void {
                    arr.screens = root.layout?.screens ?? [];
                }

                target: root
            }
            Component.onCompleted: screens = root.layout?.screens ?? []

            StyledText {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: Tokens.padding.large
                text: arr.screens.length > 1 ? "Drag the screens to where they stand on your desk" : ""
                color: Colours.palette.m3outline
                font: Tokens.font.label.small
            }

            Repeater {
                model: arr.screens

                StyledRect {
                    id: scr

                    required property var modelData
                    required property int index
                    readonly property bool main: modelData.id === (AgrosSettings.byKey["screens.main"]?.value ?? "")

                    x: arr.ox + (modelData.x - arr.minX) * arr.k
                    y: arr.oy + (modelData.y - arr.minY) * arr.k
                    width: modelData.w * arr.k
                    height: modelData.h * arr.k
                    radius: Tokens.rounding.medium
                    color: drag.active ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHighest
                    border.width: 2
                    border.color: drag.active || hover.hovered ? Colours.palette.m3primary : Colours.palette.m3outlineVariant
                    z: drag.active ? 1 : 0

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width - Tokens.padding.medium * 2
                        spacing: 0

                        MaterialIcon {
                            Layout.alignment: Qt.AlignHCenter
                            visible: scr.main
                            text: "star"
                            color: Colours.palette.m3primary
                        }

                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: scr.modelData.model || scr.modelData.name
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: `${scr.modelData.name} · ${scr.modelData.w}×${scr.modelData.h}`
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }
                    }

                    HoverHandler {
                        id: hover

                        cursorShape: arr.screens.length > 1 ? (drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.ArrowCursor
                    }

                    DragHandler {
                        id: drag

                        enabled: arr.screens.length > 1
                        onActiveChanged: {
                            if (active)
                                return;
                            const list = arr.screens.map(s => Object.assign({}, s));
                            const at = root.snap(list, scr.index, (scr.x - arr.ox) / arr.k + arr.minX, (scr.y - arr.oy) / arr.k + arr.minY);
                            list[scr.index] = Object.assign(list[scr.index], at);
                            const placed = root.normal(list);
                            arr.screens = placed; // (drawn there at once; the schema read after the apply says where they are)
                            for (const s of placed)
                                AgrosSettings.set(s.key, `${s.x}x${s.y}`);
                        }
                    }
                }
            }
        }

        AgrosRow {
            key: "screens.main"
            last: true
        }

        AgrosSections {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.large
            firstHeader: false
            pageIds: ["screens"]
            skipGroups: ["Arrangement"]
        }

        AgrosSections {
            Layout.fillWidth: true
            firstHeader: false
            notice: false
            pageIds: ["look"]
            onlyGroups: ["Wallpaper"]
            skipKeys: ["look.wallpaper"]
        }
    }
}
