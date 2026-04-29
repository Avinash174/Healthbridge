import 'package:get_it/get_it.dart';
import 'package:dio/dio.dart';
import 'package:healthbridge/core/network/dio_client.dart';
import 'package:healthbridge/core/storage/secure_storage.dart';
import 'package:healthbridge/data/datasources/remote_data_source.dart';
import 'package:healthbridge/data/datasources/local_data_source.dart';
import 'package:healthbridge/data/repositories/auth_repository_impl.dart';
import 'package:healthbridge/data/repositories/health_repository_impl.dart';
import 'package:healthbridge/domain/repositories/auth_repository.dart';
import 'package:healthbridge/domain/repositories/health_repository.dart';
import 'package:healthbridge/domain/usecases/sync_health_data_usecase.dart';
import 'package:healthbridge/presentation/blocs/auth/auth_bloc.dart';
import 'package:healthbridge/presentation/blocs/permission/permission_bloc.dart';
import 'package:healthbridge/presentation/blocs/sync/sync_bloc.dart';

final sl = GetIt.instance;

Future<void> setupServiceLocator() async {
  // Core
  sl.registerLazySingleton(() => SecureStorage());
  sl.registerLazySingleton(() => Dio());
  sl.registerLazySingleton(() => DioClient(sl(), sl()));

  // Data Sources
  sl.registerLazySingleton<RemoteDataSource>(
    () => RemoteDataSourceImpl(sl<DioClient>().dio),
  );
  sl.registerLazySingleton<LocalDataSource>(
    () => LocalDataSourceImpl(),
  );

  // Repositories
  sl.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(sl(), sl()),
  );
  sl.registerLazySingleton<HealthRepository>(
    () => HealthRepositoryImpl(
      remoteDataSource: sl(),
      localDataSource: sl(),
      storage: sl(),
    ),
  );

  // Use Cases
  sl.registerLazySingleton(() => SyncHealthDataUseCase(sl()));

  // BLoCs
  sl.registerFactory(() => AuthBloc(sl()));
  sl.registerFactory(() => SyncBloc(sl(), sl()));
  sl.registerFactory(() => PermissionBloc(sl()));
}
