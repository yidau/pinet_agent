// This is a generated file - do not edit.
//
// Generated from monitoring.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class EventPriority extends $pb.ProtobufEnum {
  static const EventPriority P0 =
      EventPriority._(0, _omitEnumNames ? '' : 'P0');
  static const EventPriority P1 =
      EventPriority._(1, _omitEnumNames ? '' : 'P1');
  static const EventPriority P2 =
      EventPriority._(2, _omitEnumNames ? '' : 'P2');
  static const EventPriority P3 =
      EventPriority._(3, _omitEnumNames ? '' : 'P3');

  static const $core.List<EventPriority> values = <EventPriority>[
    P0,
    P1,
    P2,
    P3,
  ];

  static final $core.List<EventPriority?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static EventPriority? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const EventPriority._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
