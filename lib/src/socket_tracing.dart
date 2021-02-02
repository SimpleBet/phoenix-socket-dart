import 'package:logging/logging.dart';
import 'package:phoenix_socket/phoenix_socket.dart';

/// Callback for external reporting purposes on latency measurement. E.g. Send to datadog.
typedef ReportingCallback = void Function(String topic, int measurement);

// /// Socket Tracing Options
// class SocketTracingOptions {
//   /// Init options for Tracing
//   SocketTracingOptions({this.trace = false, this.reportingCallback});

//   /// Enable / disable tracing.
//   final bool trace;

//   /// Function to report back spans.
//   final ReportingCallback reportingCallback;
// }

/// Used to measure socket latency
class SocketTracing {
  /// Can be initialized with reporting callback to report back measurements.
  SocketTracing({this.enabled = false, ReportingCallback reportingCallback}) {
    _reportingCallback = reportingCallback;
    _logger = Logger('phoenix_socket.latency');
  }

  /// Is socket tracing enabled?
  bool enabled;

  /// Tracked message refs aaiting response from server.
  Map<String, int> awaitingMsgSpanStart = {};

  /// List of current session latencies per channel.
  Map<String, List<int>> latenciesPerChannel;

  Logger _logger;
  ReportingCallback _reportingCallback;

  String _channelName(String topic) => topic.replaceAll(
      RegExp(
        '[:,*&?!@#\$%]',
      ),
      '');

  /// Begin latency mesaurement.
  void startSpan(Message message) {
    final latencySpanStart = DateTime.now().millisecondsSinceEpoch;
    final channelName = _channelName(message.topic);

    _logger.finer(() =>
        'Channel: $channelName | Send Time: ${latencySpanStart}ms | Ref: ${message.ref}');

    awaitingMsgSpanStart[message.ref] = latencySpanStart;
  }

  /// End latency measurement.
  void endSpan(Message message) {
    if (awaitingMsgSpanStart.containsKey(message.ref)) {
      final latencySpanEnd = DateTime.now().millisecondsSinceEpoch;
      final latencySpanStart = awaitingMsgSpanStart[message.ref];
      final measuredLatency = latencySpanEnd - latencySpanStart;
      final channelName = _channelName(message.topic);

      awaitingMsgSpanStart.remove(message.ref);

      if (latenciesPerChannel[channelName] != null) {
        latenciesPerChannel[channelName] = [];
      }

      latenciesPerChannel[channelName].add(measuredLatency);

      final avgChannelLatency =
          latenciesPerChannel[channelName].reduce((v, e) => v + e) /
              latenciesPerChannel[channelName].length;

      _logger.finer(() =>
          'Channel: $channelName | Ref: ${message.ref} | End Time: ${latencySpanEnd}ms | Round Trip Time:  ${measuredLatency}ms | Avg. Channel Latency: ${avgChannelLatency}ms');

      if (_reportingCallback != null) {
        final channel = _channelName(message.topic);
        _reportingCallback(channel, measuredLatency);
      }
    }
  }
}
