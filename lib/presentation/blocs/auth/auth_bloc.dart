import 'dart:developer' as dev;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/repositories/auth_repository.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository authRepository;

  AuthBloc(this.authRepository) : super(AuthInitial()) {
    on<LoginRequested>((event, emit) async {
      dev.log('LoginRequested for ${event.email}', name: 'AuthBloc');
      emit(AuthLoading());
      final result = await authRepository.login(event.email, event.password);
      result.fold(
        (failure) {
          dev.log('Login failed: ${failure.message}', name: 'AuthBloc');
          emit(AuthError(failure.message));
        },
        (token) {
          dev.log('Login successful', name: 'AuthBloc');
          emit(Authenticated(token));
        },
      );
    });

    on<LogoutRequested>((event, emit) async {
      dev.log('LogoutRequested', name: 'AuthBloc');
      await authRepository.logout();
      emit(Unauthenticated());
    });

    on<CheckAuthStatus>((event, emit) async {
      dev.log('CheckAuthStatus', name: 'AuthBloc');
      final isLoggedInResult = await authRepository.isLoggedIn();
      isLoggedInResult.fold(
        (_) => emit(Unauthenticated()),
        (isLoggedIn) {
          dev.log('Auth check: isLoggedIn=$isLoggedIn', name: 'AuthBloc');
          isLoggedIn ? emit(const Authenticated('cached_token')) : emit(Unauthenticated());
        },
      );
    });
  }
}
