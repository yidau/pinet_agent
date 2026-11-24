// This is a generated file - do not edit.
//
// Generated from monitoring.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:grpc/service_api.dart' as $grpc;
import 'package:protobuf/protobuf.dart' as $pb;

import 'monitoring.pb.dart' as $0;

export 'monitoring.pb.dart';

@$pb.GrpcServiceName('pocketnet.v1.TelemetryService')
class TelemetryServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  TelemetryServiceClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseStream<$0.TelemetryMessage> subscribe(
    $0.SubscribeRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$subscribe, $async.Stream.fromIterable([request]),
        options: options);
  }

  $grpc.ResponseFuture<$0.AckHighRiskResponse> ackHighRisk(
    $0.AckHighRiskRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$ackHighRisk, request, options: options);
  }

  $grpc.ResponseFuture<$0.ObservedDevicesPage> getObservedDevices(
    $0.ObservedDevicesRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getObservedDevices, request, options: options);
  }

  $grpc.ResponseFuture<$0.ControlCommandResponse> setCaptureProfile(
    $0.SetCaptureProfileRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$setCaptureProfile, request, options: options);
  }

  $grpc.ResponseFuture<$0.ControlCommandResponse> setObservationMode(
    $0.SetObservationModeRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$setObservationMode, request, options: options);
  }

  $grpc.ResponseFuture<$0.RadioLabStatus> controlRadioLab(
    $0.RadioLabRequest request, {$grpc.CallOptions? options}) {
    return $createUnaryCall(_$controlRadioLab, request, options: options);
  }

  $grpc.ResponseFuture<$0.ControlCommandResponse> recoverComponent(
    $0.RecoverComponentRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$recoverComponent, request, options: options);
  }

  // method descriptors

  static final _$subscribe =
      $grpc.ClientMethod<$0.SubscribeRequest, $0.TelemetryMessage>(
          '/pocketnet.v1.TelemetryService/Subscribe',
          ($0.SubscribeRequest value) => value.writeToBuffer(),
          $0.TelemetryMessage.fromBuffer);
  static final _$ackHighRisk =
      $grpc.ClientMethod<$0.AckHighRiskRequest, $0.AckHighRiskResponse>(
          '/pocketnet.v1.TelemetryService/AckHighRisk',
          ($0.AckHighRiskRequest value) => value.writeToBuffer(),
          $0.AckHighRiskResponse.fromBuffer);
  static final _$getObservedDevices =
      $grpc.ClientMethod<$0.ObservedDevicesRequest, $0.ObservedDevicesPage>(
          '/pocketnet.v1.TelemetryService/GetObservedDevices',
          ($0.ObservedDevicesRequest value) => value.writeToBuffer(),
          $0.ObservedDevicesPage.fromBuffer);
  static final _$setCaptureProfile = $grpc.ClientMethod<
          $0.SetCaptureProfileRequest, $0.ControlCommandResponse>(
      '/pocketnet.v1.TelemetryService/SetCaptureProfile',
      ($0.SetCaptureProfileRequest value) => value.writeToBuffer(),
      $0.ControlCommandResponse.fromBuffer);
  static final _$setObservationMode = $grpc.ClientMethod<
          $0.SetObservationModeRequest, $0.ControlCommandResponse>(
      '/pocketnet.v1.TelemetryService/SetObservationMode',
      ($0.SetObservationModeRequest value) => value.writeToBuffer(),
      $0.ControlCommandResponse.fromBuffer);
  static final _$controlRadioLab =
      $grpc.ClientMethod<$0.RadioLabRequest, $0.RadioLabStatus>(
          '/pocketnet.v1.TelemetryService/ControlRadioLab',
          ($0.RadioLabRequest value) => value.writeToBuffer(),
          $0.RadioLabStatus.fromBuffer);
  static final _$recoverComponent =
      $grpc.ClientMethod<$0.RecoverComponentRequest, $0.ControlCommandResponse>(
          '/pocketnet.v1.TelemetryService/RecoverComponent',
          ($0.RecoverComponentRequest value) => value.writeToBuffer(),
          $0.ControlCommandResponse.fromBuffer);
}

@$pb.GrpcServiceName('pocketnet.v1.TelemetryService')
abstract class TelemetryServiceBase extends $grpc.Service {
  $core.String get $name => 'pocketnet.v1.TelemetryService';

  TelemetryServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.SubscribeRequest, $0.TelemetryMessage>(
        'Subscribe',
        subscribe_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $0.SubscribeRequest.fromBuffer(value),
        ($0.TelemetryMessage value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.AckHighRiskRequest, $0.AckHighRiskResponse>(
            'AckHighRisk',
            ackHighRisk_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.AckHighRiskRequest.fromBuffer(value),
            ($0.AckHighRiskResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.ObservedDevicesRequest, $0.ObservedDevicesPage>(
            'GetObservedDevices',
            getObservedDevices_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.ObservedDevicesRequest.fromBuffer(value),
            ($0.ObservedDevicesPage value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SetCaptureProfileRequest,
            $0.ControlCommandResponse>(
        'SetCaptureProfile',
        setCaptureProfile_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.SetCaptureProfileRequest.fromBuffer(value),
        ($0.ControlCommandResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SetObservationModeRequest,
            $0.ControlCommandResponse>(
        'SetObservationMode',
        setObservationMode_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.SetObservationModeRequest.fromBuffer(value),
        ($0.ControlCommandResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.RadioLabRequest, $0.RadioLabStatus>(
        'ControlRadioLab', controlRadioLab_Pre, false, false,
        ($core.List<$core.int> value) => $0.RadioLabRequest.fromBuffer(value),
        ($0.RadioLabStatus value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.RecoverComponentRequest,
            $0.ControlCommandResponse>(
        'RecoverComponent',
        recoverComponent_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.RecoverComponentRequest.fromBuffer(value),
        ($0.ControlCommandResponse value) => value.writeToBuffer()));
  }

  $async.Stream<$0.TelemetryMessage> subscribe_Pre($grpc.ServiceCall $call,
      $async.Future<$0.SubscribeRequest> $request) async* {
    yield* subscribe($call, await $request);
  }

  $async.Stream<$0.TelemetryMessage> subscribe(
      $grpc.ServiceCall call, $0.SubscribeRequest request);

  $async.Future<$0.AckHighRiskResponse> ackHighRisk_Pre($grpc.ServiceCall $call,
      $async.Future<$0.AckHighRiskRequest> $request) async {
    return ackHighRisk($call, await $request);
  }

  $async.Future<$0.AckHighRiskResponse> ackHighRisk(
      $grpc.ServiceCall call, $0.AckHighRiskRequest request);

  $async.Future<$0.ObservedDevicesPage> getObservedDevices_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ObservedDevicesRequest> $request) async {
    return getObservedDevices($call, await $request);
  }

  $async.Future<$0.ObservedDevicesPage> getObservedDevices(
      $grpc.ServiceCall call, $0.ObservedDevicesRequest request);

  $async.Future<$0.ControlCommandResponse> setCaptureProfile_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.SetCaptureProfileRequest> $request) async {
    return setCaptureProfile($call, await $request);
  }

  $async.Future<$0.ControlCommandResponse> setCaptureProfile(
      $grpc.ServiceCall call, $0.SetCaptureProfileRequest request);

  $async.Future<$0.ControlCommandResponse> setObservationMode_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.SetObservationModeRequest> $request) async {
    return setObservationMode($call, await $request);
  }

  $async.Future<$0.ControlCommandResponse> setObservationMode(
      $grpc.ServiceCall call, $0.SetObservationModeRequest request);

  $async.Future<$0.RadioLabStatus> controlRadioLab_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.RadioLabRequest> $request) async {
    return controlRadioLab($call, await $request);
  }

  $async.Future<$0.RadioLabStatus> controlRadioLab(
      $grpc.ServiceCall call, $0.RadioLabRequest request);

  $async.Future<$0.ControlCommandResponse> recoverComponent_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.RecoverComponentRequest> $request) async {
    return recoverComponent($call, await $request);
  }

  $async.Future<$0.ControlCommandResponse> recoverComponent(
      $grpc.ServiceCall call, $0.RecoverComponentRequest request);
}
