package com.riskdetectedan.core.common

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import javax.inject.Inject
import javax.inject.Qualifier
import javax.inject.Singleton

@Qualifier
@Retention(AnnotationRetention.BINARY)
annotation class RdDispatcher(val type: RdDispatcherType)

enum class RdDispatcherType { Default, IO, Main }

/**
 * Injectable dispatcher provider so ViewModels/repositories never call [Dispatchers] directly —
 * keeps them swappable for `core:testing`'s TestDispatcher rule (review §8 test-coverage rule).
 */
@Singleton
class RdDispatchers @Inject constructor() {
    val default: CoroutineDispatcher = Dispatchers.Default
    val io: CoroutineDispatcher = Dispatchers.IO
    val main: CoroutineDispatcher = Dispatchers.Main
}
