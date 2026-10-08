import 'package:uuid/uuid.dart';

enum RoutingRuleType { address, ip, app }
enum RoutingAction { proxy, direct, block }

class RoutingRule {
  final String id;
  final RoutingRuleType type;
  final List<String> values;
  final RoutingAction action;
  final bool enabled;
  final String? remark;

  const RoutingRule({
    required this.id,
    required this.type,
    required this.values,
    required this.action,
    this.enabled = true,
    this.remark,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'values': values,
    'action': action.name,
    'enabled': enabled,
    'remark': remark,
  };

  factory RoutingRule.fromJson(Map<String, dynamic> json) {
    return RoutingRule(
      id: json['id'] as String? ?? const Uuid().v4(),
      type: RoutingRuleType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => RoutingRuleType.address,
      ),
      values: (json['values'] as List<dynamic>?)
              ?.map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList() ??
          [],
      action: RoutingAction.values.firstWhere(
        (e) => e.name == json['action'],
        orElse: () => RoutingAction.direct,
      ),
      enabled: json['enabled'] != false,
      remark: json['remark'] as String?,
    );
  }

  RoutingRule copyWith({
    String? id,
    RoutingRuleType? type,
    List<String>? values,
    RoutingAction? action,
    bool? enabled,
    String? remark,
  }) {
    return RoutingRule(
      id: id ?? this.id,
      type: type ?? this.type,
      values: values ?? this.values,
      action: action ?? this.action,
      enabled: enabled ?? this.enabled,
      remark: remark ?? this.remark,
    );
  }
}
