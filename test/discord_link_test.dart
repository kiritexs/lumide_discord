import 'dart:async';

import 'package:lumide_discord/lumide_discord.dart';
import 'package:test/test.dart';

/// Records what the link sends instead of talking to Discord.
class FakeClient implements PresenceClient {
  FakeClient({
    this.reachable = true,
    this.answers = true,
    this.delay = Duration.zero,
  });

  /// How long Discord takes to answer.
  final Duration delay;

  final bool reachable;

  /// False: accepts the connection but never answers, like a busy Discord.
  final bool answers;
  final shown = <PresenceContent>[];
  int clears = 0;
  bool closed = false;
  final _lost = StreamController<void>.broadcast();

  void loseConnection() => _lost.add(null);

  @override
  Future<void> connect(String applicationId) async {
    if (!reachable) throw StateError('Discord is not running');
    if (!answers) await Completer<void>().future;
    await Future<void>.delayed(delay);
  }

  @override
  Future<void> show(PresenceContent content) async => shown.add(content);

  @override
  Future<void> clear() async => clears++;

  @override
  Stream<void> get lost => _lost.stream;

  @override
  Future<void> close() async {
    closed = true;
    await _lost.close();
  }
}

void main() {
  const retryDelay = Duration(milliseconds: 40);
  const interval = Duration(milliseconds: 60);
  const editing = PresenceContent(details: 'Editing main.dart');
  const viewing = PresenceContent(details: 'Viewing main.dart');
  const idle = PresenceContent(details: 'Idle');

  late List<FakeClient> clients;
  late List<LinkState> states;
  late DiscordLink link;

  /// Clients handed out by the link, in order: unreachable ones first.
  /// [silent] ones accept the connection but never answer.
  void createLink({
    int unreachable = 0,
    int silent = 0,
    Duration delay = Duration.zero,
  }) {
    clients = [];
    states = [];
    var failures = unreachable;
    var silences = silent;
    link = DiscordLink(
      clientFactory: () {
        final client = FakeClient(
          reachable: failures-- <= 0,
          answers: silences-- <= 0,
          delay: delay,
        );
        clients.add(client);
        return client;
      },
      retryDelay: retryDelay,
      connectTimeout: const Duration(milliseconds: 50),
      minUpdateInterval: interval,
      onStateChanged: states.add,
    );
  }

  Future<void> wait(Duration duration) => Future.delayed(duration);

  tearDown(() => link.stop());

  test('connects and shows the presence', () async {
    createLink();
    link.show(editing);
    await link.start('1');
    await wait(Duration.zero);

    expect(link.state, LinkState.connected);
    expect(states, [LinkState.connecting, LinkState.connected]);
    expect(clients.single.shown, [editing]);
  });

  test('sends nothing before a presence is set', () async {
    createLink();
    await link.start('1');
    await wait(interval);
    expect(clients.single.shown, isEmpty);
    expect(clients.single.clears, 0);
  });

  test('retries until Discord is running', () async {
    createLink(unreachable: 2);
    link.show(editing);
    await link.start('1');

    expect(link.state, LinkState.waiting);
    expect(clients.single.closed, isTrue);

    await wait(retryDelay * 5);
    expect(link.state, LinkState.connected);
    expect(clients, hasLength(3));
    expect(clients.last.shown, [editing]);
  });

  test('gives up on a Discord that never answers and retries', () async {
    createLink(silent: 1);
    link.show(editing);
    final started = link.start('1');
    await wait(const Duration(milliseconds: 20));
    expect(link.state, LinkState.connecting);

    await started;
    expect(link.state, LinkState.waiting);
    expect(clients.single.closed, isTrue);

    await wait(retryDelay * 3);
    expect(link.state, LinkState.connected);
    expect(clients, hasLength(2));
    expect(clients.last.shown, [editing]);
  });

  test('reconnectNow while connecting opens no second connection', () async {
    createLink(delay: const Duration(milliseconds: 30));
    final started = link.start('1');
    await link.reconnectNow();
    await started;
    await wait(Duration.zero);
    expect(clients, hasLength(1));
    expect(link.state, LinkState.connected);
  });

  test('restarts before connecting open one connection', () async {
    createLink(delay: const Duration(milliseconds: 30));
    await Future.wait([link.start('1'), link.start('1')]);
    expect(clients, hasLength(1));
    expect(link.state, LinkState.connected);
  });

  test('a restart while connecting closes the earlier attempt', () async {
    createLink(delay: const Duration(milliseconds: 30));
    link.show(editing);
    final first = link.start('1');
    await wait(const Duration(milliseconds: 10)); // First attempt waiting.
    expect(link.state, LinkState.connecting);
    final second = link.start('1');
    await Future.wait([first, second]);
    await wait(interval * 2);

    expect(clients, hasLength(2));
    expect(clients.first.closed, isTrue);
    expect(clients.first.shown, isEmpty);
    expect(clients.last.closed, isFalse);
    expect(clients.last.shown, [editing]);
    expect(link.state, LinkState.connected);
  });

  test('reconnectNow skips the wait', () async {
    createLink(unreachable: 1);
    await link.start('1');
    expect(link.state, LinkState.waiting);

    await link.reconnectNow();
    expect(link.state, LinkState.connected);
    expect(clients, hasLength(2));
  });

  test('does not send the same presence twice', () async {
    createLink();
    await link.start('1');
    link.show(editing);
    await wait(interval * 2);
    link.show(editing);
    await wait(interval * 2);
    expect(clients.single.shown, [editing]);
  });

  test('merges quick changes and sends the latest', () async {
    createLink();
    await link.start('1');
    link.show(editing);
    await wait(Duration.zero);
    link
      ..show(viewing)
      ..show(idle);
    await wait(Duration.zero);
    expect(clients.single.shown, [editing]);

    await wait(interval * 2);
    expect(clients.single.shown, [editing, idle]);
  });

  test('clears the presence for null', () async {
    createLink();
    await link.start('1');
    link.show(editing);
    await wait(interval * 2);
    link.show(null);
    await wait(interval * 2);
    expect(clients.single.clears, 1);
  });

  test('reconnects and resends after losing Discord', () async {
    createLink();
    link.show(editing);
    await link.start('1');
    await wait(Duration.zero);

    clients.single.loseConnection();
    await wait(Duration.zero);
    expect(link.state, LinkState.waiting);
    expect(clients.first.closed, isTrue);

    await wait(retryDelay * 2 + interval);
    expect(link.state, LinkState.connected);
    expect(clients, hasLength(2));
    expect(clients.last.shown, [editing]);
  });

  test('stop clears, disconnects and stops retrying', () async {
    createLink();
    link.show(editing);
    await link.start('1');
    await wait(Duration.zero);

    await link.stop();
    expect(link.state, LinkState.off);
    expect(clients.single.clears, 1);
    expect(clients.single.closed, isTrue);

    createLink(unreachable: 100);
    await link.start('1');
    await link.stop();
    await wait(retryDelay * 3);
    expect(clients, hasLength(1));
  });

  test('start with a new application ID reconnects', () async {
    createLink();
    link.show(editing);
    await link.start('1');
    await link.start('2');
    await wait(interval * 2);

    expect(clients, hasLength(2));
    expect(clients.first.closed, isTrue);
    expect(clients.last.shown, [editing]);
    expect(link.state, LinkState.connected);
  });
}
