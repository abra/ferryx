import 'dart:async';

import 'package:domain_models/domain_models.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:network_service/network_service.dart';

/// Connect to Server: the address typed, the saved servers and the
/// addresses connected to lately, which one the cursor is on, and the
/// connection under way.
@immutable
class ConnectState extends Equatable {
  const ConnectState({
    this.servers = const [],
    this.recent = const [],
    this.cursor = -1,
    this.address = '',
    this.parsed,
    this.invalid = false,
    this.connectingTo,
    this.error,
    this.connection,
  });

  final List<ServerProfile> servers;

  /// Addresses connected to lately that are not saved servers, the newest
  /// first.
  final List<String> recent;

  /// The row the cursor is on: a saved server, then a recent address;
  /// -1 for none.
  final int cursor;

  /// The address field.
  final String address;

  /// What [address] reads as; `null` while it is empty or [invalid].
  final ServerAddress? parsed;

  /// [address] is no server's address.
  final bool invalid;

  /// The server being connected to, as it reads (`sftp://me@host`).
  final String? connectingTo;

  /// The last attempt's failure.
  final FerryxException? error;

  /// The connection made: the dialog closes with it.
  final ServerConnection? connection;

  int get rowCount => servers.length + recent.length;

  bool get connecting => connectingTo != null;

  ServerProfile? get selectedServer =>
      cursor >= 0 && cursor < servers.length ? servers[cursor] : null;

  String? get selectedRecent {
    final at = cursor - servers.length;
    return at >= 0 && at < recent.length ? recent[at] : null;
  }

  /// The protocol of what Connect would connect to, when known.
  ServerProtocol? get protocol =>
      address.trim().isNotEmpty ? (parsed?.protocol) : selectedServer?.protocol;

  /// What Connect would send crosses the network unencrypted.
  bool get insecure => protocol != null && !protocol!.secure;

  bool get canConnect =>
      !connecting && (address.trim().isNotEmpty ? parsed != null : cursor >= 0);

  ConnectState copyWith({
    List<ServerProfile>? servers,
    List<String>? recent,
    int? cursor,
    String? address,
    ServerAddress? parsed,
    bool clearParsed = false,
    bool? invalid,
    String? connectingTo,
    bool clearConnecting = false,
    FerryxException? error,
    bool clearError = false,
    ServerConnection? connection,
  }) => ConnectState(
    servers: servers ?? this.servers,
    recent: recent ?? this.recent,
    cursor: cursor ?? this.cursor,
    address: address ?? this.address,
    parsed: clearParsed ? null : (parsed ?? this.parsed),
    invalid: invalid ?? this.invalid,
    connectingTo: clearConnecting ? null : (connectingTo ?? this.connectingTo),
    error: clearError ? null : (error ?? this.error),
    connection: connection ?? this.connection,
  );

  @override
  List<Object?> get props => [
    servers,
    recent,
    cursor,
    address,
    parsed,
    invalid,
    connectingTo,
    error,
    connection,
  ];
}

class ConnectCubit extends Cubit<ConnectState> {
  ConnectCubit({
    required this._service,
    required List<ServerProfile> servers,
    required this.onServersChanged,
    List<String> recent = const [],
    this.onRecent,
    String initialAddress = '',
  }) : super(
         ConnectState(
           servers: servers,
           recent: _unsaved(recent, servers),
           cursor: servers.isNotEmpty || recent.isNotEmpty ? 0 : -1,
         ),
       ) {
    if (initialAddress.isNotEmpty) {
      typeAddress(initialAddress);
    } else if (state.cursor >= 0) {
      select(0);
    }
  }

  final NetworkService _service;

  /// The saved servers changed: the preferences keep them.
  final ValueChanged<List<ServerProfile>> onServersChanged;

  /// An address not saved was connected to: the recent list keeps it.
  final ValueChanged<String>? onRecent;

  ConnectAttempt? _attempt;

  static List<String> _unsaved(
    List<String> recent,
    List<ServerProfile> servers,
  ) => [
    for (final address in recent)
      if (!servers.any((s) => s.address == address)) address,
  ];

  /// The cursor goes to row [index]; the address field takes its address.
  void select(int index) {
    if (state.connecting || index < 0 || index >= state.rowCount) return;
    final address = index < state.servers.length
        ? state.servers[index].address
        : state.recent[index - state.servers.length];
    emit(state.copyWith(cursor: index, clearError: true));
    typeAddress(address);
  }

  void moveCursor(int delta) {
    if (state.rowCount == 0) return;
    final from = state.cursor < 0
        ? (delta > 0 ? -1 : state.rowCount)
        : state.cursor;
    select((from + delta).clamp(0, state.rowCount - 1));
  }

  /// The address field changed.
  void typeAddress(String text) {
    if (state.connecting) return;
    final trimmed = text.trim();
    ServerAddress? parsed;
    var invalid = false;
    if (trimmed.isNotEmpty) {
      try {
        parsed = _service.parse(trimmed);
      } on FerryxException {
        invalid = true;
      }
    }
    emit(
      state.copyWith(
        address: text,
        parsed: parsed,
        clearParsed: parsed == null,
        invalid: invalid,
        clearError: true,
      ),
    );
  }

  /// What Connect connects to: the saved server whose address the field
  /// holds (so its way of logging in goes along), else the address typed.
  (ServerProfile, String?)? _target() {
    final typed = state.address.trim();
    final selected = state.selectedServer;
    if (selected != null && (typed.isEmpty || typed == selected.address)) {
      return (selected, null);
    }
    final parsed = state.parsed;
    if (parsed == null) return null;
    return (
      ServerProfile(
        id: 'address',
        protocol: parsed.protocol,
        host: parsed.host,
        port: parsed.port,
        user: parsed.user,
        path: parsed.path,
      ),
      parsed.password,
    );
  }

  /// Connects; [ConnectState.connection] is set once it is made.
  Future<void> connect() async {
    if (!state.canConnect) return;
    final target = _target();
    if (target == null) return;
    final (profile, password) = target;
    final attempt = _service.connect(profile, password: password);
    _attempt = attempt;
    emit(
      state.copyWith(connectingTo: profile.displayRoot, clearError: true),
    );
    try {
      final connection = await attempt.result;
      if (isClosed) return;
      if (!state.servers.any((s) => s.id == profile.id)) {
        // Kept without the password, never with it.
        onRecent?.call(profile.address);
      }
      emit(state.copyWith(clearConnecting: true, connection: connection));
    } on FerryxException catch (error) {
      if (isClosed) return;
      emit(
        state.copyWith(
          clearConnecting: true,
          error: error.kind == FerryxErrorKind.cancelled ? null : error,
          clearError: error.kind == FerryxErrorKind.cancelled,
        ),
      );
    } finally {
      if (identical(_attempt, attempt)) _attempt = null;
    }
  }

  /// Gives up the connection under way.
  void cancel() => _attempt?.cancel();

  // ─── Saved servers ───

  void addServer(ServerProfile server) {
    final servers = [...state.servers, server];
    _setServers(servers, cursor: servers.length - 1);
  }

  void updateServer(ServerProfile server) {
    final servers = [
      for (final s in state.servers) s.id == server.id ? server : s,
    ];
    _setServers(servers, cursor: servers.indexWhere((s) => s.id == server.id));
  }

  void removeServer(String id) {
    final at = state.servers.indexWhere((s) => s.id == id);
    if (at < 0) return;
    final servers = [...state.servers]..removeAt(at);
    final rows = servers.length + state.recent.length;
    _setServers(
      servers,
      cursor: rows == 0 ? -1 : at.clamp(0, rows - 1),
    );
  }

  /// Saves the address typed as a new server named after its host.
  ServerProfile? serverFromAddress(String id) {
    final target = _target();
    if (target == null) return null;
    final (profile, _) = target;
    return ServerProfile(
      id: id,
      protocol: profile.protocol,
      host: profile.host,
      port: profile.port == profile.protocol.defaultPort ? 0 : profile.port,
      user: profile.user,
      path: profile.path,
      auth: profile.auth,
      keyPath: profile.keyPath,
    );
  }

  void _setServers(List<ServerProfile> servers, {required int cursor}) {
    onServersChanged(servers);
    emit(
      state.copyWith(
        servers: servers,
        recent: _unsaved(state.recent, servers),
        cursor: cursor,
      ),
    );
    if (cursor >= 0) select(cursor);
  }

  /// Forgets the password the keychain keeps for [server].
  Future<FerryxException?> forgetPassword(ServerProfile server) async {
    try {
      await _service.forgetPassword(_service.keyOf(server));
      return null;
    } on FerryxException catch (error) {
      return error;
    }
  }

  @override
  Future<void> close() {
    _attempt?.cancel();
    return super.close();
  }
}
