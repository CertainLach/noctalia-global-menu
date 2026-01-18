import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Column {
  spacing: Style.marginM

  NHeader {
    text: "Global Menu"
  }

  NText {
    text: "Global menus using the Canonical appmenu registrar dbus interface"
    color: Color.mOnSurfaceVariant
    pointSize: Style.fontSizeS
    wrapMode: Text.WordWrap
    width: parent.width
  }
}
