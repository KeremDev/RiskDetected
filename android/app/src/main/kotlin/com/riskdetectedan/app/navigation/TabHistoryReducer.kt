package com.riskdetectedan.app.navigation

internal data class TabHistorySnapshot(
    val active: RdTab,
    val history: List<RdTab>,
)

internal object TabHistoryReducer {
    fun select(current: TabHistorySnapshot, target: RdTab): TabHistorySnapshot {
        if (target == current.active) return current
        return TabHistorySnapshot(
            active = target,
            history = (current.history + current.active).takeLast(MAX_DEPTH),
        )
    }

    fun back(current: TabHistorySnapshot): TabHistorySnapshot {
        val previous = current.history.lastOrNull() ?: return current
        return TabHistorySnapshot(previous, current.history.dropLast(1))
    }

    private const val MAX_DEPTH = 16
}
