import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'current_location_layer.dart';
import 'data.dart';
import 'exception/incorrect_setup_exception.dart';
import 'exception/permission_denied_exception.dart' as lm;
import 'exception/permission_requesting_exception.dart' as lm;
import 'exception/service_disabled_exception.dart';

/// Helper class for converting the data stream which provide data in required
/// format from stream created by some existing plugin.
class LocationMarkerDataStreamFactory {
  /// Create a LocationMarkerDataStreamFactory.
  const LocationMarkerDataStreamFactory();

  /// Cast to a position stream from
  /// [geolocator](https://pub.dev/packages/geolocator) stream.
  Stream<LocationMarkerPosition?> fromGeolocatorPositionStream({
    Stream<Position?>? stream,
  }) {
    return (stream ?? defaultPositionStreamSource()).map((Position? position) {
      return position != null
          ? LocationMarkerPosition(
              latitude: position.latitude,
              longitude: position.longitude,
              accuracy: position.accuracy,
            )
          : null;
    });
  }

  /// Cast to a position stream from
  /// [geolocator](https://pub.dev/packages/geolocator) stream.
  @Deprecated('Use fromGeolocatorPositionStream instead')
  Stream<LocationMarkerPosition?> geolocatorPositionStream({
    Stream<Position?>? stream,
  }) =>
      fromGeolocatorPositionStream(
        stream: stream,
      );

  /// Create a position stream which is used as default value of
  /// [CurrentLocationLayer.positionStream].
  Stream<Position?> defaultPositionStreamSource() {
    final List<AsyncCallback> cancelFunctions = [];
    final streamController = StreamController<Position?>.broadcast(
      onCancel: () =>
          Future.wait(cancelFunctions.map((callback) => callback())),
    );
    streamController.onListen = () async {
      try {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          streamController.sink
              .addError(const lm.PermissionRequestingException());
          permission = await Geolocator.requestPermission();
        }
        switch (permission) {
          case LocationPermission.denied:
          case LocationPermission.deniedForever:
            streamController.sink
              ..addError(const lm.PermissionDeniedException())
              ..close();
            break;
          case LocationPermission.whileInUse:
          case LocationPermission.always:
            try {
              final serviceEnabled =
                  await Geolocator.isLocationServiceEnabled();
              if (!serviceEnabled) {
                streamController.sink
                    .addError(const ServiceDisabledException());
              }
            } catch (_) {}
            try {
              final subscription =
                  Geolocator.getServiceStatusStream().listen((serviceStatus) {
                if (serviceStatus == ServiceStatus.enabled) {
                  streamController.sink.add(null);
                } else {
                  streamController.sink
                      .addError(const ServiceDisabledException());
                }
              });
              cancelFunctions.add(subscription.cancel);
            } catch (_) {}
            try {
              final lastKnown = await Geolocator.getLastKnownPosition();
              if (lastKnown != null) {
                streamController.sink.add(lastKnown);
              }
            } catch (_) {}
            try {
              streamController.sink.add(await Geolocator.getCurrentPosition());
            } catch (_) {}
            final subscription =
                Geolocator.getPositionStream().listen((position) {
              streamController.sink.add(position);
            });
            cancelFunctions.add(subscription.cancel);
            break;
          case LocationPermission.unableToDetermine:
            break;
        }
      } on PermissionDefinitionsNotFoundException {
        streamController.sink.addError(const IncorrectSetupException());
      }
    };
    return streamController.stream;
  }
}
