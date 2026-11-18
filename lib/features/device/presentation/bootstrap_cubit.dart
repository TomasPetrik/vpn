import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/device_registration.dart';
import '../domain/device_repository.dart';
import '../domain/device_session.dart';

sealed class BootstrapState {
  const BootstrapState();
}

class BootstrapInitial extends BootstrapState {
  const BootstrapInitial();
}

class BootstrapRegistering extends BootstrapState {
  const BootstrapRegistering();
}

class BootstrapRegistered extends BootstrapState {
  const BootstrapRegistered(this.registration, {this.session});
  final DeviceRegistration registration;
  final DeviceSession? session;
}

class BootstrapOffline extends BootstrapState {
  const BootstrapOffline(this.message);
  final String message;
}

class BootstrapCubit extends Cubit<BootstrapState> {
  BootstrapCubit(this._repository) : super(const BootstrapInitial());

  final DeviceRepository _repository;

  Future<void> start() async {
    emit(const BootstrapRegistering());
    try {
      final session = await _repository.ensureSession();
      emit(
        BootstrapRegistered(
          DeviceRegistration(
            userId: session.userId,
            deviceId: session.deviceId,
            created: false,
          ),
          session: session,
        ),
      );
    } catch (e) {
      emit(BootstrapOffline(e.toString()));
    }
  }
}
