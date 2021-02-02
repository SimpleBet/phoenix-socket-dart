import 'package:logging/logging.dart';
import 'package:phoenix_socket/phoenix_socket.dart';

/// Callback for external reporting purposes on latency measurement. E.g. Send to datadog.
typedef ReportingCallback = void Function(String topic, int measurement);

/// Used to measure socket latency
class SocketTracing {
  /// Can be initialized with reporting callback to report back measurements.
  SocketTracing({this.enabled = false, ReportingCallback reportingCallback}) {
    _reportingCallback = reportingCallback;
    _logger = Logger('phoenix_socket.latency');
    _latenciesPerChannel = {};
    _awaitingMsgSpanStart = {};
  }

  /// Is socket tracing enabled?
  bool enabled;

  Map<String, int> _awaitingMsgSpanStart;
  Map<String, List<int>> _latenciesPerChannel;
  Logger _logger;
  ReportingCallback _reportingCallback;

  String _parseChannelName(String topic) => topic.replaceAll(
      RegExp(
        '[:,*&?!@#\$%]',
      ),
      '');

  String _channelName(Message message) {
    final channelName = _parseChannelName(message.topic);

    if (channelName == 'phoenix') {
      // return message.event.value;
      // TODO: store the 'topic' on startSpan in _awaitingMsgSpanStart.
      return 'heartbeat';
    }

    return channelName;
  }

  /// Begin latency mesaurement.
  void startSpan(Message message) {
    final latencySpanStart = DateTime.now().millisecondsSinceEpoch;
    final channelName = _channelName(message);

    _logger.finer(() {
      final channelText =
          channelName == 'heartbeat' ? 'Heartbeat' : 'Channel: $channelName';

      return '$channelText | Send Time: ${latencySpanStart}ms | Ref: ${message.ref}';
    });

    _awaitingMsgSpanStart[message.ref] = latencySpanStart;
  }

  /// End latency measurement.
  void endSpan(Message message) {
    if (_awaitingMsgSpanStart.containsKey(message.ref)) {
      final latencySpanEnd = DateTime.now().millisecondsSinceEpoch;
      final latencySpanStart = _awaitingMsgSpanStart[message.ref];
      final measuredLatency = latencySpanEnd - latencySpanStart;
      final channelName = _channelName(message);

      _awaitingMsgSpanStart.remove(message.ref);

      if (_latenciesPerChannel.containsKey(channelName)) {
        _latenciesPerChannel[channelName].add(measuredLatency);
      } else {
        _latenciesPerChannel[channelName] = [measuredLatency];
      }

      final avgChannelLatency =
          _latenciesPerChannel[channelName].reduce((v, e) => v + e) /
              _latenciesPerChannel[channelName].length;

      _logger.finer(() =>
          'Channel: $channelName | Ref: ${message.ref} | End Time: ${latencySpanEnd}ms | Round Trip Time:  ${measuredLatency}ms | Avg. Channel Latency: ${avgChannelLatency}ms');

      if (_reportingCallback != null) {
        final channel = _channelName(message);
        _reportingCallback(channel, measuredLatency);
      }
    }
  }
}
