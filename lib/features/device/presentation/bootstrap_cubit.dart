import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/device_registration.dart';
import '../domain/device_repository.dart';

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
  const BootstrapRegistered(this.registration);
  final DeviceRegistration registration;
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
      final registration = await _repository.register();
      emit(BootstrapRegistered(registration));
    } catch (e) {
      emit(BootstrapOffline(e.toString()));
    }
  }
}
