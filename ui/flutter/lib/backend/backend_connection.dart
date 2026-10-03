enum RodinConnectionState {
  connecting,
  online,
  offline;

  static RodinConnectionState fromNative(int status) => switch (status) {
    1 => online,
    0 => offline,
    _ => connecting,
  };

  String get label => switch (this) {
    connecting => 'Connecting',
    online => 'Live',
    offline => 'Offline',
  };

  String get badgeLabel => label.toUpperCase();

  String serviceLabel({required bool enabled}) =>
      this == online && !enabled ? 'Disabled' : label;
}
