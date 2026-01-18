import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.DBusMenu
import Quickshell.Wayland
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Services.Compositor
import qs.Services.UI
import qs.Widgets

Rectangle {
  id: root

  property var pluginApi: null

  property ShellScreen screen
  property string widgetId: ""
  property string section: ""

  readonly property string barPosition: Settings.data.bar.position
  readonly property bool isVertical: barPosition === "left" || barPosition === "right"

  property var currentOpenSubmenu: null
  property var clickCatcher: null

  onCurrentOpenSubmenuChanged: {
    if (currentOpenSubmenu !== null) {
      if (!clickCatcher) {
        clickCatcher = clickCatcherComponent.createObject(null);
      }
    } else {
      if (clickCatcher) {
        clickCatcher.destroy();
        clickCatcher = null;
      }
    }
  }

  DBusMenuHandle {
    id: windowMenuHandle
  }

  QsMenuOpener {
    id: menuOpener
    menu: windowMenuHandle
  }

  Component {
    id: trayMenuComponent
    TrayMenu {
      onVisibleChanged: {
        if (!visible && root.currentOpenSubmenu === this) {
          root.currentOpenSubmenu = null;
        }
      }
    }
  }

  Component {
    id: clickCatcherComponent
    PanelWindow {
      screen: root.screen
      color: "transparent"
      visible: true

      anchors.top: true
      anchors.left: true
      anchors.right: true
      anchors.bottom: true

      margins.top: Settings.data.bar.position === "top" ? Style.barHeight : 0
      margins.bottom: Settings.data.bar.position === "bottom" ? Style.barHeight : 0
      margins.left: Settings.data.bar.position === "left" ? Style.barHeight : 0
      margins.right: Settings.data.bar.position === "right" ? Style.barHeight : 0

      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      WlrLayershell.namespace: "noctalia-globalmenu-clickcatcher"
      WlrLayershell.exclusionMode: ExclusionMode.Ignore

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onClicked: {
          if (root.currentOpenSubmenu) {
            const menuToClose = root.currentOpenSubmenu;
            menuToClose.hideMenu();
            menuToClose.destroy();
            root.currentOpenSubmenu = null;
          }
        }
      }
    }
  }

  readonly property bool hasMenuItems: menuOpener.children && menuOpener.children.values.length > 0

  implicitWidth: isVertical ? Style.capsuleHeight : Math.round(menuLayout.implicitWidth + Style.marginXS * 2)
  implicitHeight: isVertical ? Math.round(menuLayout.implicitHeight + Style.marginXS * 2) : Style.capsuleHeight

  Layout.alignment: Qt.AlignVCenter
  radius: Style.radiusM
  color: Style.capsuleColor
  visible: hasMenuItems

  Connections {
    target: CompositorService
    function onActiveWindowChanged() {
      updateGlobalMenu();
    }
  }

  Timer {
    id: initTimer
    interval: 100
    repeat: false
    running: true
    onTriggered: updateGlobalMenu()
  }

  Process {
    id: dbusMenuQuery
    running: false

    property string out: ""

    stdout: StdioCollector {}
    onExited: function(exitCode) {
      if (exitCode === 0) {
        onDbusResponse(stdout.text);
      } else {
        clearMenu();
      }
    }
  }

  function onDbusResponse(output) {
    let service = "";
    let path = "";

    for (let line of output.split('\n')) {
      line = line.trim();
      let match;
      if (line === '' || line.startsWith("method return ")) {
      } else if (match = line.match(/^string "(.*)"$/)) {
        service = match[1]
      } else if (match = line.match(/^object path "(.*)"$/)) {
        path = match[1]
      } else {
        Logger.w("GlobalMenu", "Unexpected dbus-send stdout line", line, match)
      }
    }

    if (service && path) {
      windowMenuHandle.setAddress(service, path);
    } else {
      clearMenu();
    }
  }

  function queryDbusMenu(windowId) {
    if (!windowId) {
      clearMenu();
      return;
    }

    if (dbusMenuQuery.running) {
      dbusMenuQuery.running = false;
    }

    dbusMenuQuery.command = [
      "dbus-send",
      "--print-reply",
      "--session",
      "--dest=com.canonical.AppMenu.Registrar",
      "/com/canonical/AppMenu/Registrar",
      "com.canonical.AppMenu.Registrar.GetMenuForWindow",
      "uint32:" + windowId
    ];

    dbusMenuQuery.running = true;
  }

  function updateGlobalMenu() {
    let focusedWindow = CompositorService.getFocusedWindow();
    if (focusedWindow && focusedWindow.id !== undefined && focusedWindow.id !== null) {
      queryDbusMenu(focusedWindow.id.toString());
    } else {
      clearMenu();
    }
  }

  function clearMenu() {
    windowMenuHandle.setAddress("", "");
  }

  RowLayout {
    id: menuLayout
    anchors.fill: parent
    anchors.margins: Style.marginXS
    spacing: 0

    Repeater {
      model: menuOpener.children ? [...menuOpener.children.values] : []

      delegate: Rectangle {
        id: menuButton
        required property var modelData
        property var subMenu: null

        Connections {
          target: root
          function onCurrentOpenSubmenuChanged() {
            if (root.currentOpenSubmenu !== subMenu && subMenu) {
              subMenu = null;
            }
          }
        }

        Layout.preferredHeight: parent.height
        Layout.preferredWidth: buttonText.implicitWidth + Style.marginM * 2
        color: buttonMouseArea.containsMouse || subMenu?.visible ? Color.mHover : "transparent"
        radius: Style.radiusS

        NText {
          id: buttonText
          anchors.centerIn: parent
          text: modelData?.text ?? ""
          color: buttonMouseArea.containsMouse || subMenu?.visible ? Color.mOnHover : Color.mOnSurface
          pointSize: Style.fontSizeS
        }

        MouseArea {
          id: buttonMouseArea
          anchors.fill: parent
          hoverEnabled: true

          function openSubmenu() {
            var newSubmenu = trayMenuComponent.createObject(root, {
              "menu": modelData,
              "isSubMenu": true,
              "screen": root.screen
            });

            if (newSubmenu) {
              if (root.currentOpenSubmenu && root.currentOpenSubmenu !== subMenu) {
                var oldMenu = root.currentOpenSubmenu;
                oldMenu.hideMenu();
                oldMenu.destroy();
                root.currentOpenSubmenu = null;
              }

              subMenu = newSubmenu;
              root.currentOpenSubmenu = newSubmenu;
              newSubmenu.showAt(menuButton, 0, root.isVertical ? 0 : Style.capsuleHeight);
            }
          }

          onEntered: {
            if (root.currentOpenSubmenu && !subMenu) {
              openSubmenu();
            }
          }

          onClicked: {
            if (subMenu) {
              subMenu.hideMenu();
              subMenu.destroy();
              subMenu = null;
              root.currentOpenSubmenu = null;
            } else {
              openSubmenu();
            }
          }
        }

        Component.onDestruction: {
          if (subMenu) {
            subMenu.hideMenu();
            subMenu.destroy();
            subMenu = null;
          }
        }
      }
    }
  }
}
