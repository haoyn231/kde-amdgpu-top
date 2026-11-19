// SPDX-FileCopyrightText: 2026 haoyn231
// SPDX-License-Identifier: MIT
//
// 进程占用列表。
//
// 刷新策略参考了 DankMaterialShell 的 ProcessesView：只有当列表停在最顶上时才
// 每秒重建模型；一旦用户往下滚动，列表就冻结成静态表格，避免每秒重排打断阅读。
// 回到顶部（或点「已暂停」提示）后自动恢复实时刷新。

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
    id: section

    property var snap: null
    property int maxProcs: 12
    property string preferredSort: "vram"
    property bool active: true          // 弹窗没打开时不做任何重建

    property string sortKey: preferredSort
    property bool sortDesc: true
    property bool paused: false
    property int expandedPid: -1

    readonly property bool ready: snap !== null && snap.ok === true
    readonly property real totalVram: ready && snap.vram.total > 0 ? snap.vram.total : 1
    readonly property int processCount: ready ? (snap.proc_count || 0) : 0
    readonly property color textColor: Kirigami.Theme.textColor
    readonly property color accentColor: Kirigami.Theme.highlightColor
    readonly property real pidWidth: Math.round(Kirigami.Units.gridUnit * 2.9)
    readonly property real gfxWidth: Math.round(Kirigami.Units.gridUnit * 2.4)
    readonly property real vramWidth: Math.round(Kirigami.Units.gridUnit * 4.2)

    property string lastSignature: ""

    implicitHeight: Kirigami.Units.gridUnit * 11
    implicitWidth: Kirigami.Units.gridUnit * 18

    onPreferredSortChanged: {
        sortKey = preferredSort;
        sortDesc = true;
        resume();
    }
    onSnapChanged: refresh()
    onActiveChanged: {
        if (active) {
            // 每次打开弹窗都回到"点面板时选的那一列"，避免上次手动排序的残留
            sortKey = preferredSort;
            sortDesc = true;
            resume();
        }
    }

    function resume() {
        if (list.contentY > 0) {
            list.positionViewAtBeginning();
        }
        paused = false;
        lastSignature = "";
        refresh();
    }

    function setSort(key) {
        if (sortKey === key) {
            sortDesc = !sortDesc;
        } else {
            sortKey = key;
            sortDesc = true;
        }
        resume();
    }

    // 把排序后的进程整理成"模型应该长成的样子"
    function wantedRows() {
        // 注意：不能在这里读 ready 绑定，属性变化通知的当下绑定值还是旧的，
        // 所以直接从 snap 现算一遍。
        const usable = snap !== null && snap !== undefined && snap.ok === true;
        if (!usable || !snap.procs || snap.procs.length === 0) {
            return [];
        }
        const rows = snap.procs.slice(0);
        const key = sortKey;
        const desc = sortDesc;
        rows.sort(function (left, right) {
            let diff = 0;
            if (key === "gfx") {
                diff = left.gfx - right.gfx;
            } else if (key === "name") {
                const a = String(left.name).toLowerCase();
                const b = String(right.name).toLowerCase();
                diff = a < b ? -1 : (a > b ? 1 : 0);
            } else {
                diff = left.vram - right.vram;
            }
            if (diff === 0) {
                diff = left.pid - right.pid;
            }
            return desc ? -diff : diff;
        });

        const limited = rows.slice(0, Math.max(1, maxProcs));
        const vramTotal = snap.vram && snap.vram.total > 0 ? snap.vram.total : 1;
        const out = [];
        for (let i = 0; i < limited.length; ++i) {
            const item = limited[i];
            out.push({
                pid: item.pid,
                name: item.name,
                cmd: item.cmd,
                ppid: item.ppid,
                vram: item.vram,
                gtt: item.gtt,
                gfx: item.gfx,
                media: item.media,
                share: (item.vram / vramTotal) * 100
            });
        }
        return out;
    }

    // 增量同步模型，而不是每秒 clear() + append()：后者会把所有 delegate 销毁重建，
    // 界面就一帧一帧地闪。这里只挪位置、增删行、改变化的字段，行对象保持不动。
    function refresh() {
        if (!active || paused) {
            return;
        }
        const wanted = wantedRows();

        let signature = "";
        for (let i = 0; i < wanted.length; ++i) {
            const row = wanted[i];
            signature += row.pid + ":" + row.name + ":" + row.gfx + ":" + row.vram
                       + ":" + row.gtt + ":" + row.media + ":" + row.share.toFixed(1) + ";";
        }
        if (signature === lastSignature) {
            return;                        // 一个字段都没变，连 setProperty 都省了
        }
        lastSignature = signature;

        // 1) 先让行顺序和 pid 序列对齐：已在列表里的用 move 挪，没有的插入
        for (let i = 0; i < wanted.length; ++i) {
            if (i >= procModel.count) {
                procModel.append(wanted[i]);
                continue;
            }
            if (procModel.get(i).pid === wanted[i].pid) {
                continue;
            }
            let existing = -1;
            for (let j = i + 1; j < procModel.count; ++j) {
                if (procModel.get(j).pid === wanted[i].pid) {
                    existing = j;
                    break;
                }
            }
            if (existing >= 0) {
                procModel.move(existing, i, 1);
            } else {
                procModel.insert(i, wanted[i]);
            }
        }

        // 2) 去掉多出来的尾巴
        if (procModel.count > wanted.length) {
            procModel.remove(wanted.length, procModel.count - wanted.length);
        }

        // 3) 只更新真正变化的字段
        for (let i = 0; i < wanted.length; ++i) {
            const current = procModel.get(i);
            const target = wanted[i];
            for (const key in target) {
                if (current[key] !== target[key]) {
                    procModel.setProperty(i, key, target[key]);
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        // ---------- 标题栏 ----------
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Text {
                text: qsTr("进程")
                color: section.textColor
                font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.66)
                font.bold: true
            }

            Text {
                text: section.processCount
                visible: section.ready
                color: Qt.rgba(section.textColor.r, section.textColor.g, section.textColor.b, 0.45)
                font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.6)
            }

            Rectangle {
                visible: section.paused
                implicitWidth: pausedLabel.implicitWidth + Kirigami.Units.smallSpacing * 2
                implicitHeight: Kirigami.Units.gridUnit * 1.35
                radius: height / 2
                color: Qt.rgba(section.accentColor.r, section.accentColor.g, section.accentColor.b, 0.18)

                Text {
                    id: pausedLabel
                    anchors.centerIn: parent
                    text: qsTr("已暂停 · 回到顶部")
                    color: section.accentColor
                    font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.55)
                }

                TapHandler { onTapped: section.resume() }
            }

            Item { Layout.fillWidth: true }

            SortChip {
                text: qsTr("显存")
                active: section.sortKey === "vram"
                descending: section.sortDesc
                onClicked: section.setSort("vram")
            }

            SortChip {
                text: qsTr("GPU")
                active: section.sortKey === "gfx"
                descending: section.sortDesc
                onClicked: section.setSort("gfx")
            }
        }

        // ---------- 列标题 ----------
        // 用和 delegate 完全相同的几何（宽度 - 10 的滚动条预留、左右各 4 的边距），
        // 这样列标题和数值一定对齐。
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: headerRow.implicitHeight
            visible: section.ready

            RowLayout {
                id: headerRow
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.leftMargin: Kirigami.Units.smallSpacing
                width: Math.max(0, list.width - 10 - Kirigami.Units.smallSpacing * 2)
                spacing: Kirigami.Units.smallSpacing

            Text {
                Layout.fillWidth: true
                text: qsTr("名称")
                color: Qt.rgba(section.textColor.r, section.textColor.g, section.textColor.b, 0.36)
                font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.54)
            }
            Text {
                Layout.preferredWidth: section.pidWidth
                horizontalAlignment: Text.AlignRight
                text: "PID"
                color: Qt.rgba(section.textColor.r, section.textColor.g, section.textColor.b, 0.36)
                font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.54)
            }
            Text {
                Layout.preferredWidth: section.gfxWidth
                horizontalAlignment: Text.AlignRight
                text: "GPU"
                color: Qt.rgba(section.textColor.r, section.textColor.g, section.textColor.b, 0.36)
                font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.54)
            }
                Text {
                    Layout.preferredWidth: section.vramWidth
                    horizontalAlignment: Text.AlignRight
                    text: qsTr("显存")
                    color: Qt.rgba(section.textColor.r, section.textColor.g, section.textColor.b, 0.36)
                    font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.54)
                }
            }
        }

        // ---------- 列表 ----------
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ListView {
                id: list
                anchors.fill: parent
                clip: true
                model: procModel
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: 400
                bottomMargin: Kirigami.Units.smallSpacing
                onContentYChanged: {
                    if (contentY > 1 && !section.paused) {
                        section.paused = true;
                    } else if (contentY <= 1 && section.paused) {
                        section.paused = false;
                        section.lastSignature = "";
                        section.refresh();
                    }
                }

                // 排序变化导致的行位移用短动画带过，避免整块突然跳一下
                move: Transition {
                    NumberAnimation {
                        properties: "y"
                        duration: Kirigami.Units.shortDuration
                        easing.type: Easing.OutCubic
                    }
                }

                displaced: Transition {
                    NumberAnimation {
                        properties: "y"
                        duration: Kirigami.Units.shortDuration
                        easing.type: Easing.OutCubic
                    }
                }

                delegate: ProcessRow {
                    width: list.width - 10
                    name: model.name
                    pid: model.pid
                    cmd: model.cmd
                    ppid: model.ppid
                    vram: model.vram
                    gtt: model.gtt
                    gfx: model.gfx
                    media: model.media
                    share: model.share
                    expanded: section.expandedPid === model.pid
                    onToggled: section.expandedPid = (section.expandedPid === model.pid ? -1 : model.pid)
                }
            }

            // 极细的滚动位置提示，不抢焦点、不吃滚轮事件
            Rectangle {
                id: scrollHint
                visible: list.contentHeight > list.height + 1
                width: 3
                radius: 1.5
                height: Math.max(24, list.height * list.height / Math.max(1, list.contentHeight))
                x: parent.width - width - 1
                y: list.contentY / Math.max(1, list.contentHeight - list.height) * (list.height - height)
                color: Qt.rgba(section.textColor.r, section.textColor.g, section.textColor.b, 0.25)
            }

            Text {
                anchors.centerIn: parent
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                visible: section.ready && procModel.count === 0
                text: qsTr("没有进程占用显存")
                color: Qt.rgba(section.textColor.r, section.textColor.g, section.textColor.b, 0.45)
                font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.62)
            }
        }
    }

    ListModel { id: procModel }
}
