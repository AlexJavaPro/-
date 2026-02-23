package ru.amajo.photomailer.split

object BatchSplitter {
    fun <T> split(
        items: List<T>,
        limitBytes: Long,
        sizeSelector: (T) -> Long,
    ): List<List<T>> {
        require(limitBytes > 0) { "limitBytes must be > 0" }

        if (items.isEmpty()) {
            return emptyList()
        }

        data class SizedItem<T>(
            val item: T,
            val sizeBytes: Long,
            val sourceIndex: Int,
        )

        val sorted = items.mapIndexed { index, item ->
            SizedItem(
                item = item,
                sizeBytes = sizeSelector(item).coerceAtLeast(0L),
                sourceIndex = index,
            )
        }.sortedWith(
            compareByDescending<SizedItem<T>> { it.sizeBytes }
                .thenBy { it.sourceIndex },
        )

        val bins = mutableListOf<MutableList<T>>()
        val binSizes = mutableListOf<Long>()

        for (entry in sorted) {
            if (entry.sizeBytes > limitBytes) {
                bins += mutableListOf(entry.item)
                binSizes += entry.sizeBytes
                continue
            }

            var targetIndex = -1
            for (index in bins.indices) {
                if (binSizes[index] + entry.sizeBytes <= limitBytes) {
                    targetIndex = index
                    break
                }
            }

            if (targetIndex >= 0) {
                bins[targetIndex] += entry.item
                binSizes[targetIndex] += entry.sizeBytes
            } else {
                bins += mutableListOf(entry.item)
                binSizes += entry.sizeBytes
            }
        }
        return bins.map { it.toList() }
    }
}
