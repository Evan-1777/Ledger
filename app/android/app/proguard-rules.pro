# shared_preferences_android 2.5.0 calls Kotlin through Pigeon JNI. Its bindings
# resolve kotlin.coroutines.Continuation and related classes by name, but R8
# renames them in release builds. The descriptor used by the Dart side then no
# longer matches, so SharedPreferences.getInstance() throws NoSuchMethodError
# before runApp() and the app stays on the launch screen.
# Keep these classes until the plugin ships consumer rules:
# https://github.com/flutter/flutter/issues/194649
# https://github.com/flutter/packages/pull/13311
-keep class kotlin.Unit { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep class kotlin.coroutines.Continuation { *; }
-keep class kotlin.coroutines.intrinsics.CoroutineSingletons { *; }
-keep class kotlin.coroutines.intrinsics.IntrinsicsKt { *; }
